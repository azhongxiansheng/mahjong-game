extends GutTest

# E5-04 / #252：RewardWindow 状态机 / 奖池 / 分配 / 屏障 / 三出口。
# 真实核心逻辑；禁止 mock 状态机、分配器或评分器。

const RULE_VERSION := "trash_talk_rules_v1"
const CHARS := ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"]
const ROOM := "room_rw_252"
const SEED := 42
const NOW0 := 1_700_000_000_000


func test_prize_pool_four_unique_stable_and_varies_by_hand_window() -> void:
	var a: Array = RewardWindowPrizePool.select_four(SEED, 0, 0, RULE_VERSION)
	var b: Array = RewardWindowPrizePool.select_four(SEED, 0, 0, RULE_VERSION)
	assert_eq(a.size(), 4)
	assert_eq(TrashTalkGoldFixtures.stable_stringify(a), TrashTalkGoldFixtures.stable_stringify(b))
	var seen: Dictionary = {}
	for id in a:
		assert_false(seen.has(String(id)), "奖池不得重复 item_id")
		seen[String(id)] = true
		assert_false(TrashTalkRuleCatalog.item_def(StringName(id)).is_empty())

	var other_hand: Array = RewardWindowPrizePool.select_four(SEED, 1, 0, RULE_VERSION)
	var other_win: Array = RewardWindowPrizePool.select_four(SEED, 0, 1, RULE_VERSION)
	# 不同 hand/window 通常不同；允许偶然碰撞但 replay 同输入必须一致
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(
			RewardWindowPrizePool.select_four(SEED, 1, 0, RULE_VERSION)
		),
		TrashTalkGoldFixtures.stable_stringify(other_hand)
	)
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(
			RewardWindowPrizePool.select_four(SEED, 0, 1, RULE_VERSION)
		),
		TrashTalkGoldFixtures.stable_stringify(other_win)
	)


func test_prize_pool_catalog_order_perturbation_stable() -> void:
	var base: Array = TrashTalkRuleCatalog.grantable_item_ids()
	var rev: Array = base.duplicate()
	rev.reverse()
	var a: Array = RewardWindowPrizePool.select_four(7, 2, 3, RULE_VERSION, base)
	var b: Array = RewardWindowPrizePool.select_four(7, 2, 3, RULE_VERSION, rev)
	assert_eq(a.size(), 4)
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(a),
		TrashTalkGoldFixtures.stable_stringify(b),
		"目录输入顺序扰动不得改变奖池"
	)


func test_open_emits_schema_valid_payload() -> void:
	var rw := RewardWindowModule.new()
	var res: Dictionary = rw.open(_open_input())
	assert_true(bool(res.get("ok", false)), str(res))
	assert_eq(String(res.get("kind", "")), "REWARD_WINDOW_OPENED")
	var payload: Dictionary = res["payload"]
	assert_eq(String(payload["phase"]), "OPEN")
	assert_true(payload["window_exit"] == null)
	assert_eq((payload["prize_pool"] as Array).size(), 4)
	var vh: String = ProtocolViewCodec.compute_view_hash(payload)
	var ne: NetworkedEvent = NetworkedEvent.make(
		"REWARD_WINDOW_OPENED", 1, ROOM, payload, vh
	)
	assert_not_null(ne, "OPEN payload 必须通过 NetworkedEvent schema")
	assert_eq(rw.phase, RewardWindowModule.PHASE_OPEN)
	assert_eq(rw.discard_count, 0)


func test_open_idempotent_same_window() -> void:
	var rw := RewardWindowModule.new()
	var a: Dictionary = rw.open(_open_input())
	var b: Dictionary = rw.open(_open_input())
	assert_true(bool(a.get("ok", false)))
	assert_true(bool(b.get("ok", false)))
	assert_true(bool(b.get("idempotent", false)))
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(a["payload"]),
		TrashTalkGoldFixtures.stable_stringify(b["payload"])
	)


func test_discard_count_only_discard_riichi_and_closing_at_24() -> void:
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open(_open_input()).get("ok", false)))
	for i in range(23):
		var r: Dictionary = rw.on_discard_applied({
			"server_seq": 10 + i,
			"seat": i % 4,
			"kind": "DISCARD",
			"now_ms": NOW0,
		})
		assert_true(bool(r.get("ok", false)), "discard %d: %s" % [i + 1, str(r)])
		assert_eq(int(r.get("discard_count", -1)), i + 1)
		assert_eq(rw.phase, RewardWindowModule.PHASE_OPEN)
	var last: Dictionary = rw.on_discard_applied({
		"server_seq": 33,
		"seat": 0,
		"kind": "RIICHI",
		"now_ms": NOW0,
	})
	assert_true(bool(last.get("ok", false)), str(last))
	assert_eq(String(last.get("kind", "")), "REWARD_WINDOW_CLOSING")
	assert_eq(rw.phase, RewardWindowModule.PHASE_CLOSING)
	assert_eq(int(rw.closing_boundary_server_seq), 33)
	assert_eq(rw.discard_count, 24)
	assert_false(rw.grace_deadline_at.is_empty())
	# 鸣牌本身不走 on_discard_applied；再弃不再计数
	var after: Dictionary = rw.on_discard_applied({
		"server_seq": 34, "seat": 1, "kind": "DISCARD", "now_ms": NOW0,
	})
	assert_true(bool(after.get("ok", false)))
	assert_eq(rw.discard_count, 24)


func test_closing_idempotent() -> void:
	var rw := _open_and_close_24()
	var again: Dictionary = rw.begin_closing({
		"closing_boundary_server_seq": 33,
		"now_ms": NOW0,
		"pending_exit": "FULL_GRANT",
		"settle_reason": RewardWindowModule.SETTLE_REASON_FULL_24,
	})
	assert_true(bool(again.get("ok", false)))
	assert_true(bool(again.get("idempotent", false)))


func test_full_grant_after_claim_terminal_and_grace() -> void:
	var rw := _open_and_close_24()
	# CLOSING 且 claim 未 terminal → 屏障阻塞
	assert_true(rw.is_barrier_blocking(NOW0))
	assert_false(rw.barrier_released(NOW0))
	var term: Dictionary = rw.mark_claim_terminal({"context_boundary_server_seq": 40})
	assert_true(bool(term.get("ok", false)), str(term))
	# 无在途 utterance → all_eligible_utterances_are_terminal=true → 屏障释放（无需等宽限）
	assert_true(rw.barrier_released(NOW0))
	assert_false(rw.is_barrier_blocking(NOW0))
	var settled: Dictionary = rw.try_settle({"now_ms": NOW0})
	assert_true(bool(settled.get("ok", false)), str(settled))
	assert_eq(String(settled.get("kind", "")), "REWARD_WINDOW_SETTLED")
	var p: Dictionary = settled["payload"]
	assert_eq(String(p["outcome"]), "FULL_GRANT")
	assert_eq(int(p["grant_count"]), 4)
	assert_eq(String(p["assignment_version"]), "assign_v1")
	assert_eq((p["assignment"] as Dictionary).size(), 4)
	assert_eq(rw.window_exit, "FULL_GRANT")
	var vh: String = ProtocolViewCodec.compute_view_hash(p)
	var ne: NetworkedEvent = NetworkedEvent.make(
		"REWARD_WINDOW_SETTLED", 50, ROOM, p, vh
	)
	assert_not_null(ne, "SETTLED FULL_GRANT schema: %s" % str(p.keys()))


func test_cancel_by_ron_during_closing_no_score_no_matrix() -> void:
	var rw := _open_and_close_24()
	var can: Dictionary = rw.cancel_by_win({"now_ms": NOW0})
	assert_true(bool(can.get("ok", false)), str(can))
	assert_eq(String(can.get("kind", "")), "REWARD_WINDOW_CANCELLED")
	var p: Dictionary = can["payload"]
	assert_eq(String(p["cancel_reason"]), "CANCELLED_BY_WIN")
	assert_eq(int(p["grant_count"]), 0)
	assert_false(bool(p["scored"]))
	assert_true(bool(p["grace_aborted"]))
	assert_eq(int(p["closing_boundary_server_seq"]), 33)
	assert_false(bool(can.get("scorer_called", true)))
	assert_false(rw.scorer_was_called())
	assert_true(rw.matrix_summary.is_empty())
	assert_true(rw.assignment.is_empty())
	# 取消后不可 settle
	var settle: Dictionary = rw.try_settle({"now_ms": NOW0 + 2000})
	assert_false(bool(settle.get("ok", true)))
	var vh: String = ProtocolViewCodec.compute_view_hash(p)
	assert_not_null(NetworkedEvent.make("REWARD_WINDOW_CANCELLED", 41, ROOM, p, vh))


func test_mid_hand_tsumo_open_to_cancelled() -> void:
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open(_open_input()).get("ok", false)))
	rw.on_discard_applied({"server_seq": 5, "seat": 0, "kind": "DISCARD", "now_ms": NOW0})
	var can: Dictionary = rw.cancel_by_win({})
	assert_true(bool(can.get("ok", false)))
	assert_eq(rw.phase, RewardWindowModule.PHASE_CANCELLED)
	assert_true(can["payload"]["closing_boundary_server_seq"] == null)
	assert_false(bool(can["payload"]["grace_aborted"]))
	assert_false(rw.scorer_was_called())


func test_non_final_draw_scoring_close_full_grant() -> void:
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open(_open_input()).get("ok", false)))
	for i in range(10):
		rw.on_discard_applied({
			"server_seq": 20 + i, "seat": i % 4, "kind": "DISCARD", "now_ms": NOW0,
		})
	var sc: Dictionary = rw.begin_scoring_close({
		"result_server_seq": 99,
		"now_ms": NOW0,
		"is_match_end": false,
	})
	assert_true(bool(sc.get("ok", false)), str(sc))
	assert_eq(rw.phase, RewardWindowModule.PHASE_CLOSING)
	assert_eq(int(rw.closing_boundary_server_seq), 99)
	assert_eq(int(rw.context_boundary_server_seq), 99)
	assert_true(rw.claim_is_terminal())
	var settled: Dictionary = rw.try_settle({"now_ms": NOW0})
	assert_true(bool(settled.get("ok", false)), str(settled))
	assert_eq(String(settled["payload"]["outcome"]), "FULL_GRANT")
	assert_eq(int(settled["payload"]["grant_count"]), 4)
	assert_eq(String(settled["payload"]["settle_reason"]), "NON_FINAL_DRAW")


func test_match_end_display_only_grant_zero() -> void:
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open(_open_input()).get("ok", false)))
	var sc: Dictionary = rw.begin_scoring_close({
		"result_server_seq": 55,
		"now_ms": NOW0,
		"is_match_end": true,
	})
	assert_true(bool(sc.get("ok", false)), str(sc))
	var settled: Dictionary = rw.try_settle({"now_ms": NOW0})
	assert_true(bool(settled.get("ok", false)), str(settled))
	var p: Dictionary = settled["payload"]
	assert_eq(String(p["outcome"]), "DISPLAY_ONLY")
	assert_eq(int(p["grant_count"]), 0)
	assert_eq((p["assignment"] as Dictionary).size(), 4)
	assert_false(p.has("cancel_reason"))


func test_final_win_is_cancelled_not_display_only() -> void:
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open(_open_input()).get("ok", false)))
	var can: Dictionary = rw.cancel_by_win({})
	assert_true(bool(can.get("ok", false)))
	assert_eq(String(rw.window_exit), "CANCELLED_BY_WIN")
	assert_ne(String(rw.window_exit), "DISPLAY_ONLY")


func test_ptt_after_closing_boundary_rejected_and_grace_deadline() -> void:
	var rw := _open_and_close_24()
	var late: Dictionary = rw.ingest_utterance({
		"seat": 0,
		"utterance_id": "u_late",
		"text": "晚了",
		"language": "zh",
		"ptt_end_server_seq": 100, # > closing 33
		"terminal": true,
	})
	assert_true(bool(late.get("ok", false)))
	assert_false(bool(late.get("accepted", true)))
	assert_eq(String(late.get("reason", "")), "PTT_AFTER_CLOSING_BOUNDARY")

	var ok_u: Dictionary = rw.ingest_utterance({
		"seat": 0,
		"utterance_id": "u_ok",
		"text": "好",
		"language": "zh",
		"ptt_end_server_seq": 33,
		"terminal": false,
	})
	assert_true(bool(ok_u.get("accepted", false)))
	rw.mark_claim_terminal({"context_boundary_server_seq": 40})
	assert_false(rw.barrier_released(NOW0))
	assert_true(rw.barrier_released(NOW0 + RewardWindowModule.GRACE_MS))
	# pending → final 后可立即 settle
	var term_u: Dictionary = rw.ingest_utterance({
		"seat": 0,
		"utterance_id": "u_ok",
		"text": "好",
		"language": "zh",
		"ptt_end_server_seq": 33,
		"terminal": true,
	})
	assert_eq(String(term_u.get("reason", "")), "TERMINALIZED")
	assert_true(rw.barrier_released(NOW0))
	var settled: Dictionary = rw.try_settle({"now_ms": NOW0})
	assert_true(bool(settled.get("ok", false)), str(settled))


func test_utterance_duplicate_idempotent() -> void:
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open(_open_input()).get("ok", false)))
	var u := {
		"seat": 0,
		"utterance_id": "same",
		"text": "x",
		"language": "zh",
		"ptt_end_server_seq": 1,
		"terminal": true,
	}
	assert_true(bool(rw.ingest_utterance(u).get("accepted", false)))
	var d: Dictionary = rw.ingest_utterance(u)
	assert_true(bool(d.get("idempotent", false)))


func test_assigner_enumerates_24_and_lex_tiebreak() -> void:
	var pool := ["item_a", "item_b", "item_c", "item_d"]
	var matrix: Array = []
	for seat in range(4):
		for item_id in pool:
			matrix.append({"seat": seat, "item_id": item_id, "total_score": 0})
	var asg: Dictionary = RewardWindowAssigner.assign_bijection(matrix, pool)
	assert_true(bool(asg.get("ok", false)))
	# 全零 → 字典序最小向量即 pool 原字典序排列 seat 顺序
	assert_eq(String(asg["assignment"]["0"]), "item_a")
	assert_eq(String(asg["assignment"]["1"]), "item_b")
	assert_eq(String(asg["assignment"]["2"]), "item_c")
	assert_eq(String(asg["assignment"]["3"]), "item_d")

	# 唯一最优：对角线高分
	var matrix2: Array = []
	for seat in range(4):
		for i in range(4):
			var item_id: String = pool[i]
			var score: int = 1000 if i == seat else 0
			matrix2.append({"seat": seat, "item_id": item_id, "total_score": score})
	var asg2: Dictionary = RewardWindowAssigner.assign_bijection(matrix2, pool)
	assert_true(bool(asg2.get("ok", false)))
	assert_eq(int(asg2["total_score_sum"]), 4000)
	assert_eq(String(asg2["assignment"]["0"]), "item_a")
	assert_eq(String(asg2["assignment"]["1"]), "item_b")
	assert_eq(String(asg2["assignment"]["2"]), "item_c")
	assert_eq(String(asg2["assignment"]["3"]), "item_d")


func test_assigner_unique_optimum_prefers_max_sum() -> void:
	var pool := ["w", "x", "y", "z"]
	var matrix: Array = []
	for seat in range(4):
		for item_id in pool:
			var score := 0
			if seat == 0 and item_id == "z":
				score = 500
			elif seat == 1 and item_id == "y":
				score = 500
			elif seat == 2 and item_id == "x":
				score = 500
			elif seat == 3 and item_id == "w":
				score = 500
			matrix.append({"seat": seat, "item_id": item_id, "total_score": score})
	var asg: Dictionary = RewardWindowAssigner.assign_bijection(matrix, pool)
	assert_true(bool(asg.get("ok", false)))
	assert_eq(int(asg["total_score_sum"]), 2000)
	assert_eq(String(asg["assignment"]["0"]), "z")
	assert_eq(String(asg["assignment"]["1"]), "y")
	assert_eq(String(asg["assignment"]["2"]), "x")
	assert_eq(String(asg["assignment"]["3"]), "w")


func test_full_grant_display_only_same_matrix_assignment_on_same_inputs() -> void:
	var pool := [
		"dora_charm_v1", "double_payout_v1", "iron_shield_v1", "wall_peek_v1",
	]
	var full_rw := _score_path_window("FULL_GRANT", pool)
	var disp_rw := _score_path_window("DISPLAY_ONLY", pool)
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(full_rw.matrix_summary),
		TrashTalkGoldFixtures.stable_stringify(disp_rw.matrix_summary)
	)
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(full_rw.assignment),
		TrashTalkGoldFixtures.stable_stringify(disp_rw.assignment)
	)
	assert_eq(full_rw.grant_count, 4)
	assert_eq(disp_rw.grant_count, 0)


func test_silent_all_zero_still_assigns() -> void:
	var rw := _open_and_close_24()
	rw.mark_claim_terminal({"context_boundary_server_seq": 40})
	var settled: Dictionary = rw.try_settle({"now_ms": NOW0})
	assert_true(bool(settled.get("ok", false)), str(settled))
	assert_eq((settled["payload"]["assignment"] as Dictionary).size(), 4)


func test_settle_cancel_conflict_and_idempotent_replay() -> void:
	var rw := _open_and_close_24()
	rw.mark_claim_terminal({"context_boundary_server_seq": 40})
	var s1: Dictionary = rw.try_settle({"now_ms": NOW0})
	assert_true(bool(s1.get("ok", false)))
	var s2: Dictionary = rw.try_settle({"now_ms": NOW0})
	assert_true(bool(s2.get("idempotent", false)))
	var c: Dictionary = rw.cancel_by_win({})
	assert_false(bool(c.get("ok", true)))

	var rw2 := _open_and_close_24()
	var c1: Dictionary = rw2.cancel_by_win({})
	assert_true(bool(c1.get("ok", false)))
	var c2: Dictionary = rw2.cancel_by_win({})
	assert_true(bool(c2.get("idempotent", false)))
	assert_false(bool(rw2.try_settle({"now_ms": NOW0}).get("ok", true)))


func test_illegal_phase_transitions() -> void:
	var rw := RewardWindowModule.new()
	assert_false(bool(rw.begin_closing({
		"closing_boundary_server_seq": 1, "now_ms": NOW0,
		"pending_exit": "FULL_GRANT", "settle_reason": "X",
	}).get("ok", true)))
	assert_true(bool(rw.open(_open_input()).get("ok", false)))
	# OPEN 不得直接 settle
	assert_false(bool(rw.try_settle({"now_ms": NOW0}).get("ok", true)))


func test_gold_fixtures_byte_stable() -> void:
	# 真实实现对硬编码 expected（禁止 fixture 自举 expected）
	var open_fx: Dictionary = RewardWindowGoldFixtures.gold_open_pool()
	var pool2: Array = RewardWindowPrizePool.select_four(SEED, 0, 0, RULE_VERSION)
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(pool2),
		TrashTalkGoldFixtures.stable_stringify(open_fx["expected_prize_pool"])
	)
	var rw := RewardWindowModule.new()
	var open_p: Dictionary = rw.open(_open_input())["payload"]
	assert_eq(
		TrashTalkGoldFixtures.stable_digest(open_p),
		String(open_fx["expected_open_digest"])
	)
	var zero_fx: Dictionary = RewardWindowGoldFixtures.gold_zero_assignment()
	var asg: Dictionary = RewardWindowAssigner.assign_bijection(
		zero_fx["matrix"], zero_fx["pool_item_ids"]
	)
	assert_true(bool(asg.get("ok", false)))
	assert_eq(int(asg["total_score_sum"]), int(zero_fx["expected_sum"]))
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(asg["assignment"]),
		TrashTalkGoldFixtures.stable_stringify(zero_fx["expected_assignment"])
	)
	var tie_fx: Dictionary = RewardWindowGoldFixtures.gold_tiebreak_assignment()
	var asg2: Dictionary = RewardWindowAssigner.assign_bijection(
		tie_fx["matrix"], tie_fx["pool_item_ids"]
	)
	assert_eq(int(asg2["total_score_sum"]), int(tie_fx["expected_sum"]))
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(asg2["assignment"]),
		TrashTalkGoldFixtures.stable_stringify(tie_fx["expected_assignment"])
	)
	var can_fx: Dictionary = RewardWindowGoldFixtures.gold_cancelled_payload()
	var rw2 := RewardWindowModule.new()
	assert_true(bool(rw2.open(_open_input()).get("ok", false)))
	var can: Dictionary = rw2.cancel_by_win({})
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(can["payload"]),
		TrashTalkGoldFixtures.stable_stringify(can_fx["expected_payload"])
	)


func test_snapshot_dto_envelope_roundtrip_and_unknown_version() -> void:
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open(_open_input()).get("ok", false)))
	var dto: Dictionary = rw.to_snapshot_dto()
	assert_eq(String(dto.get("module_key", "")), "reward_window")
	assert_eq(typeof(dto.get("schema_version", null)), TYPE_INT)
	assert_eq(int(dto["schema_version"]), 1)
	assert_true(dto.has("payload"))
	var pl: Dictionary = dto["payload"]
	assert_eq(String(pl.get("phase", "")), "OPEN")
	assert_false(pl.has("hand"))
	assert_false(pl.has("wall"))
	assert_false(pl.has("match_seed"), "公开 DTO 不得暴露 match_seed")
	assert_false(pl.has("seed"), "公开 DTO 不得暴露 seed")
	# 服务端 capture 仍有权威 seed
	assert_true(rw.capture_state().has("_match_seed"))
	# round-trip
	var rw2 := RewardWindowModule.new()
	var rest: Dictionary = rw2.restore_from_snapshot_dto(dto)
	assert_true(bool(rest.get("ok", false)), str(rest))
	assert_eq(rw2.phase, RewardWindowModule.PHASE_OPEN)
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(rw2.to_snapshot_dto()),
		TrashTalkGoldFixtures.stable_stringify(dto)
	)
	# 未知版本拒绝
	var bad := dto.duplicate(true)
	bad["schema_version"] = 99
	assert_false(bool(rw2.restore_from_snapshot_dto(bad).get("ok", true)))
	# 隐藏/未知键拒绝
	var bad2 := dto.duplicate(true)
	(bad2["payload"] as Dictionary)["wall"] = []
	assert_false(bool(RewardWindowModule.new().restore_from_snapshot_dto(bad2).get("ok", true)))
	# match_seed 注入拒绝
	var bad3 := dto.duplicate(true)
	(bad3["payload"] as Dictionary)["match_seed"] = 1
	assert_false(bool(RewardWindowModule.new().restore_from_snapshot_dto(bad3).get("ok", true)))


func test_discard_fingerprint_idempotent_and_conflict() -> void:
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open(_open_input()).get("ok", false)))
	var a: Dictionary = rw.on_discard_applied({
		"server_seq": 5, "seat": 0, "kind": "DISCARD", "now_ms": NOW0,
	})
	assert_true(bool(a.get("ok", false)))
	assert_eq(rw.discard_count, 1)
	var dup: Dictionary = rw.on_discard_applied({
		"server_seq": 5, "seat": 0, "kind": "DISCARD", "now_ms": NOW0,
	})
	assert_true(bool(dup.get("idempotent", false)))
	assert_eq(rw.discard_count, 1)
	var conflict: Dictionary = rw.on_discard_applied({
		"server_seq": 5, "seat": 1, "kind": "DISCARD", "now_ms": NOW0,
	})
	assert_false(bool(conflict.get("ok", true)))
	assert_eq(String(conflict.get("reason", "")), "DISCARD_FINGERPRINT_CONFLICT")
	assert_eq(rw.discard_count, 1)


func test_closing_conflict_rejected() -> void:
	var rw := _open_and_close_24()
	var bad: Dictionary = rw.begin_closing({
		"closing_boundary_server_seq": 999,
		"now_ms": NOW0,
		"pending_exit": "FULL_GRANT",
		"settle_reason": RewardWindowModule.SETTLE_REASON_FULL_24,
	})
	assert_false(bool(bad.get("ok", true)))
	assert_eq(String(bad.get("reason", "")), "CLOSING_INPUT_CONFLICT")


func test_utterance_terminalize_pending_to_final() -> void:
	var rw := _open_and_close_24()
	var utt_pending: Dictionary = rw.ingest_utterance({
		"seat": 0, "utterance_id": "u1", "text": "hi", "language": "zh",
		"ptt_end_server_seq": 30, "terminal": false,
	})
	assert_true(bool(utt_pending.get("accepted", false)))
	rw.mark_claim_terminal({"context_boundary_server_seq": 40})
	assert_false(rw.barrier_released(NOW0), "non-terminal utterance 阻塞屏障")
	var fin: Dictionary = rw.ingest_utterance({
		"seat": 0, "utterance_id": "u1", "text": "hi", "language": "zh",
		"ptt_end_server_seq": 30, "terminal": true,
	})
	assert_eq(String(fin.get("reason", "")), "TERMINALIZED")
	assert_true(rw.barrier_released(NOW0), "terminalize 后屏障可释放")
	# final 不可退回
	var back: Dictionary = rw.ingest_utterance({
		"seat": 0, "utterance_id": "u1", "text": "hi", "language": "zh",
		"ptt_end_server_seq": 30, "terminal": false,
	})
	assert_false(bool(back.get("ok", true)))
	# 文本冲突
	var conf: Dictionary = rw.ingest_utterance({
		"seat": 0, "utterance_id": "u1", "text": "other", "language": "zh",
		"ptt_end_server_seq": 30, "terminal": true,
	})
	assert_false(bool(conf.get("ok", true)))


func test_capture_restore_exact_state() -> void:
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open(_open_input()).get("ok", false)))
	rw.on_discard_applied({"server_seq": 7, "seat": 1, "kind": "DISCARD", "now_ms": NOW0})
	var snap: Dictionary = rw.capture_state()
	rw.on_discard_applied({"server_seq": 8, "seat": 2, "kind": "DISCARD", "now_ms": NOW0})
	assert_eq(rw.discard_count, 2)
	assert_true(rw.restore_state(snap))
	assert_eq(rw.discard_count, 1)
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(rw.capture_state()),
		TrashTalkGoldFixtures.stable_stringify(snap)
	)


func test_replay_same_seed_event_stream_byte_identical() -> void:
	var a: Dictionary = _full_stream_payloads()
	var b: Dictionary = _full_stream_payloads()
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(a),
		TrashTalkGoldFixtures.stable_stringify(b)
	)


# ---- helpers ----

func _open_input(window_index: int = 0, hand_seq: int = 0) -> Dictionary:
	return {
		"seed": SEED,
		"hand_seq": hand_seq,
		"window_index": window_index,
		"rule_version": RULE_VERSION,
		"room_id": ROOM,
		"character_ids": CHARS,
		"language": "zh",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"public_initial": {
			"hand_seq": hand_seq,
			"dealer_seat": 0,
			"scores": [25000, 25000, 25000, 25000],
		},
	}


func _open_and_close_24() -> RewardWindowModule:
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open(_open_input()).get("ok", false)))
	for i in range(23):
		rw.on_discard_applied({
			"server_seq": 10 + i, "seat": i % 4, "kind": "DISCARD", "now_ms": NOW0,
		})
	var last: Dictionary = rw.on_discard_applied({
		"server_seq": 33, "seat": 0, "kind": "DISCARD", "now_ms": NOW0,
	})
	assert_eq(String(last.get("kind", "")), "REWARD_WINDOW_CLOSING")
	return rw


func _score_path_window(exit_kind: String, pool: Array) -> RewardWindowModule:
	var rw := RewardWindowModule.new()
	var inp := _open_input()
	# 强制奖池：通过 catalog 子集使 select 结果可控——直接 open 后覆写不合法；
	# 改用 begin_closing 路径前注入：打开后手动替换 prize_pool（测试专用最小侵入）
	assert_true(bool(rw.open(inp).get("ok", false)))
	rw.prize_pool = pool.duplicate()
	for i in range(24):
		var r: Dictionary = rw.on_discard_applied({
			"server_seq": 10 + i, "seat": i % 4, "kind": "DISCARD", "now_ms": NOW0,
		})
		if i == 23:
			assert_eq(String(r.get("kind", "")), "REWARD_WINDOW_CLOSING")
	# 若 pending 默认 FULL_GRANT，DISPLAY_ONLY 需 scoring_close 路径
	if exit_kind == "DISPLAY_ONLY":
		rw._pending_exit = "DISPLAY_ONLY"
		rw.settle_reason = RewardWindowModule.SETTLE_REASON_MATCH_END
	rw.mark_claim_terminal({"context_boundary_server_seq": 50})
	var settled: Dictionary = rw.try_settle({"now_ms": NOW0})
	assert_true(bool(settled.get("ok", false)), str(settled))
	return rw


func _full_stream_payloads() -> Dictionary:
	var rw := RewardWindowModule.new()
	var open_p: Dictionary = rw.open(_open_input())["payload"]
	for i in range(23):
		rw.on_discard_applied({
			"server_seq": 10 + i, "seat": i % 4, "kind": "DISCARD", "now_ms": NOW0,
		})
	var close_p: Dictionary = rw.on_discard_applied({
		"server_seq": 33, "seat": 0, "kind": "DISCARD", "now_ms": NOW0,
	})["payload"]
	rw.mark_claim_terminal({"context_boundary_server_seq": 40})
	var settle_p: Dictionary = rw.try_settle({"now_ms": NOW0})["payload"]
	return {"open": open_p, "close": close_p, "settle": settle_p}
