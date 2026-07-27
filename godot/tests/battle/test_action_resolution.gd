extends GutTest
## E2-02：ActionSource / ActionResolution / BattleController.apply_action 核心契约

const _ERROR_CODES: Array[StringName] = [
	&"INVALID_ACTION", &"WRONG_HAND", &"WRONG_DECISION", &"WRONG_SEAT",
	&"WRONG_PHASE", &"NOT_OFFERED", &"ALREADY_RESPONDED", &"ENTITY_NOT_FOUND",
	&"RULE_REJECTED", &"NOT_ENABLED", &"MODE_FORBIDDEN", &"REPLAY_MISMATCH",
]


# ---------------------------------------------------------------------------
# ActionSource
# ---------------------------------------------------------------------------

func test_action_source_distinct_string_names_and_is_valid() -> void:
	var sources: Array = [ActionSource.HUMAN, ActionSource.AI, ActionSource.REPLAY]
	for s in sources:
		assert_typeof(s, TYPE_STRING_NAME)
		assert_true(ActionSource.is_valid(s))
	assert_ne(ActionSource.HUMAN, ActionSource.AI)
	assert_ne(ActionSource.HUMAN, ActionSource.REPLAY)
	assert_ne(ActionSource.AI, ActionSource.REPLAY)
	for bad in [&"UNKNOWN", &"", "HUMAN", "AI", "REPLAY", null, 0, {}]:
		assert_false(ActionSource.is_valid(bad), "is_valid 应拒绝 %s" % str(bad))


# ---------------------------------------------------------------------------
# ActionResolution.success / rejected
# ---------------------------------------------------------------------------

func test_action_resolution_success_accepts_event_array_only() -> void:
	var ev: BattleEvent = BattleEvent.make("PLAYER_ACTION", 0, null, {"nested": [1, 2]})
	var ok: ActionResolution = ActionResolution.success([ev])
	assert_not_null(ok)
	assert_true(ok.accepted)
	assert_eq(ok.error_code, &"")
	assert_eq(ok.events.size(), 1)
	assert_true(ok.events[0] is BattleEvent)

	var empty: ActionResolution = ActionResolution.success([])
	assert_not_null(empty)
	assert_true(empty.accepted)
	assert_eq(empty.error_code, &"")
	assert_eq(empty.events.size(), 0)

	# fail-closed：坏 Array + 普通非 Array（Dictionary/String/int），非仅特判 null
	var illegal: Array = [
		null, {}, "not_array", 42,
		[1, 2], ["not_event"], [{}],
		[BattleEvent.make("PLAYER_ACTION", 0, null, {}), "bad"],
	]
	for raw in illegal:
		assert_null(ActionResolution.success(raw), "success 应 fail-closed: %s" % str(raw))


func test_action_resolution_error_code_allowlist_and_rejected() -> void:
	var pairs: Array = [
		[ActionResolution.INVALID_ACTION, &"INVALID_ACTION"],
		[ActionResolution.WRONG_HAND, &"WRONG_HAND"],
		[ActionResolution.WRONG_DECISION, &"WRONG_DECISION"],
		[ActionResolution.WRONG_SEAT, &"WRONG_SEAT"],
		[ActionResolution.WRONG_PHASE, &"WRONG_PHASE"],
		[ActionResolution.NOT_OFFERED, &"NOT_OFFERED"],
		[ActionResolution.ALREADY_RESPONDED, &"ALREADY_RESPONDED"],
		[ActionResolution.ENTITY_NOT_FOUND, &"ENTITY_NOT_FOUND"],
		[ActionResolution.RULE_REJECTED, &"RULE_REJECTED"],
		[ActionResolution.NOT_ENABLED, &"NOT_ENABLED"],
		[ActionResolution.MODE_FORBIDDEN, &"MODE_FORBIDDEN"],
		[ActionResolution.REPLAY_MISMATCH, &"REPLAY_MISMATCH"],
	]
	assert_eq(pairs.size(), 12)
	assert_eq(_ERROR_CODES.size(), 12)
	for pair in pairs:
		var const_val: StringName = pair[0]
		var literal: StringName = pair[1]
		assert_typeof(const_val, TYPE_STRING_NAME)
		assert_eq(const_val, literal)
		assert_true(literal in _ERROR_CODES)
		var res: ActionResolution = ActionResolution.rejected(const_val)
		assert_not_null(res, "rejected(%s) 应成功" % String(const_val))
		assert_false(res.accepted)
		assert_eq(res.error_code, const_val)
		assert_eq(res.events.size(), 0)

	var rejects: Array = [
		&"", "", null, 0, {},
		"INVALID_ACTION", "WRONG_HAND", "RULE_REJECTED",
		&"UNKNOWN", &"INVALID_ACTON", &"X", &"NOPE", &"TEST_INVALID_RESULT",
	]
	for bad in rejects:
		assert_null(ActionResolution.rejected(bad), "rejected 应拒绝 %s" % str(bad))


# ---------------------------------------------------------------------------
# 只读 + events 深拷贝
# ---------------------------------------------------------------------------

func test_action_resolution_readonly_getters_no_setters() -> void:
	var script: GDScript = load("res://battle/action_resolution.gd") as GDScript
	assert_not_null(script)
	var methods: Dictionary = {}
	for m in script.get_script_method_list():
		methods[String(m.get("name", ""))] = true
	for field in ["accepted", "error_code", "events"]:
		assert_true(methods.has("@%s_getter" % field), "须有 @%s_getter" % field)
		assert_false(methods.has("@%s_setter" % field), "不得有 @%s_setter" % field)
	var res: ActionResolution = ActionResolution.rejected(ActionResolution.INVALID_ACTION)
	assert_typeof(res.accepted, TYPE_BOOL)
	assert_typeof(res.error_code, TYPE_STRING_NAME)
	assert_typeof(res.events, TYPE_ARRAY)


func test_action_resolution_events_deep_copy_on_write_and_read() -> void:
	var nested: Array = [1, 2]
	var extra: Dictionary = {"nested": nested}
	var ev: BattleEvent = BattleEvent.make("PLAYER_ACTION", 0, null, extra)
	var source: Array = [ev]
	var res: ActionResolution = ActionResolution.success(source)
	assert_not_null(res)

	source.clear()
	source.append("poison")
	extra["nested"] = [9, 9]
	extra["hijacked"] = true
	nested.append(3)
	ev.extra["after_success"] = true

	var got: Array = res.events
	assert_eq(got.size(), 1)
	var got_ev: BattleEvent = got[0] as BattleEvent
	assert_not_null(got_ev)
	got.clear()
	got.append("mutated")
	got_ev.extra["from_getter"] = true
	if got_ev.extra.has("nested") and got_ev.extra["nested"] is Array:
		got_ev.extra["nested"].append(99)

	var again: Array = res.events
	assert_eq(again.size(), 1)
	var again_ev: BattleEvent = again[0] as BattleEvent
	assert_not_null(again_ev)
	var snap: Dictionary = again_ev.extra
	assert_false(snap.has("hijacked"))
	assert_false(snap.has("after_success"))
	assert_false(snap.has("from_getter"))
	assert_eq(snap.get("nested"), [1, 2])


# ---------------------------------------------------------------------------
# to_dict
# ---------------------------------------------------------------------------

func test_action_resolution_to_dict_exact_serializable() -> void:
	var ok: ActionResolution = ActionResolution.success([
		BattleEvent.make("PLAYER_ACTION", 0, null, {"nested": [1, 2]}),
	])
	var d_ok: Dictionary = ok.to_dict()
	_assert_exact_to_dict_keys(d_ok)
	assert_eq(d_ok["accepted"], true)
	assert_eq(StringName(d_ok["error_code"]), &"")
	assert_typeof(d_ok["events"], TYPE_ARRAY)
	assert_eq(d_ok["events"].size(), 1)
	assert_typeof(d_ok["events"][0], TYPE_DICTIONARY)
	_assert_no_object_values(d_ok)
	var ed: Dictionary = d_ok["events"][0]
	for k in BattleEvent.make("PLAYER_ACTION", 0, null, {"nested": [1, 2]}).to_dict().keys():
		assert_true(ed.has(k), "events[0] 应含键 %s" % str(k))
	if ed.has("extra") and ed["extra"] is Dictionary:
		assert_eq(ed["extra"].get("nested"), [1, 2])

	var rej: ActionResolution = ActionResolution.rejected(ActionResolution.RULE_REJECTED)
	var d_rej: Dictionary = rej.to_dict()
	_assert_exact_to_dict_keys(d_rej)
	assert_eq(d_rej["accepted"], false)
	assert_eq(StringName(d_rej["error_code"]), &"RULE_REJECTED")
	assert_eq(d_rej["events"], [])
	_assert_no_object_values(d_rej)


func _assert_exact_to_dict_keys(d: Dictionary) -> void:
	assert_eq(d.size(), 3)
	assert_true(d.has("accepted"))
	assert_true(d.has("error_code"))
	assert_true(d.has("events"))
	for k in d.keys():
		assert_true(str(k) in ["accepted", "error_code", "events"], "多余键 %s" % str(k))


func _assert_no_object_values(value: Variant, path: String = "root") -> void:
	match typeof(value):
		TYPE_OBJECT:
			fail_test("to_dict 不得含 Object @ %s" % path)
		TYPE_ARRAY:
			var i: int = 0
			for item in value:
				_assert_no_object_values(item, "%s[%d]" % [path, i])
				i += 1
		TYPE_DICTIONARY:
			for k in value.keys():
				_assert_no_object_values(value[k], "%s.%s" % [path, str(k)])


# ---------------------------------------------------------------------------
# BattleController.apply_action（动态 load；禁止静态类型引用 BC / snapshot）
# ---------------------------------------------------------------------------

func _hand_iids(seat: Seat) -> Array:
	var out: Array = []
	for t in seat.hand.tiles():
		out.append(int(t.instance_id))
	return out


## 紧凑领域 fixture；禁止 snapshot_dict / hash
func _domain_fixture(instance: Object) -> Dictionary:
	var state: BattleState = instance.get("state") as BattleState
	assert_not_null(state)
	if state == null:
		return {}
	var events: Variant = instance.get("events")
	assert_true(events is Array, "events 须为 Array，typeof=%s" % typeof(events))
	if not (events is Array):
		return {}
	var hand_sizes: Array = []
	var hand_iids: Array = []
	for i in range(4):
		var seat: Seat = state.seats[i]
		hand_sizes.append(seat.hand.size())
		hand_iids.append(_hand_iids(seat))
	return {
		"current_seat": state.current_seat,
		"phase": state.phase,
		"hand_seq": state.hand_seq,
		"scores": state.scores.duplicate(),
		"live_wall_size": state.wall.live_wall_size(),
		"hand_sizes": hand_sizes,
		"hand_iids": hand_iids,
		"events_len": (events as Array).size(),
	}


func test_battle_controller_apply_action_null_returns_invalid_action() -> void:
	var script: GDScript = load("res://battle/battle_controller.gd") as GDScript
	assert_not_null(script, "BattleController 脚本应可 load")
	if script == null:
		return
	assert_true(script.can_instantiate(), "BattleController 必须可实例化")
	if not script.can_instantiate():
		return

	# 脚本 method metadata 严格唯一 API；实例直接 call，禁止 has_method fallback
	var apply_count: int = 0
	var has_submit: bool = false
	for m in script.get_script_method_list():
		var n: String = String(m.get("name", ""))
		if n == "apply_action":
			apply_count += 1
		elif n == "submit_action":
			has_submit = true
	assert_eq(apply_count, 1, "须恰好唯一 apply_action")
	assert_false(has_submit, "旧 submit_action 不得存在")

	var instance: Object = script.new(0, 0, false, TileId.E, 0)
	assert_not_null(instance)
	var before: Dictionary = _domain_fixture(instance)
	if before.is_empty():
		return
	var state_before: Variant = instance.get("state")

	var result: Variant = instance.call("apply_action", null, ActionSource.HUMAN)
	assert_true(result is ActionResolution, "须返回 ActionResolution，typeof=%s" % typeof(result))
	if not (result is ActionResolution):
		return
	var resolution: ActionResolution = result as ActionResolution
	assert_false(resolution.accepted)
	assert_eq(resolution.error_code, ActionResolution.INVALID_ACTION)
	assert_eq(resolution.events, [])

	var after: Dictionary = _domain_fixture(instance)
	if after.is_empty():
		return
	assert_eq(instance.get("state"), state_before)
	for k in before.keys():
		assert_eq(after[k], before[k], "null Action 零修改字段 %s" % k)
