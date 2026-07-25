extends GutTest

# E5-06 / #254 rework-5：真实 journal FULL_GRANT + 公开 API 三出口 + 精确多语。

const BalScr = preload("res://meta/reward_feedback_balance_fixtures.gd")
const ProjScr = preload("res://ui/four_player_table/reward_feedback_projector.gd")
const ModelScr = preload("res://ui/four_player_table/seat_caption_model.gd")

const CHARS := ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"]
const RULE := "trash_talk_rules_v1"
const NOW0 := 1_700_000_000_000


func test_fixture_catalog_stable() -> void:
	# all() 仅每局基线；STT 为显示子夹具不在 all()
	assert_eq(BalScr.all().size(), 5)
	assert_eq(BalScr.fixture_version(), "reward_feedback_balance_v6")
	assert_eq(BalScr.gold_digest(), "rfb_v6_real_loopback_ml_hand")
	for raw in BalScr.all():
		var g: Dictionary = raw
		assert_true(g.has("outcome") or g.has("inventory_total") or g.has("inventory_total_after_grants"),
			"每局基线须含 outcome/库存字段: %s" % str(g.get("fixture_id")))
	var stt: Dictionary = BalScr.gold_stt_silent_baseline()
	assert_eq(String(stt.get("kind", "")), "display_subfixture")


func test_full_grant_real_stream_bijection_and_schema() -> void:
	var g: Dictionary = BalScr.gold_full_grant_baseline()
	var pool: Array = g["prize_pool"]
	var asg: Dictionary = g["assignment"]
	assert_eq(pool.size(), 4)
	var seen: Dictionary = {}
	for s in range(4):
		var item := String(asg[str(s)])
		assert_true(pool.has(item), "assignment 必须来自同一 prize_pool: %s" % item)
		assert_false(seen.has(item), "一对一双射不得重复 item")
		seen[item] = true
	assert_eq(seen.size(), 4)
	# 与 PrizePool seed11 一致
	var live_pool: Array = RewardWindowPrizePool.select_four(
		int(g["seed"]), int(g["hand_seq"]), int(g["window_index"]), String(g["rule_version"])
	)
	assert_eq(JSON.stringify(live_pool), JSON.stringify(pool))
	# instance ids 与 ItemInstance 公式一致
	for seat in range(4):
		var item2 := String(asg[str(seat)])
		var expect_iid := String((g["instance_ids"] as Dictionary)[str(seat)])
		var live_iid := ItemInstance.make_instance_id(
			String(g["match_namespace"]), String(g["window_id"]), seat, item2
		)
		assert_eq(live_iid, expect_iid)

	var events: Array = BalScr.self_consistent_full_grant_events()
	assert_gt(events.size(), 10, "真实冻结 journal 必须存在")
	var grant_n := 0
	var dist: Dictionary = {}
	var pool_from_open: Array = []
	var asg_from_settle: Dictionary = {}
	for raw in events:
		var d: Dictionary = raw
		assert_not_null(NetworkedEvent.from_dict(d), "wire 必须 from_dict: %s" % str(d.get("kind")))
		var kind := String(d.get("kind", ""))
		if kind == "REWARD_WINDOW_OPENED" and pool_from_open.is_empty():
			pool_from_open = (d["payload"] as Dictionary).get("prize_pool", []) as Array
		elif kind == "REWARD_WINDOW_SETTLED" \
				and String((d["payload"] as Dictionary).get("outcome", "")) == "FULL_GRANT":
			asg_from_settle = (d["payload"] as Dictionary).get("assignment", {}) as Dictionary
			assert_eq(JSON.stringify((d["payload"] as Dictionary).get("prize_pool", [])),
				JSON.stringify(pool_from_open))
			assert_eq(int((d["payload"] as Dictionary).get("grant_count", -1)), 4)
		elif kind == "ITEM_GRANTED":
			grant_n += 1
			var p: Dictionary = d["payload"]
			var item3 := String(p.get("item_id", ""))
			dist[item3] = int(dist.get(item3, 0)) + 1
			var seat2 := str(int(p.get("seat", -1)))
			assert_eq(item3, String(asg_from_settle.get(seat2, "")),
				"ITEM_GRANTED 必须等于 assignment 双射")
	assert_eq(grant_n, 4)
	assert_eq(JSON.stringify(pool_from_open), JSON.stringify(g["prize_pool"]))
	assert_eq(JSON.stringify(asg_from_settle), JSON.stringify(g["assignment"]))
	assert_eq(JSON.stringify(dist), JSON.stringify(g["item_distribution"]))
	assert_eq(int(g["affinity_activation_numerator"]), 0)
	assert_eq(int(g["affinity_activation_denominator"]), 4)
	assert_eq(int(g["inventory_total_after_grants"]), 4)
	assert_eq(int(g["same_id_max_count"]), 1)


func test_display_only_via_begin_scoring_close_public_api() -> void:
	var expected: Dictionary = BalScr.gold_display_only_baseline()
	var rw := RewardWindowModule.new()
	var open_ok: Dictionary = rw.open({
		"seed": int(expected["seed"]), "hand_seq": 0, "window_index": 0,
		"rule_version": RULE, "room_id": "room_disp",
		"character_ids": CHARS, "language": "zh",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"public_initial": {"hand_seq": 0, "dealer_seat": 0, "scores": [25000, 25000, 25000, 25000]},
	})
	assert_true(bool(open_ok.get("ok", false)), str(open_ok))
	# 公开 API：终场评分关闭 → DISPLAY_ONLY（不得写 _pending_exit）
	var close_res: Dictionary = rw.begin_scoring_close({
		"result_server_seq": 100,
		"now_ms": NOW0,
		"is_match_end": true,
	})
	assert_true(bool(close_res.get("ok", false)), str(close_res))
	var settled: Dictionary = rw.try_settle({"now_ms": NOW0})
	assert_true(bool(settled.get("ok", false)), str(settled))
	var p: Dictionary = settled.get("payload", {})
	assert_eq(String(p.get("outcome", "")), "DISPLAY_ONLY")
	assert_eq(int(p.get("grant_count", -1)), int(expected["grant_count"]))
	assert_eq(int(expected["inventory_total"]), 0)
	assert_eq(int(expected["same_id_count"]), 0)
	assert_true(bool(p.has("assignment")))
	assert_true(bool(p.has("matrix_summary")))
	# 真实 settle payload 必须 schema-valid（不得手拼回退）
	var wire := {
		"protocol_version": 1, "server_seq": 101, "room_id": "room_disp",
		"kind": "REWARD_WINDOW_SETTLED", "payload": p,
		"view_hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
	}
	var ne: NetworkedEvent = NetworkedEvent.from_dict(wire)
	assert_not_null(ne, "DISPLAY_ONLY 真实 payload 必须 from_dict: %s" % str(p.keys()))
	var proj = ProjScr.new()
	var ok_p: Dictionary = proj.project(ne)
	assert_true(bool(ok_p.get("ok", false)), str(ok_p))
	assert_eq(String(ok_p.get("message", "")), String(expected["expected_message"]))
	assert_eq(proj.inventory_count_for_seat(0), 0)
	assert_eq(int(expected["affinity_activation_numerator"]), 0)
	assert_eq(int(expected["affinity_activation_denominator"]), 4)


func test_cancelled_via_real_cancel_by_win_no_fallback() -> void:
	var expected: Dictionary = BalScr.gold_cancelled_baseline()
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open({
		"seed": int(expected["seed"]), "hand_seq": 0, "window_index": 0,
		"rule_version": RULE, "room_id": "room_can",
		"character_ids": CHARS, "language": "zh",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"public_initial": {"hand_seq": 0, "dealer_seat": 0, "scores": [25000, 25000, 25000, 25000]},
	}).get("ok", false)))
	var can: Dictionary = rw.cancel_by_win({"now_ms": NOW0})
	assert_true(bool(can.get("ok", false)), str(can))
	assert_eq(String(rw.window_exit), "CANCELLED_BY_WIN")
	assert_false(bool(rw.scored))
	assert_eq(int(rw.grant_count), 0)
	var payload: Dictionary = can.get("payload", {}) as Dictionary
	assert_eq(String(payload.get("cancel_reason", "")), "CANCELLED_BY_WIN")
	assert_eq(int(payload.get("grant_count", -1)), 0)
	assert_eq(int(expected["inventory_total"]), 0)
	assert_eq(int(expected["same_id_count"]), 0)
	# 真实 cancel payload 直接 project；失败不得回退手拼另一份
	var wire := {
		"protocol_version": 1, "server_seq": 5, "room_id": "room_can",
		"kind": "REWARD_WINDOW_CANCELLED",
		"payload": payload,
		"view_hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
	}
	var ne: NetworkedEvent = NetworkedEvent.from_dict(wire)
	assert_not_null(ne, "cancel_by_win 真实 payload 必须 schema-valid: %s" % str(payload))
	var proj = ProjScr.new()
	var r: Dictionary = proj.project(ne)
	assert_true(bool(r.get("ok", false)), str(r))
	assert_eq(String(r.get("message", "")), String(expected["expected_message"]))
	assert_false(proj.has_assignment_display())
	assert_eq(int(expected["affinity_activation_numerator"]), 0)
	assert_eq(int(expected["affinity_activation_denominator"]), 4)


func test_multi_instance_real_grant_and_snapshot() -> void:
	var m: Dictionary = BalScr.gold_multi_instance_baseline()
	var inv := ItemInventoryModule.new()
	inv.set_match_namespace(String(m["match_namespace"]))
	var g0: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": String(m["item_id"]),
		"window_id": String(m["window_a"]), "hand_seq": 0, "score": 0,
		"affinity_match": false, "matched_rule_ids": [],
		"rule_version": RULE, "assignment_version": "assign_v1",
	})
	var g1: Dictionary = inv.grant_for_seat({
		"seat": 0, "item_id": String(m["item_id"]),
		"window_id": String(m["window_b"]), "hand_seq": 0, "score": 0,
		"affinity_match": false, "matched_rule_ids": [],
		"rule_version": RULE, "assignment_version": "assign_v1",
	})
	assert_true(bool(g0.get("ok", false)), str(g0))
	assert_true(bool(g1.get("ok", false)), str(g1))
	var id0 := String((g0["payload"] as Dictionary)["item_instance_id"])
	var id1 := String((g1["payload"] as Dictionary)["item_instance_id"])
	assert_eq(id0, String(m["expected_instance_ids"][0]))
	assert_eq(id1, String(m["expected_instance_ids"][1]))
	var dto: Dictionary = inv.to_seat_snapshot_dto(0)
	var inv2 := ItemInventoryModule.new()
	inv2.set_match_namespace(String(m["match_namespace"]))
	assert_true(inv2.restore_seat_snapshot_payload(dto["payload"], 0))
	assert_eq(inv2.instances_for_seat(0).size(), 2)
	assert_eq(int(m["same_id_count"]), 2)
	assert_eq(int(m["inventory_total"]), 2)


func test_multilingual_exact_matched_rules_and_affinity() -> void:
	var m: Dictionary = BalScr.gold_multilingual_inputs()
	var seats: Dictionary = m["seats"]
	for sk in ["0", "1", "2"]:
		var row: Dictionary = seats[sk]
		var acc: Dictionary = TextAnalyzer.accumulate_window({
			"rule_version": String(m["rule_version"]),
			"window_id": "bal_exact",
			"seat": int(sk),
			"character_id": String(row["character_id"]),
			"language": String(row["language"]),
			"utterances": [{
				"utterance_id": "u",
				"text": String(row["text"]),
				"language": String(row["language"]),
			}],
		})
		assert_false(acc.is_empty())
		var matched: Array = acc.get("matched_rule_ids", []) as Array
		var expect_ids: Array = row["matched_rule_ids"] as Array
		assert_eq(JSON.stringify(matched), JSON.stringify(expect_ids),
			"seat %s matched_rule_ids 必须字节级一致" % sk)
		var aff: Dictionary = acc.get("affinity", {}) as Dictionary
		var exp_aff: Dictionary = row["affinity"] as Dictionary
		for k in exp_aff.keys():
			assert_eq(int(aff.get(String(k), -1)), int(exp_aff[k]),
				"seat %s affinity %s" % [sk, k])
	assert_eq((seats["3"]["matched_rule_ids"] as Array).size(), 0)


func test_multilingual_inputs_drive_real_scorer_matrix() -> void:
	# 真实 scorer 输出必须逐项对照硬编码 expected（不得只断言 size/存在）
	var m: Dictionary = BalScr.gold_multilingual_inputs()
	var seats: Dictionary = m["seats"]
	var rw := RewardWindowModule.new()
	assert_true(bool(rw.open({
		"seed": int(m["seed"]), "hand_seq": int(m["hand_seq"]), "window_index": int(m["window_index"]),
		"rule_version": RULE, "room_id": String(m["room_id"]),
		"character_ids": (m["character_ids"] as Array).duplicate(),
		"language": "zh",
		"participants": (m["participants"] as Array).duplicate(),
		"public_initial": {"hand_seq": 0, "dealer_seat": 0, "scores": [25000, 25000, 25000, 25000]},
	}).get("ok", false)))
	for sk in ["0", "1", "2"]:
		var row: Dictionary = seats[sk]
		var text := String(row["text"])
		if text.is_empty():
			continue
		var ing: Dictionary = rw.ingest_utterance({
			"seat": int(sk),
			"utterance_id": "ml_%s" % sk,
			"text": text,
			"language": String(row["language"]),
			"ptt_end_server_seq": 10 + int(sk),
			"terminal": true,
		})
		assert_true(bool(ing.get("accepted", false)), "seat %s utterance: %s" % [sk, str(ing)])
	assert_true(bool(rw.begin_scoring_close({
		"result_server_seq": 50, "now_ms": NOW0, "is_match_end": true,
	}).get("ok", false)))
	var settled: Dictionary = rw.try_settle({"now_ms": NOW0})
	assert_true(bool(settled.get("ok", false)), str(settled))
	var p: Dictionary = settled.get("payload", {})
	assert_eq(String(p.get("outcome", "")), String(m["outcome"]))
	assert_eq(int(p.get("grant_count", -1)), int(m["grant_count"]))
	assert_eq(int(m["inventory_total"]), 0, "DISPLAY_ONLY 库存基线须为 0")
	assert_eq(int(m["same_id_count"]), 0)
	assert_eq(JSON.stringify(m["item_distribution"]), JSON.stringify({}))
	assert_eq(int(m["affinity_activation_numerator"]), 3)
	assert_eq(int(m["affinity_activation_denominator"]), 4)
	assert_eq(JSON.stringify(p.get("prize_pool", [])), JSON.stringify(m["prize_pool"]))
	assert_eq(JSON.stringify(p.get("assignment", {})), JSON.stringify(m["assignment"]))
	assert_eq(JSON.stringify((p.get("matrix_summary", {}) as Dictionary).get("scores", [])),
		JSON.stringify((m["matrix_summary"] as Dictionary).get("scores", [])))
	# 投影文案
	var wire := {
		"protocol_version": 1, "server_seq": 101, "room_id": String(m["room_id"]),
		"kind": "REWARD_WINDOW_SETTLED", "payload": p,
		"view_hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
	}
	var ne: NetworkedEvent = NetworkedEvent.from_dict(wire)
	assert_not_null(ne)
	var proj = ProjScr.new()
	var ok_p: Dictionary = proj.project(ne)
	assert_true(bool(ok_p.get("ok", false)), str(ok_p))
	assert_eq(String(ok_p.get("message", "")), String(m["expected_message"]))
	assert_eq(proj.inventory_count_for_seat(0), 0)


func test_stt_failed_text() -> void:
	var gold: Dictionary = BalScr.gold_stt_silent_baseline()
	var model = ModelScr.new()
	assert_true(bool(model.ingest({
		"seat": 0, "utterance_id": "stt", "text": "",
		"kind": "final", "source": "server_stt", "lang": "zh",
		"now_ms": 1, "stt_failed": true,
	}).get("ok", false)))
	assert_eq(String(model.display_for_seat(0).get("text", "")),
		String(gold["stt_failed_text"]))
