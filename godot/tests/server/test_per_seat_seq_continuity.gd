extends GutTest

# #240 round-3 Red：四席可见流 server_seq 连续；NBC 每条 ingest true；
# journal 含 ACTION_APPLIED（非仅“收到消息”布尔）。

const SID := "seq-continuity-e3-240"
const CHARS := [&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"]


func _cfg_all_human() -> GameSessionConfig:
	return GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL,
		&"EAST",
		&"STANDARD",
		[&"HUMAN", &"HUMAN", &"HUMAN", &"HUMAN"],
		CHARS,
		42,
		SID,
		"riichi-v1"
	)


func _assert_seq_continuous(events: Array, tag: String) -> void:
	var prev := 0
	for i in range(events.size()):
		assert_true(events[i] is NetworkedEvent, "%s[%d] NetworkedEvent" % [tag, i])
		if not (events[i] is NetworkedEvent):
			return
		var ne: NetworkedEvent = events[i]
		assert_eq(int(ne.server_seq), prev + 1, "%s 序号须连续 got=%d want=%d" % [
			tag, ne.server_seq, prev + 1,
		])
		prev = int(ne.server_seq)


func _discard_meta(prompt: NetworkedEvent) -> Dictionary:
	if prompt == null or prompt.kind != "TURN_PROMPT":
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


func test_four_human_start_and_action_per_seat_stream_continuous_nbc() -> void:
	var server := LocalLoopbackServer.new(_cfg_all_human(), 0)
	assert_not_null(server)
	assert_true(server.start())

	# start 后：四席 journal 等长、序号从 1 连续；仅决策席有 TURN_PROMPT
	var j0: Array = server.event_journal(0)
	assert_gte(j0.size(), 2)
	assert_eq((j0[0] as NetworkedEvent).kind, "ROOM_SNAPSHOT")
	assert_eq((j0[1] as NetworkedEvent).kind, "TURN_PROMPT")
	var prompt_seq: int = int((j0[1] as NetworkedEvent).server_seq)

	for seat in range(4):
		var j: Array = server.event_journal(seat)
		_assert_seq_continuous(j, "start/seat%d" % seat)
		assert_eq(j.size(), j0.size(), "start 后四席 journal 条数须一致（非目标席须 filler）")
		# journal 按下标对齐 server_seq-1（连续从 1 起）
		assert_eq(int((j[prompt_seq - 1] as NetworkedEvent).server_seq), prompt_seq)
		var at_prompt: NetworkedEvent = j[prompt_seq - 1] as NetworkedEvent
		if seat == 0:
			assert_eq(at_prompt.kind, "TURN_PROMPT")
		else:
			assert_eq(at_prompt.kind, "ROOM_SNAPSHOT",
				"非目标席在私有 prompt 序号上须 ROOM_SNAPSHOT filler")
			assert_null(_find_kind(j, "TURN_PROMPT"))

	# 四席 NBC 逐条 ingest 全 true
	var nbcs: Array = []
	for seat in range(4):
		var nbc := NetworkedBattleController.new(SID, seat)
		nbcs.append(nbc)
		var j: Array = server.event_journal(seat)
		for ev in j:
			assert_true(nbc.ingest_networked_event(ev),
				"start seat%d seq=%d kind=%s ingest 须 true" % [
					seat, (ev as NetworkedEvent).server_seq, (ev as NetworkedEvent).kind,
				])
		assert_false(nbc.resync_required())
		assert_eq(nbc.current_seq(), int((j[j.size() - 1] as NetworkedEvent).server_seq))

	# 合法 DISCARD
	var meta := _discard_meta(j0[1] as NetworkedEvent)
	assert_false(meta.is_empty())
	if meta.is_empty():
		return
	var act := Action.from_dict({
		"protocol_version": 1,
		"command_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
		"room_id": SID,
		"seat": int(meta["seat"]),
		"hand_seq": int(meta["hand_seq"]),
		"decision_id": str(meta["decision_id"]),
		"kind": "DISCARD",
		"payload": {"tile_instance_id": int(meta["tile_instance_id"])},
		"client_seq": 1,
	})
	var cr: CommandResult = server.submit_action(act)
	assert_not_null(cr)
	assert_eq(cr.status, "ACCEPTED")

	# 行动后：每席连续 + NBC ingest 全 true + journal 含 ACTION_APPLIED
	for seat in range(4):
		var j: Array = server.event_journal(seat)
		_assert_seq_continuous(j, "post/seat%d" % seat)
		var nbc: NetworkedBattleController = nbcs[seat]
		var after: int = nbc.current_seq()
		var new_evs: Array = server.events_since(seat, after)
		for ev in new_evs:
			assert_true(nbc.ingest_networked_event(ev),
				"post seat%d seq=%d kind=%s ingest 须 true" % [
					seat, (ev as NetworkedEvent).server_seq, (ev as NetworkedEvent).kind,
				])
		assert_false(nbc.resync_required(), "seat%d 不得 resync" % seat)
		var journal: Array = nbc.get_event_journal()
		var has_aa := false
		for e in journal:
			if e is NetworkedEvent and (e as NetworkedEvent).kind == "ACTION_APPLIED":
				has_aa = true
				break
		assert_true(has_aa, "seat%d NBC journal 必须含 ACTION_APPLIED" % seat)


func _find_kind(events: Array, kind: String) -> NetworkedEvent:
	for e in events:
		if e is NetworkedEvent and (e as NetworkedEvent).kind == kind:
			return e
	return null
