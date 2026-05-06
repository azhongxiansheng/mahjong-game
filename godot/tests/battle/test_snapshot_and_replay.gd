extends GutTest

# 麻将王 — M11 net foundation: snapshot_hash + PLAYER_ACTION + Replay
# 接同事 PR #124 (IBattleController) + #127 (Action/NetworkedEvent 协议)
# 后续工作。本测试锁住三层硬证：
# 1. BattleState.snapshot_hash 在 desync detect 中可用
# 2. PLAYER_ACTION event 让事件日志自包含决策
# 3. set_replay_decisions(extract_player_actions(...)) 端到端收敛

# ---- snapshot_hash ----

func test_snapshot_hash_deterministic_for_same_seed():
	var bc1 := BattleController.new(42, 0, true)
	bc1.run_to_end()
	var bc2 := BattleController.new(42, 0, true)
	bc2.run_to_end()
	assert_eq(bc1.state.snapshot_hash(), bc2.state.snapshot_hash(),
		"同 seed 终态 hash byte-identical（Phase 2 desync detect 硬前提）")
	assert_eq(JSON.stringify(bc1.state.snapshot_dict()),
		JSON.stringify(bc2.state.snapshot_dict()),
		"snapshot_dict 也必须 byte-identical")

func test_snapshot_hash_changes_with_seed():
	var bc1 := BattleController.new(42, 0, true)
	bc1.run_to_end()
	var bc2 := BattleController.new(43, 0, true)
	bc2.run_to_end()
	assert_ne(bc1.state.snapshot_hash(), bc2.state.snapshot_hash(),
		"不同 seed 终态 hash 应不同（防 hash 退化为常量）")

func test_snapshot_dict_covers_key_fields():
	var bc := BattleController.new(42, 0, true)
	bc.run_to_end()
	var d: Dictionary = bc.state.snapshot_dict()
	for key in ["scores", "furiten_flags", "dealer_seat", "current_seat",
		"round_wind", "hand_number", "honba", "riichi_sticks", "phase",
		"turn_count", "seats", "discards", "extra_dora_count"]:
		assert_true(d.has(key), "snapshot_dict 缺关键字段: %s" % key)

func test_snapshot_dict_seats_contain_hand_and_melds():
	var bc := BattleController.new(42, 0, true)
	bc.run_to_end()
	var d: Dictionary = bc.state.snapshot_dict()
	assert_eq(d.seats.size(), 4)
	for seat_data in d.seats:
		assert_true(seat_data.has("hand_ids"))
		assert_true(seat_data.has("melds"))
		assert_true(seat_data.has("riichi_declared"))
		assert_true(seat_data.has("furiten_perm"))
		assert_true(seat_data.has("points"))

# ---- PLAYER_ACTION event ----

func test_player_action_emitted_for_each_discard():
	var bc := BattleController.new(42, 0, true)
	bc.run_to_end()
	for i in range(bc.events.size()):
		var ev: BattleEvent = bc.events[i]
		if ev.type != &"TILE_DISCARDED":
			continue
		var found := false
		for j in range(i - 1, -1, -1):
			var prev: BattleEvent = bc.events[j]
			if prev.type == &"PLAYER_ACTION":
				assert_eq(String(prev.extra.kind), "discard")
				assert_eq(int(prev.extra.tile_id), ev.tile_instance.tile.id)
				assert_eq(prev.actor_seat, ev.actor_seat)
				found = true
				break
		assert_true(found, "每个 TILE_DISCARDED 必须有前置 PLAYER_ACTION(discard)")

func test_player_action_emitted_for_riichi():
	var bc := BattleController.new(42, 0, true)
	bc.run_to_end()
	for i in range(bc.events.size()):
		var ev: BattleEvent = bc.events[i]
		if ev.type != &"RIICHI_DECLARED":
			continue
		var found := false
		for j in range(i - 1, -1, -1):
			var prev: BattleEvent = bc.events[j]
			if prev.type == &"PLAYER_ACTION" and String(prev.extra.get("kind", "")) == "riichi":
				assert_eq(prev.actor_seat, ev.actor_seat)
				found = true
				break
			if prev.type == &"TILE_DISCARDED":
				break
		assert_true(found, "每个 RIICHI_DECLARED 必须有前置 PLAYER_ACTION(riichi)")

func test_player_action_includes_tsumo_and_ron_kinds():
	var saw_tsumo: bool = false
	var saw_ron: bool = false
	for s in [42, 100, 200, 1234, 7]:
		var bc := BattleController.new(s, 0, true)
		bc.run_to_end()
		for ev in bc.events:
			if ev.type != &"PLAYER_ACTION":
				continue
			var k: String = String(ev.extra.get("kind", ""))
			if k == "tsumo_accept": saw_tsumo = true
			elif k == "ron_accept": saw_ron = true
		if saw_tsumo and saw_ron:
			break
	assert_true(saw_tsumo or saw_ron,
		"5 个 seed 内至少应有一次 tsumo_accept 或 ron_accept PLAYER_ACTION")

func test_extract_player_actions_returns_decision_log():
	var bc := BattleController.new(42, 0, true)
	bc.run_to_end()
	var actions: Array = BattleController.extract_player_actions(bc.events)
	var discards: int = 0
	for a in actions:
		if a.kind == "discard":
			discards += 1
			assert_true(int(a.tile_id) >= 0 and int(a.tile_id) <= 33)
		assert_true(int(a.seat) >= 0 and int(a.seat) <= 3)
	assert_gt(discards, 0)

func test_player_action_does_not_break_determinism():
	var bc1 := BattleController.new(42, 0, true)
	bc1.run_to_end()
	var bc2 := BattleController.new(42, 0, true)
	bc2.run_to_end()
	for i in range(mini(bc1.events.size(), bc2.events.size())):
		assert_eq(JSON.stringify(bc1.events[i].to_dict()),
			JSON.stringify(bc2.events[i].to_dict()),
			"event %d 仍 byte-identical（含 PLAYER_ACTION）" % i)

# ---- end-to-end Replay smoke ----

func test_replay_with_recorded_decisions_reproduces_state():
	# 录一局 → 抽决策 → 重放 → 终态 hash byte-identical 于原录制
	var bc1 := BattleController.new(42, 0, true)
	bc1.run_to_end()
	var actions: Array = BattleController.extract_player_actions(bc1.events)
	var hash1: int = bc1.state.snapshot_hash()
	var bc2 := BattleController.new(42, 0, true)
	bc2.set_replay_decisions(actions)
	bc2.run_to_end()
	assert_eq(bc2.state.snapshot_hash(), hash1,
		"重放终态 hash 必须等于原录制（联机收敛硬证）")
	assert_eq(JSON.stringify(bc1.state.snapshot_dict()),
		JSON.stringify(bc2.state.snapshot_dict()),
		"snapshot_dict 也 byte-identical")

func test_replay_event_stream_matches_original():
	var bc1 := BattleController.new(123, 0, true)
	bc1.run_to_end()
	var actions: Array = BattleController.extract_player_actions(bc1.events)
	var bc2 := BattleController.new(123, 0, true)
	bc2.set_replay_decisions(actions)
	bc2.run_to_end()
	assert_eq(bc1.events.size(), bc2.events.size())
	for i in range(mini(bc1.events.size(), bc2.events.size())):
		assert_eq(JSON.stringify(bc1.events[i].to_dict()),
			JSON.stringify(bc2.events[i].to_dict()))

func test_replay_with_empty_decisions_falls_back_to_ai():
	# 空决策队列 = v1 行为不变（向后兼容）
	var bc1 := BattleController.new(42, 0, true)
	bc1.run_to_end()
	var bc2 := BattleController.new(42, 0, true)
	bc2.set_replay_decisions([])
	bc2.run_to_end()
	assert_eq(bc1.state.snapshot_hash(), bc2.state.snapshot_hash(),
		"空决策回放等同原 AI 决策路径")
