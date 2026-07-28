extends GutTest

# #375：统一单局结算结果与权威点数账本（Red → Green）
# 证明 GameDriver 与 LocalLoopbackServer 分叉，并验收共享 HandSettlement 入口。

const START := 25000


func _ron_events(winner: int, loser: int, payout: Dictionary, winner_total: int) -> Array:
	return [
		BattleEvent.make(&"RON_DECLARED", winner, null, {"discarder_seat": loser}),
		BattleEvent.make(&"WIN_DECLARED", winner, null, {
			"payout": payout,
			"winner_total": winner_total,
			"han": 1,
			"fu": 30,
			"is_tsumo": false,
			"discarder_seat": loser,
		}),
	]


func _tsumo_events(winner: int, payout: Dictionary, winner_total: int) -> Array:
	return [
		BattleEvent.make(&"TSUMO_DECLARED", winner),
		BattleEvent.make(&"WIN_DECLARED", winner, null, {
			"payout": payout,
			"winner_total": winner_total,
			"han": 1,
			"fu": 30,
			"is_tsumo": true,
		}),
	]


func _exhaustive_events() -> Array:
	return [BattleEvent.make(&"EXHAUSTIVE_DRAW", -1)]


func _abortive_events() -> Array:
	return [BattleEvent.make(&"ABORTIVE_DRAW", -1, null, {"reason": "kyuusyu_kyuuhai"})]


func _nagashi_events(winner: int) -> Array:
	return [
		BattleEvent.make(&"EXHAUSTIVE_DRAW", -1),
		BattleEvent.make(&"NAGASHI_MANGAN", winner, null, {"winner_seat": winner}),
	]


func _fake_state(
	scores: Array = [START, START, START, START],
	dealer: int = 0,
	honba: int = 0,
	riichi_sticks: int = 0,
	hand_seq: int = 0
) -> BattleState:
	var st := BattleState.new()
	st.scores = [int(scores[0]), int(scores[1]), int(scores[2]), int(scores[3])]
	st.dealer_seat = dealer
	st.honba = honba
	st.riichi_sticks = riichi_sticks
	st.hand_seq = hand_seq
	for i in range(4):
		st.seats.append(Seat.new(i, TileId.E if i == 0 else TileId.S_WIND, int(scores[i])))
	return st


# ---- Red: 证明分叉存在的契约（实现后 LocalLoopback 与 GameDriver 一致）----

func test_shared_entry_ron_matches_driver_and_payload_shape() -> void:
	# 守恒：起分 4×25000 棒 0；局内 seat0 立直扣 1000 + skill 转 seat2 500
	var start := [START, START, START, START]
	var st := _fake_state(
		[START - 1000 - 500, START, START + 500, START], 0, 2, 1, 3
	)
	st.riichi_sticks = 1
	var events := _ron_events(2, 1, {1: 2000}, 3000)  # 2000 铳 + 1000 棒
	var built: Dictionary = HandSettlement.build(events, start, st, [], 2, 0)
	assert_false(built.is_empty(), "HandSettlement.build 须返回完整结果")
	assert_eq(str(built.get("outcome", "")), "RON")
	assert_eq(built.get("winner_seats"), [2])
	assert_eq(int(built.get("loser_seat", -2)), 1)
	assert_eq(int(built.get("hand_seq", -1)), 3)
	assert_eq(int(built.get("dealer_seat", -1)), 0)
	assert_false(bool(built.get("renchan", true)), "闲家荣和 → 不连庄")
	assert_eq(int(built.get("honba", -1)), 0, "不连庄 honba 归零")
	assert_eq(int(built.get("riichi_sticks", -1)), 0, "胡牌收走立直棒")
	var expect := [
		START - 1000 - 500, START - 2000, START + 500 + 3000, START,
	]
	assert_eq(built.get("scores"), expect)
	assert_true(HandSettlement.is_conserved(built.get("scores"), 0))
	assert_true(built.has("adjustments"), "须有 adjustments")
	assert_true(built.has("score_deltas"))
	var d := GameDriver.new(1)
	for i in range(4):
		d.cumulative_scores[i] = int(start[i])
	d.honba = 2
	d.riichi_sticks = 0
	d.dealer_seat = 0
	d.battle = BattleController.new(1, 0)
	for i2 in range(4):
		d.battle.state.scores[i2] = int(st.scores[i2])
	d.battle.state.riichi_sticks = 1
	d.battle.state.dealer_seat = 0
	d.battle.state.hand_seq = 3
	for i3 in range(4):
		d._pre_hand_state_scores[i3] = START
	d._pre_hand_honba = 2
	d._pre_hand_riichi_sticks = 0
	d._pre_hand_frozen = true
	var applied: Dictionary = d.apply_result(events)
	assert_eq(str(applied.get("kind", "")), "ron")
	var expected_scores: Array = built.get("scores")
	for i4 in range(4):
		assert_eq(int(d.cumulative_scores[i4]), int(expected_scores[i4]),
			"GameDriver 与 HandSettlement 终分 seat%d" % i4)
	assert_eq(d.riichi_sticks, 0)


func test_shared_entry_tsumo_with_honba_renchan() -> void:
	var start := [START, START, START, START]
	var st := _fake_state(start, 0, 1, 0, 0)
	var events := _tsumo_events(0, {1: 2000, 2: 2000, 3: 2000}, 6000)
	var built: Dictionary = HandSettlement.build(events, start, st, [], 1, 0)
	assert_eq(str(built.get("outcome", "")), "TSUMO")
	assert_true(bool(built.get("renchan", false)), "庄家自摸连庄")
	assert_eq(int(built.get("honba", -1)), 2, "连庄 honba+1")
	assert_eq(built.get("scores"), [START + 6000, START - 2000, START - 2000, START - 2000])
	assert_true(HandSettlement.is_conserved(built.get("scores"), int(built.get("riichi_sticks", 0))))


func test_exhaustive_draw_applies_noten_not_zero() -> void:
	var start := [START, START, START, START]
	var st := _fake_state(start, 0, 0, 0, 1)
	var events := _exhaustive_events()
	var tenpai := [true, false, false, false]
	var built: Dictionary = HandSettlement.build(events, start, st, tenpai, 0, 0)
	assert_eq(str(built.get("outcome", "")), "EXHAUSTIVE_DRAW")
	assert_eq(built.get("scores"), [START + 3000, START - 1000, START - 1000, START - 1000],
		"普通流局须应用 3000 不听罚符")
	assert_true(bool(built.get("renchan", false)), "庄家听 → 连庄")
	assert_eq(int(built.get("riichi_sticks", -1)), 0)
	# LocalLoopback 旧路径（零罚符）须被统一纠正：不得等于 state.scores
	assert_ne(JSON.stringify(built.get("scores")), JSON.stringify(start),
		"不得伪装为零罚符普通流局")


func test_abortive_draw_zero_noten_renchan() -> void:
	var start := [START, START, START, START]
	var st := _fake_state(start, 1, 0, 2, 0)
	var events := _abortive_events()
	var built: Dictionary = HandSettlement.build(events, start, st, [false, false, false, false], 0, 2)
	assert_eq(str(built.get("outcome", "")), "ABORTIVE_DRAW")
	assert_eq(built.get("scores"), start, "途中流局零罚符")
	assert_true(bool(built.get("renchan", false)))
	assert_eq(int(built.get("riichi_sticks", -1)), 2, "途中流局保留立直棒")


func test_nagashi_mangan_distinct_outcome_and_payout() -> void:
	var start := [START, START, START, START]
	var st := _fake_state(start, 0, 0, 0, 0)
	var events := _nagashi_events(1)
	var built: Dictionary = HandSettlement.build(events, start, st, [], 0, 0)
	assert_eq(str(built.get("outcome", "")), "NAGASHI_MANGAN",
		"流し满贯须独立 outcome，不得伪装 EXHAUSTIVE_DRAW")
	assert_eq(built.get("winner_seats"), [1])
	assert_eq(int(built.get("loser_seat", 0)), -1)
	var expected_payout: Dictionary = NagashiMangan.payout(1, 0)
	var expected_scores: Array = []
	for i in range(4):
		expected_scores.append(START + int(expected_payout[i]))
	assert_eq(built.get("scores"), expected_scores)
	assert_false(bool(built.get("renchan", true)), "闲家流し → 不连庄")


func test_external_mint_patience_stone_recorded_not_forced_conserved() -> void:
	# 忍石：state.scores[owner]+=2000，STANDARD 守恒被破；须 EXTERNAL adjustment
	var start := [START, START, START, START]
	var st := _fake_state([START + 2000, START, START, START], 0, 0, 0, 0)
	var events := _exhaustive_events()
	var tenpai := [true, true, true, true]  # 全听 0 罚符，暴露 mint
	var built: Dictionary = HandSettlement.build(events, start, st, tenpai, 0, 0)
	assert_false(built.is_empty())
	assert_eq(built.get("scores"), [START + 2000, START, START, START])
	var adjs: Array = built.get("adjustments", [])
	var seat_sum := [0, 0, 0, 0]
	var has_external := false
	for a in adjs:
		var seat: int = int(a.get("seat", -1))
		if seat >= 0 and seat < 4:
			seat_sum[seat] += int(a.get("delta", 0))
		if str(a.get("kind", "")) == "EXTERNAL" and int(a.get("delta", 0)) != 0:
			has_external = true
	assert_true(has_external, "忍石 mint 须记录 EXTERNAL adjustment")
	assert_eq(seat_sum[0], 2000, "每席 adjustments 合计须 = state-start，不得 IN_HAND+EXTERNAL 双计")
	assert_eq(seat_sum[1], 0)
	assert_false(
		HandSettlement.is_conserved(built.get("scores"), int(built.get("riichi_sticks", 0))),
		"TRASH_TALK mint 不强行伪装守恒"
	)


func test_commit_is_atomic_and_idempotent_per_hand_seq() -> void:
	var start := [START, START, START, START]
	var st := _fake_state(start, 0, 0, 0, 5)
	var events := _tsumo_events(0, {1: 1000, 2: 1000, 3: 1000}, 3000)
	var built: Dictionary = HandSettlement.build(events, start, st, [], 0, 0)
	assert_false(built.is_empty())
	var ledger: Array = start.duplicate()
	var tracker := HandSettlement.empty_tracker()
	assert_true(HandSettlement.commit(built, ledger, tracker, null, start, true), "首次提交成功")
	assert_eq(ledger, built.get("scores"))
	assert_eq(int(tracker["committed_hand_seq"]), 5)
	var ledger_snapshot: Array = ledger.duplicate()
	assert_true(HandSettlement.commit(built, ledger, tracker, null, start, true), "同 hand 重复提交幂等成功")
	assert_eq(ledger, ledger_snapshot, "重复提交不得二次落账")
	# 非法结果：零 mutation
	var bad := built.duplicate(true)
	bad.erase("scores")
	var before: Array = ledger.duplicate()
	assert_false(HandSettlement.commit(bad, ledger, tracker, null, start, true), "非法结果原子失败")
	assert_eq(ledger, before)


func test_commit_writes_battle_state_scores_for_next_hand_source() -> void:
	var start := [START, START, START, START]
	var st := _fake_state(start, 0, 0, 0, 0)
	var events := _ron_events(0, 1, {1: 1000}, 1000)
	var built: Dictionary = HandSettlement.build(events, start, st, [], 0, 0)
	var ledger: Array = start.duplicate()
	var tracker := HandSettlement.empty_tracker()
	assert_true(HandSettlement.commit(built, ledger, tracker, st, start, true))
	assert_eq(st.scores, built.get("scores"), "提交后 BattleState.scores == HAND_SETTLED.scores")
	# 下一局起分唯一来源
	var next_start: Array = []
	for s in st.scores:
		next_start.append(int(s))
	assert_eq(next_start, built.get("scores"))
	assert_eq(int(st.riichi_sticks), int(built.get("riichi_sticks", -1)))


func test_protocol_hand_settled_accepts_nagashi_and_expanded_keys() -> void:
	var payload: Dictionary = {
		"hand_seq": 0,
		"outcome": "NAGASHI_MANGAN",
		"winner_seats": [1],
		"loser_seat": -1,
		"score_deltas": [-4000, 8000, -2000, -2000],
		"scores": [21000, 33000, 23000, 23000],
		"dealer_seat": 0,
		"renchan": false,
		"honba": 0,
		"riichi_sticks": 0,
		"adjustments": [],
	}
	var ne: NetworkedEvent = NetworkedEvent.make(
		"HAND_SETTLED", 1, "room-x", payload,
		"a".repeat(64)
	)
	assert_not_null(ne, "NAGASHI_MANGAN + 扩展键须通过 strict validator")
	if ne != null:
		var rt: NetworkedEvent = NetworkedEvent.from_dict(ne.to_dict())
		assert_not_null(rt, "roundtrip 须成功")
		assert_eq(str(rt.payload.get("outcome", "")), "NAGASHI_MANGAN")


func test_driver_and_settlement_share_exhaustive_noten() -> void:
	var d := GameDriver.new(7)
	var events := _exhaustive_events()
	var result: Dictionary = d.apply_result(events)
	assert_eq(str(result.get("kind", "")), "exhaustive_draw")
	result["tenpai_array"] = [false, true, true, false]
	d.advance_or_finish(result)
	assert_eq(d.cumulative_scores[0], START - 1500)
	assert_eq(d.cumulative_scores[1], START + 1500)
	assert_eq(d.cumulative_scores[2], START + 1500)
	assert_eq(d.cumulative_scores[3], START - 1500)
	assert_true(d.is_score_conserved())


# ---- Round 2：幂等 / 冲突 / 严格类型 / 流局 fail-closed ----

func test_commit_same_result_idempotent_restores_canonical() -> void:
	var start := [START, START, START, START]
	var st := _fake_state(start, 0, 0, 0, 7)
	var events := _tsumo_events(0, {1: 1000, 2: 1000, 3: 1000}, 3000)
	var built: Dictionary = HandSettlement.build(events, start, st, [], 0, 0)
	var ledger: Array = start.duplicate()
	var tracker := HandSettlement.empty_tracker()
	assert_true(HandSettlement.commit(built, ledger, tracker, st, start, true))
	var canon_scores: Array = built.get("scores")
	# 污染 ledger 后同结果再 commit：须恢复 canonical，不得失败
	ledger[0] = 1
	assert_true(HandSettlement.commit(built, ledger, tracker, st, start, true), "相同结果幂等成功")
	for i in range(4):
		assert_eq(int(ledger[i]), int(canon_scores[i]))
	assert_eq(int(st.scores[0]), int(canon_scores[0]))


func test_commit_same_hand_seq_conflict_fails_zero_mutation() -> void:
	var start := [START, START, START, START]
	var st := _fake_state(start, 0, 0, 0, 8)
	var events := _tsumo_events(0, {1: 1000, 2: 1000, 3: 1000}, 3000)
	var built: Dictionary = HandSettlement.build(events, start, st, [], 0, 0)
	var ledger: Array = start.duplicate()
	var tracker := HandSettlement.empty_tracker()
	assert_true(HandSettlement.commit(built, ledger, tracker, st, start, true))
	var before: Array = ledger.duplicate()
	var conflict: Dictionary = built.duplicate(true)
	conflict["scores"] = [99999, 1, 1, 1]
	conflict["score_deltas"] = [74999, -24999, -24999, -24999]
	assert_false(HandSettlement.commit(conflict, ledger, tracker, st, start, true), "同 seq 不同 scores 须失败")
	assert_eq(JSON.stringify(ledger), JSON.stringify(before), "冲突零 mutation ledger")
	assert_eq(int(st.scores[0]), int(before[0]), "冲突零 mutation state")


func test_is_valid_result_rejects_float_scores_and_bad_outcome() -> void:
	var start := [START, START, START, START]
	var st := _fake_state(start, 0, 0, 0, 0)
	var built: Dictionary = HandSettlement.build(
		_tsumo_events(0, {1: 1000, 2: 1000, 3: 1000}, 3000), start, st, [], 0, 0
	)
	assert_true(HandSettlement.is_valid_result(built))
	var bad := built.duplicate(true)
	bad["scores"] = [28000.0, 24000, 24000, 24000]
	assert_false(HandSettlement.is_valid_result(bad), "float score 须拒绝")
	bad = built.duplicate(true)
	bad["outcome"] = "WIN"
	assert_false(HandSettlement.is_valid_result(bad), "非法 outcome 须拒绝")
	bad = built.duplicate(true)
	bad["winner_seats"] = ["0"]
	assert_false(HandSettlement.is_valid_result(bad), "string winner 须拒绝")


func test_driver_repeat_apply_returns_canonical_not_double_payout() -> void:
	var d := GameDriver.new(3)
	var events := _ron_events(2, 0, {0: 2000}, 2000)
	var first: Dictionary = d.apply_result(events)
	assert_eq(str(first.get("kind", "")), "ron")
	var scores_after: Array = []
	for s in d.cumulative_scores:
		scores_after.append(int(s))
	var second: Dictionary = d.apply_result(events)
	assert_eq(str(second.get("kind", "")), "ron", "重复 apply 幂等返回")
	assert_false(second.is_empty())
	for i in range(4):
		assert_eq(int(d.cumulative_scores[i]), int(scores_after[i]), "重复 apply 不得改 ledger")
	var settle: Dictionary = second.get("settlement", {})
	assert_eq(JSON.stringify(settle.get("scores", [])), JSON.stringify(scores_after),
		"返回 settlement 须为 canonical 终分，不得二次 payout")


func test_driver_exhaustive_commit_fail_does_not_advance() -> void:
	var d := GameDriver.new(9)
	d.hand_index = 0
	d.dealer_seat = 0
	d.honba = 0
	# 先进入 pending draw
	var r: Dictionary = d.apply_result(_exhaustive_events())
	assert_eq(str(r.get("kind", "")), "exhaustive_draw")
	# 污染 pending hand_seq 为非法并清空 events 使 build 仍可成功；改用 tracker 冲突模拟
	# 先提交一个 hand_seq=0 结果，再让 exhaustive 也用 hand_seq=0 但不同 scores
	var st := _fake_state([START, START, START, START], 0, 0, 0, 0)
	var win_built: Dictionary = HandSettlement.build(
		_tsumo_events(0, {1: 1000, 2: 1000, 3: 1000}, 3000),
		[START, START, START, START], st, [], 0, 0
	)
	assert_true(HandSettlement.commit(
		win_built, d.cumulative_scores, d._settlement_tracker, null,
		[START, START, START, START], true
	))
	# pending 仍指向 hand_seq 0 exhaustive → commit 冲突失败
	d._pending_draw_kind = "exhaustive_draw"
	d._pending_draw_events = _exhaustive_events()
	d._pending_draw_state_scores = [START, START, START, START]
	d._pending_draw_state_sticks = 0
	d._pending_draw_hand_seq = 0
	d._pre_hand_frozen = true
	for i in range(4):
		d._pre_hand_state_scores[i] = START
	var before_hi: int = d.hand_index
	var before_dealer: int = d.dealer_seat
	var adv: Dictionary = d.advance_or_finish({
		"kind": "exhaustive_draw",
		"tenpai_array": [false, true, false, false],
	})
	assert_eq(str(adv.get("error", "")), "SETTLEMENT_COMMIT_FAILED")
	assert_eq(d.hand_index, before_hi, "commit 失败不得推进 hand_index")
	assert_eq(d.dealer_seat, before_dealer, "commit 失败不得转庄")


func test_adjustments_transfer_only_in_hand_no_external() -> void:
	var start := [START, START, START, START]
	var st := _fake_state([START + 1000, START - 1000, START, START], 0, 0, 0, 0)
	var built: Dictionary = HandSettlement.build(
		_exhaustive_events(), start, st, [true, true, true, true], 0, 0
	)
	var adjs: Array = built.get("adjustments", [])
	var seat_sum := [0, 0, 0, 0]
	for a in adjs:
		assert_eq(str(a.get("kind", "")), "IN_HAND", "守恒转分不得标 EXTERNAL")
		seat_sum[int(a.get("seat", 0))] += int(a.get("delta", 0))
	assert_eq(seat_sum, [1000, -1000, 0, 0])


# ---- Round 3：STANDARD 守恒门禁 + score_deltas 交叉校验（生产消费者）----

func _standard_driver(seed: int = 11) -> GameDriver:
	var d := GameDriver.new(seed)
	d.mode_modules = null
	return d


func _trash_talk_driver(seed: int = 12) -> GameDriver:
	var d := GameDriver.new(seed)
	var cfg := GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PRACTICE, GameSessionConfig.ROUND_EAST,
		GameSessionConfig.MODE_TRASH_TALK,
		[&"HUMAN", &"AI", &"AI", &"AI"],
		[&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"],
		seed, "sess-tt-375", "rv-375"
	)
	assert_not_null(cfg, "TRASH_TALK config 须合法")
	if cfg == null:
		return d
	d.mode_modules = ModeModuleBundle.from_config(cfg)
	assert_not_null(d.mode_modules)
	assert_true(d.mode_modules.is_trash_talk())
	return d


func test_driver_standard_rejects_non_conserved_mint_zero_mutation() -> void:
	var d := _standard_driver(21)
	var bc := d.start_hand()
	assert_not_null(bc)
	bc.state.scores[0] = int(bc.state.scores[0]) + 2000
	var res: Dictionary = d.apply_result(_exhaustive_events())
	assert_eq(str(res.get("kind", "")), "exhaustive_draw")
	res["tenpai_array"] = [true, true, true, true]
	var before: Array = []
	for s in d.cumulative_scores:
		before.append(int(s))
	var before_hi: int = d.hand_index
	var adv: Dictionary = d.advance_or_finish(res)
	assert_eq(str(adv.get("error", "")), "SETTLEMENT_COMMIT_FAILED",
		"STANDARD mint 须 SETTLEMENT_COMMIT_FAILED，实际=%s" % str(adv.get("error", "")))
	for i in range(4):
		assert_eq(int(d.cumulative_scores[i]), int(before[i]), "STANDARD 拒绝后 ledger 零 mutation")
	assert_eq(d.hand_index, before_hi, "STANDARD 拒绝后不得推进 hand_index")
	assert_eq(int(d._settlement_tracker.get("committed_hand_seq", -1)), -1)


func test_driver_trash_talk_accepts_mint_with_external_adjustment() -> void:
	var d := _trash_talk_driver(22)
	var bc := d.start_hand()
	assert_not_null(bc)
	bc.state.scores[0] = int(bc.state.scores[0]) + 2000
	var res: Dictionary = d.apply_result(_exhaustive_events())
	res["tenpai_array"] = [true, true, true, true]
	var adv: Dictionary = d.advance_or_finish(res)
	assert_eq(str(adv.get("error", "")), "",
		"TRASH_TALK 允许 mint，不得 SETTLEMENT_COMMIT_FAILED error=%s" % str(adv.get("error", "")))
	assert_eq(int(d.cumulative_scores[0]), START + 2000, "TRASH_TALK mint 须落账")
	var settle: Dictionary = {}
	if typeof(res.get("settlement", {})) == TYPE_DICTIONARY:
		settle = res.get("settlement", {})
	# advance_or_finish 把 settlement 写回 result 参数
	if settle.is_empty() and typeof(adv.get("settlement", null)) == TYPE_DICTIONARY:
		settle = adv.get("settlement", {})
	# 从 res 取：GameDriver 在 advance 内 result["settlement"]=...
	# GDScript 字典按引用，res 应已有 settlement
	if res.has("settlement") and typeof(res["settlement"]) == TYPE_DICTIONARY:
		settle = res["settlement"]
	assert_false(settle.is_empty(), "须暴露 settlement 供 EXTERNAL 断言")
	if settle.is_empty():
		return
	var has_ext := false
	for a in settle.get("adjustments", []):
		if str(a.get("kind", "")) == "EXTERNAL" and int(a.get("delta", 0)) == 2000:
			has_ext = true
	assert_true(has_ext, "TRASH_TALK mint 须 EXTERNAL +2000")
	assert_false(HandSettlement.is_conserved(
		settle.get("scores"), int(settle.get("riichi_sticks", 0))
	), "不得伪装守恒")


func test_commit_rejects_score_delta_mismatch_zero_mutation() -> void:
	var start := [START, START, START, START]
	var st := _fake_state(start, 0, 0, 0, 3)
	var built: Dictionary = HandSettlement.build(
		_tsumo_events(0, {1: 1000, 2: 1000, 3: 1000}, 3000), start, st, [], 0, 0
	)
	assert_true(HandSettlement.is_valid_result(built))
	var bad: Dictionary = built.duplicate(true)
	bad["score_deltas"] = [0, 0, 0, 0]  # 与 scores 矛盾
	var ledger: Array = start.duplicate()
	var tracker := HandSettlement.empty_tracker()
	# 提交边界须携带起分并拒绝矛盾 deltas（Green 后生效；Red 期望 false）
	assert_false(
		HandSettlement.commit(bad, ledger, tracker, st, start, true),
		"矛盾 score_deltas 须原子失败（需 start_scores + 交叉校验）"
	)
	for i in range(4):
		assert_eq(int(ledger[i]), START)
		assert_eq(int(st.scores[i]), START)
	assert_eq(int(tracker.get("committed_hand_seq", -1)), -1)
