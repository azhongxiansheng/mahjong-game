extends GutTest

# #240：HeadlessRoomSession 惰性建房 / READY 门槛 / 真实 LocalLoopback 权威。

const CHARS_OK := true


func _claims(room := "room-hs", parts: Array = ["HUMAN", "AI", "AI", "AI"]) -> Dictionary:
	return {
		"room_id": room,
		"seat": 0,
		"session_id": "sess-0",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": parts,
		"expires_at_unix": 9999999999,
	}


func test_bootstrap_generates_seed_and_real_server() -> void:
	var s := HeadlessRoomSession.new()
	s.set_seed_override_for_test(42)
	assert_true(s.bootstrap_from_claims(_claims()))
	assert_true(s.is_bootstrapped())
	assert_eq(s.authority_seed, 42)
	assert_eq(s.character_ids.size(), 4)
	assert_not_null(s.server)
	assert_not_null(s.server._bc)
	assert_false(s.is_started())
	# 客户端不得在 claims 里注入 seed：bootstrap 忽略外来 seed 字段
	var c2 := _claims("room-hs-2")
	c2["seed"] = 999
	var s2 := HeadlessRoomSession.new()
	s2.set_seed_override_for_test(7)
	assert_true(s2.bootstrap_from_claims(c2))
	assert_eq(s2.authority_seed, 7)


func test_ready_before_join_fails_and_four_human_gate() -> void:
	var s := HeadlessRoomSession.new()
	s.set_seed_override_for_test(1)
	var parts := ["HUMAN", "HUMAN", "HUMAN", "HUMAN"]
	assert_true(s.bootstrap_from_claims(_claims("room-4h", parts)))
	var r0 := s.ready(0, "sess-0")
	assert_false(bool(r0["ok"]), "未 JOIN 不得 READY")
	for i in range(4):
		var j := s.join(i, "sess-%d" % i)
		assert_true(bool(j["ok"]), "join seat %d" % i)
	# 仅 3 人 READY 不得 start
	for i in range(3):
		var r := s.ready(i, "sess-%d" % i)
		assert_true(bool(r["ok"]))
	assert_false(s.is_started())
	assert_false(s.all_humans_ready())
	var r3 := s.ready(3, "sess-3")
	assert_true(bool(r3["ok"]))
	assert_true(s.is_started(), "四 HUMAN 全 READY 后必须 start")
	assert_gt(s.current_server_seq(), 0)


func test_ai_seats_do_not_block_start() -> void:
	var s := HeadlessRoomSession.new()
	s.set_seed_override_for_test(11)
	assert_true(s.bootstrap_from_claims(_claims("room-1h", ["HUMAN", "AI", "AI", "AI"])))
	assert_false(bool(s.join(1, "ai-sess")["ok"]), "AI 席不得 JOIN")
	assert_true(bool(s.join(0, "human-0")["ok"]))
	assert_true(bool(s.ready(0, "human-0")["ok"]))
	assert_true(s.is_started(), "仅等全部 HUMAN")


func test_action_requires_start_and_uses_real_submit() -> void:
	var s := HeadlessRoomSession.new()
	s.set_seed_override_for_test(99)
	assert_true(s.bootstrap_from_claims(_claims("room-act", ["HUMAN", "AI", "AI", "AI"])))
	assert_true(bool(s.join(0, "h0")["ok"]))
	# 未 start 的 action
	var early := Action.from_dict({
		"protocol_version": 1,
		"command_id": "11111111-1111-4111-8111-111111111111",
		"room_id": "room-act",
		"seat": 0,
		"hand_seq": 0,
		"decision_id": "22222222-2222-4222-8222-222222222222",
		"kind": "PASS",
		"payload": {},
		"client_seq": 1,
	})
	var cr0: CommandResult = s.submit_action_for_seat(0, early)
	assert_not_null(cr0)
	assert_eq(cr0.status, "REJECTED")
	assert_true(bool(s.ready(0, "h0")["ok"]))
	assert_true(s.is_started())
	# 取 TURN_PROMPT 合法弃牌
	var journal: Array = s.event_journal(0)
	var prompt: NetworkedEvent = null
	for e in journal:
		if e is NetworkedEvent and (e as NetworkedEvent).kind == "TURN_PROMPT":
			prompt = e
			break
	assert_not_null(prompt, "start 后须有 TURN_PROMPT")
	if prompt == null:
		return
	var meta := _discard_meta(prompt)
	assert_false(meta.is_empty())
	if meta.is_empty():
		return
	var act := Action.from_dict({
		"protocol_version": 1,
		"command_id": "33333333-3333-4333-8333-333333333333",
		"room_id": "room-act",
		"seat": int(meta["seat"]),
		"hand_seq": int(meta["hand_seq"]),
		"decision_id": str(meta["decision_id"]),
		"kind": "DISCARD",
		"payload": {"tile_instance_id": int(meta["tile_instance_id"])},
		"client_seq": 2,
	})
	var cr: CommandResult = s.submit_action_for_seat(0, act)
	assert_not_null(cr)
	assert_eq(cr.status, "ACCEPTED", "合法 Action 须经真实规则入口接受")
	# 越权 seat：绑定 seat0 却提交 seat1
	var hijack := Action.from_dict({
		"protocol_version": 1,
		"command_id": "44444444-4444-4444-8444-444444444444",
		"room_id": "room-act",
		"seat": 1,
		"hand_seq": int(meta["hand_seq"]),
		"decision_id": str(meta["decision_id"]),
		"kind": "DISCARD",
		"payload": {"tile_instance_id": int(meta["tile_instance_id"])},
		"client_seq": 3,
	})
	var cr_bad: CommandResult = s.submit_action_for_seat(0, hijack)
	assert_eq(cr_bad.status, "REJECTED")
	assert_eq(cr_bad.error_code, "UNAUTHORIZED")


func test_public_projection_consumable_by_networked_battle_controller() -> void:
	var s := HeadlessRoomSession.new()
	s.set_seed_override_for_test(1234)
	assert_true(s.bootstrap_from_claims(_claims("room-nbc", ["HUMAN", "HUMAN", "AI", "AI"])))
	assert_true(bool(s.join(0, "a")["ok"]))
	assert_true(bool(s.join(1, "b")["ok"]))
	assert_true(bool(s.ready(0, "a")["ok"]))
	assert_true(bool(s.ready(1, "b")["ok"]))
	assert_true(s.is_started())
	var nbc0 := NetworkedBattleController.new("room-nbc", 0)
	var nbc1 := NetworkedBattleController.new("room-nbc", 1)
	assert_true(nbc0.ingest_event_stream(s.event_journal(0)))
	assert_true(nbc1.ingest_event_stream(s.event_journal(1)))
	assert_gt(nbc0.current_seq(), 0)
	assert_gt(nbc1.current_seq(), 0)
	var v0: Dictionary = nbc0.get_public_view()
	var v1: Dictionary = nbc1.get_public_view()
	assert_false(v0.is_empty())
	assert_false(v1.is_empty())
	# 各席投影可不同（手牌可见性），但均应有 core_table
	assert_false(nbc0.get_core_table_view().is_empty())
	assert_false(nbc1.get_core_table_view().is_empty())


func _discard_meta(prompt: NetworkedEvent) -> Dictionary:
	if prompt == null:
		return {}
	var p: Dictionary = prompt.payload
	for o in p.get("allowed_actions", []):
		if typeof(o) != TYPE_DICTIONARY:
			continue
		if str(o.get("kind", "")) != "DISCARD":
			continue
		var opts: Array = o.get("payload_options", [])
		if opts.is_empty():
			continue
		return {
			"seat": int(p["seat"]),
			"hand_seq": int(p["hand_seq"]),
			"decision_id": str(p["decision_id"]),
			"tile_instance_id": int(opts[0]["tile_instance_id"]),
		}
	return {}
