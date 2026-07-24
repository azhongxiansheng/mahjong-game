extends GutTest
## E2-02 Unified Action Red。禁止静态 BattleController；动态 load + can_instantiate。
## journal=已接受 Action；load_replay_journal=期望队列（装载后 journal 仍空）。
const ROOM := "practice-room"
const BC_PATH := "res://battle/battle_controller.gd"
const IAUTH_PATH := "res://battle/i_authoritative_battle_controller.gd"
const ENVELOPE_KEYS := [
	"protocol_version", "command_id", "room_id", "seat", "hand_seq",
	"decision_id", "kind", "payload", "client_seq",
]
const UUID_V4_RE := \
	"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
const DECISION_MISMATCH := "550e8400-e29b-41d4-a716-0000000000bb"
const REQUIRED_METHODS := [
	"apply_action", "decision_context_for_seat",
	"action_journal", "load_replay_journal", "replay_status",
]
const FORBIDDEN_METHODS := [
	"submit_action", "set_replay_actions", "extract_actions",
	"set_replay_decisions", "extract_player_actions",
]
const E5_TYPES := [
	"REWARD_WINDOW_OPENED", "REWARD_WINDOW_CLOSING", "REWARD_WINDOW_SETTLED",
	"REWARD_WINDOW_CANCELLED", "ITEM_GRANTED", "ITEM_CONSUMED", "ITEM_APPLIED",
	"CHARACTER_ABILITY_ARMED", "CHARACTER_ABILITY_DISARMED",
]
func _is_uuid_v4(s: String) -> bool:
	if s.length() != 36 or s != s.to_lower():
		return false
	var re := RegEx.new()
	return re.compile(UUID_V4_RE) == OK and re.search(s) != null
func _cmd_uuid(n: int) -> String:
	return "550e8400-e29b-41d4-a716-%012d" % n
func _exact_keys(d: Dictionary, expected: Array) -> bool:
	if d.keys().size() != expected.size():
		return false
	for k in expected:
		if not d.has(k):
			return false
	return true
func _script_names(path: String, kind: String) -> Array:
	var scr: GDScript = load(path) as GDScript
	if scr == null:
		return []
	var names: Array = []
	var items: Array = scr.get_script_method_list() if kind == "method" else scr.get_script_property_list()
	for item in items:
		names.append(str(item.get("name", "")))
	return names
func _make_bc(
	p_seed: int = 1, dealer: int = 0, hand_seq: int = 0, use_heuristic_ai: bool = false
) -> Object:
	var scr: GDScript = load(BC_PATH) as GDScript
	assert_not_null(scr, "BATTLE_RED: 无法 load %s" % BC_PATH)
	if scr == null:
		return null
	assert_true(scr.can_instantiate(), "BATTLE_RED: battle_controller.gd 不可实例化")
	if not scr.can_instantiate():
		return null
	# 唯一构造：seed, dealer, use_heuristic_ai, round_wind, hand_seq
	var bc: Object = scr.new(p_seed, dealer, use_heuristic_ai, TileId.E, hand_seq)
	if bc == null or bc.get("state") == null or bc.get("engine") == null:
		assert_true(false, "BATTLE_RED: 构造/state/engine null")
		return null
	return bc
func _action(
	kind: String, payload: Dictionary, seat: int, hand_seq: int,
	decision_id: String, client_seq: int = 1
) -> Action:
	var cmd: String = _cmd_uuid(client_seq)
	assert_true(_is_uuid_v4(cmd) and _is_uuid_v4(decision_id), "UUID v4+variant")
	var wire := {
		"protocol_version": 1, "command_id": cmd, "room_id": ROOM,
		"seat": seat, "hand_seq": hand_seq, "decision_id": decision_id,
		"kind": kind, "payload": payload.duplicate(true), "client_seq": client_seq,
	}
	assert_true(_exact_keys(wire, ENVELOPE_KEYS), "Action wire exact 九键")
	var a: Action = Action.from_dict(wire)
	assert_not_null(a, "PROTOCOL_RED: Action.from_dict null kind=%s" % kind)
	return a
func _apply(
	bc: Object, action: Action, source: StringName = ActionSource.HUMAN
) -> ActionResolution:
	if bc == null:
		assert_true(false, "BATTLE_RED: apply 需要 controller")
		return null
	var methods: Array = _script_names(BC_PATH, "method")
	assert_true(methods.has("apply_action"), "BATTLE_RED: 唯一入口 apply_action")
	assert_false(methods.has("submit_action"), "BATTLE_RED: 不得有 submit_action")
	var raw: Variant = bc.call("apply_action", action, source)
	assert_true(raw is ActionResolution, "BATTLE_RED: 必须返回 ActionResolution")
	if not (raw is ActionResolution):
		return null
	return raw as ActionResolution
func _ctx(bc: Object, seat: int) -> DecisionContext:
	if bc == null or not _script_names(BC_PATH, "method").has("decision_context_for_seat"):
		assert_true(false, "BATTLE_RED: decision_context_for_seat")
		return null
	var raw: Variant = bc.call("decision_context_for_seat", seat)
	assert_true(raw is DecisionContext, "BATTLE_RED: decision_context_for_seat(%d)" % seat)
	if not (raw is DecisionContext):
		return null
	return raw as DecisionContext
func _hand_iids(seat: Seat) -> Array:
	var out: Array = []
	for t in seat.hand._tiles:
		out.append(int(t.instance_id))
	return out
func _domain_fixture(bc: Object, focus_seat: int) -> Dictionary:
	var state: BattleState = bc.get("state") as BattleState
	var seat: Seat = state.seats[focus_seat]
	var current_discard_iid: int = -1
	var river_iids: Array = []
	for t in state.discards_per_seat[focus_seat]:
		river_iids.append(int((t as Tile).instance_id))
	for s in range(4):
		var river: Array = state.discards_per_seat[s]
		if not river.is_empty():
			current_discard_iid = int((river[-1] as Tile).instance_id)
	return {
		"phase": int(state.phase), "current_seat": int(state.current_seat),
		"hand_seq": int(state.hand_seq), "focus_hand_iids": _hand_iids(seat),
		"focus_hand_size": seat.hand.size(), "focus_river_iids": river_iids,
		"current_discard_iid": current_discard_iid,
		"riichi_declared": bool(seat.riichi.declared),
		"ippatsu": bool(seat.riichi.ippatsu_window), "points": int(seat.points),
		"scores": state.scores.duplicate(), "riichi_sticks": int(state.riichi_sticks),
		"events_len": int((bc.get("events") as Array).size()),
		"last_drawn_iid": int(seat.last_drawn_instance_id),
	}
func _assert_domain_unchanged(before: Dictionary, after: Dictionary, label: String) -> void:
	for k in before.keys():
		assert_eq(after[k], before[k], "零修改领域字段 %s @ %s" % [k, label])
func _enter_discard(bc: Object) -> Dictionary:
	var state: BattleState = bc.get("state") as BattleState
	var engine: TurnEngine = bc.get("engine") as TurnEngine
	if state.phase != BattlePhase.Kind.DISCARD:
		assert_eq(state.phase, BattlePhase.Kind.DRAW, "开局 DRAW")
		var drawn: Tile = engine.draw_for_current()
		assert_not_null(drawn, "draw_for_current 应摸牌")
		if drawn == null:
			return {}
	assert_eq(state.phase, BattlePhase.Kind.DISCARD)
	var seat_id: int = state.current_seat
	var iids: Array = _hand_iids(state.seats[seat_id])
	assert_gt(iids.size(), 0)
	return {
		"seat": seat_id, "hand_iids": iids,
		"last_drawn_iid": int(state.seats[seat_id].last_drawn_instance_id),
		"hand_seq": int(state.hand_seq),
	}
func _discard_offer_iids(ctx: DecisionContext) -> Array:
	assert_not_null(ctx)
	if ctx == null:
		return []
	var out: Array = []
	for offer in ctx.allowed_actions:
		if typeof(offer) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = offer
		if str(d.get("kind", "")) != "DISCARD":
			continue
		for opt in d.get("payload_options", []):
			if opt is Dictionary and (opt as Dictionary).has("tile_instance_id"):
				out.append(int((opt as Dictionary)["tile_instance_id"]))
	assert_gt(out.size(), 0, "BATTLE_RED: 必须 offer DISCARD")
	return out
func _assert_battle_events_only(events: Array, label: String) -> void:
	for i in range(events.size()):
		assert_true(
			events[i] is BattleEvent,
			"events[%d] 必须 BattleEvent（%s），禁止 Dictionary/NetworkedEvent" % [i, label]
		)
func _count_type(events: Array, type_name: String) -> int:
	var n: int = 0
	for ev in events:
		if ev is BattleEvent and str((ev as BattleEvent).type) == type_name:
			n += 1
	return n
func _applied_extras(events: Array) -> Array:
	var out: Array = []
	for ev in events:
		if ev is BattleEvent and str((ev as BattleEvent).type) == "ACTION_APPLIED":
			var extra: Dictionary = {}
			if (ev as BattleEvent).extra != null:
				extra = (ev as BattleEvent).extra.duplicate(true)
			out.append(extra)
	return out
func _e5_found(events: Array) -> Array:
	var found: Array = []
	for ev in events:
		if ev is BattleEvent and str((ev as BattleEvent).type) in E5_TYPES:
			found.append(str((ev as BattleEvent).type))
	return found
func _assert_accepted_resolution_events(resp: ActionResolution, label: String) -> void:
	assert_true(resp.accepted, "必须 accepted: %s" % label)
	assert_eq(resp.error_code, &"", "accepted 时 error_code 必须是空 StringName")
	_assert_battle_events_only(resp.events, "%s ActionResolution.events" % label)
	assert_eq(_count_type(resp.events, "ACTION_APPLIED"), 1, "%s 恰好 1 ACTION_APPLIED" % label)


## journal 元素级深拷贝：两次 getter 元素非同源引用，to_dict 相等；clear 不伤内部。
func _assert_journal_element_deepcopy(
	bc: Object, expected: Action, expected_size: int, label: String
) -> void:
	var j1: Array = bc.call("action_journal") as Array
	assert_eq(j1.size(), expected_size, "%s size" % label)
	assert_true(j1[0] is Action, "%s[0] Action" % label)
	assert_false(is_same(j1[0], expected), "%s j1[0] 非原 action 引用" % label)
	assert_eq((j1[0] as Action).to_dict(), expected.to_dict(), "%s j1 to_dict" % label)
	var j2: Array = bc.call("action_journal") as Array
	assert_eq(j2.size(), expected_size, "%s j2 size" % label)
	assert_false(is_same(j2[0], j1[0]), "%s j2[0] 非 j1[0] 引用" % label)
	assert_eq((j2[0] as Action).to_dict(), (j1[0] as Action).to_dict(), "%s j1/j2 值等" % label)
	j1.clear()
	assert_eq(
		(bc.call("action_journal") as Array).size(), expected_size,
		"%s clear 后内部不变" % label
	)
func test_i_authoritative_base_and_unique_api_surface() -> void:
	var methods: Array = _script_names(BC_PATH, "method")
	for m in REQUIRED_METHODS:
		assert_true(methods.has(m), "BATTLE_RED: 新 API 必须存在: %s" % m)
	for m in FORBIDDEN_METHODS:
		assert_false(methods.has(m), "BATTLE_RED: 旧 API 不得存在: %s" % m)
	assert_false(
		_script_names(BC_PATH, "prop").has("_replay_actions"),
		"BATTLE_RED: 不得暴露 _replay_actions getter/property"
	)
	assert_true(ResourceLoader.exists(IAUTH_PATH), "BATTLE_RED: 缺 i_authoritative_battle_controller.gd")
	if ResourceLoader.exists(IAUTH_PATH):
		var iauth: GDScript = load(IAUTH_PATH) as GDScript
		assert_not_null(iauth, "BATTLE_RED: i_authoritative 不可 load")
		var bc_scr: GDScript = load(BC_PATH) as GDScript
		assert_not_null(bc_scr, "BATTLE_RED: battle_controller 不可 load")
		if bc_scr != null and bc_scr.can_instantiate() and iauth != null:
			assert_eq(
				bc_scr.get_base_script(), iauth,
				"BATTLE_RED: BattleController 直接 base 必须是 i_authoritative_battle_controller.gd"
			)
	var bc: Object = _make_bc(1)
	if bc == null:
		return
	_assert_battle_events_only(bc.get("events") as Array, "construct")
	assert_eq(bc.call("replay_status"), &"IDLE")
	assert_eq((bc.call("action_journal") as Array).size(), 0, "journal 必须空: construct")
func test_legal_discard_accepted_exact_resolved_payload() -> void:
	var bc: Object = _make_bc(7)
	if bc == null:
		return
	var entered: Dictionary = _enter_discard(bc)
	if entered.is_empty():
		return
	var seat: int = int(entered["seat"])
	var ctx: DecisionContext = _ctx(bc, seat)
	if ctx == null:
		return
	assert_true(_is_uuid_v4(ctx.decision_id), "decision_id UUID v4")
	assert_eq(ctx.seat, seat)
	assert_eq(ctx.hand_seq, int(entered["hand_seq"]))
	var offers: Array = _discard_offer_iids(ctx)
	if offers.is_empty():
		return
	var tile_iid: int = int(offers[0])
	assert_true(ctx.allows("DISCARD", {"tile_instance_id": tile_iid}))
	assert_eq((bc.call("action_journal") as Array).size(), 0, "apply 前 journal 空（events 不得反推）")
	var action: Action = _action(
		"DISCARD", {"tile_instance_id": tile_iid},
		seat, int(entered["hand_seq"]), ctx.decision_id, 1
	)
	if action == null:
		return
	var before_n: int = (bc.get("events") as Array).size()
	var resp: ActionResolution = _apply(bc, action, ActionSource.HUMAN)
	if resp == null:
		return
	_assert_accepted_resolution_events(resp, "legal DISCARD")
	var new_ev: Array = (bc.get("events") as Array).slice(before_n)
	_assert_battle_events_only(new_ev, "controller 新增 events")
	assert_eq(_count_type(new_ev, "ACTION_APPLIED"), 1)
	var extras: Array = _applied_extras(new_ev)
	assert_eq(extras.size(), 1)
	var extra: Dictionary = extras[0]
	assert_false(extra.has("normalized_payload"))
	assert_true(extra.has("resolved_payload"))
	var rp: Dictionary = extra["resolved_payload"] as Dictionary
	assert_eq(int(rp.get("tile_instance_id", -2)), tile_iid)
	assert_eq(int(rp.get("seat", -2)), action.seat)
	assert_eq(int(rp.get("hand_seq", -2)), action.hand_seq)
	assert_eq(str(rp.get("decision_id", "")), action.decision_id)
	var resp_extras: Array = _applied_extras(resp.events)
	assert_eq(resp_extras.size(), 1)
	assert_eq((resp_extras[0] as Dictionary).get("resolved_payload"), rp)
	_assert_journal_element_deepcopy(bc, action, 1, "legal DISCARD journal")
func test_reject_stable_codes_domain_zero_mod() -> void:
	var bc: Object = _make_bc(11)
	if bc == null:
		return
	var entered: Dictionary = _enter_discard(bc)
	if entered.is_empty():
		return
	var seat: int = int(entered["seat"])
	var ctx: DecisionContext = _ctx(bc, seat)
	if ctx == null:
		return
	var hs: int = int(entered["hand_seq"])
	var did: String = ctx.decision_id
	var offers: Array = _discard_offer_iids(ctx)
	if offers.is_empty():
		return
	var good: int = int(offers[0])
	var missing_from_hand := Tile.INVALID_INSTANCE_ID
	var actor_seat: Seat = (bc.get("state") as BattleState).seats[seat] as Seat
	for tile in (bc.get("state") as BattleState).wall._tiles:
		var candidate_iid: int = int((tile as Tile).instance_id)
		if actor_seat.hand.find_by_instance_id(candidate_iid) == null:
			missing_from_hand = candidate_iid
			break
	assert_ne(missing_from_hand, Tile.INVALID_INSTANCE_ID,
		"须从当前局牌墙找到一张不在 actor 手牌中的合法实体")
	if missing_from_hand == Tile.INVALID_INSTANCE_ID:
		return
	var cases: Array = [
		["WRONG_HAND", ActionResolution.WRONG_HAND,
			_action("DISCARD", {
				"tile_instance_id": good + ProtocolConstants.TILES_PER_HAND,
			}, seat, hs + 1, did, 10)],
		["WRONG_DECISION", ActionResolution.WRONG_DECISION,
			_action("DISCARD", {"tile_instance_id": good}, seat, hs, DECISION_MISMATCH, 11)],
		["WRONG_SEAT", ActionResolution.WRONG_SEAT,
			_action("DISCARD", {"tile_instance_id": good}, (seat + 1) % 4, hs, did, 12)],
		["ENTITY_NOT_FOUND", ActionResolution.ENTITY_NOT_FOUND,
			_action("DISCARD", {"tile_instance_id": missing_from_hand}, seat, hs, did, 13)],
		["NOT_OFFERED", ActionResolution.NOT_OFFERED,
			_action("PASS", {}, seat, hs, did, 14)],
	]
	for c in cases:
		var act: Action = c[2] as Action
		if act == null:
			assert_true(false, "PROTOCOL_RED: %s Action 不可解析" % str(c[0]))
			return
		var before: Dictionary = _domain_fixture(bc, seat)
		var resp: ActionResolution = _apply(bc, act)
		if resp == null:
			return
		assert_false(resp.accepted, "应拒绝 %s" % str(c[0]))
		assert_eq(resp.error_code, c[1], "稳定码 %s" % str(c[0]))
		_assert_domain_unchanged(before, _domain_fixture(bc, seat), str(c[0]))
		_assert_battle_events_only(bc.get("events") as Array, str(c[0]))
	var state: BattleState = bc.get("state") as BattleState
	var saved_phase: int = state.phase
	state.phase = BattlePhase.Kind.DRAW
	var before_p: Dictionary = _domain_fixture(bc, seat)
	assert_eq(int(before_p["phase"]), int(BattlePhase.Kind.DRAW))
	var act_p: Action = _action("DISCARD", {"tile_instance_id": good}, seat, hs, did, 15)
	if act_p == null:
		return
	var resp_p: ActionResolution = _apply(bc, act_p)
	if resp_p == null:
		return
	assert_false(resp_p.accepted)
	assert_eq(resp_p.error_code, ActionResolution.WRONG_PHASE)
	_assert_domain_unchanged(before_p, _domain_fixture(bc, seat), "WRONG_PHASE 含 phase")
	state.phase = saved_phase
func test_item_use_not_enabled_no_action_applied_no_e5() -> void:
	var bc: Object = _make_bc(91)
	if bc == null:
		return
	var entered: Dictionary = _enter_discard(bc)
	if entered.is_empty():
		return
	var seat: int = int(entered["seat"])
	var ctx: DecisionContext = _ctx(bc, seat)
	if ctx == null:
		return
	var act: Action = _action(
		"ITEM_USE", {"item_instance_id": "inst_abc"},
		seat, int(entered["hand_seq"]), ctx.decision_id, 1
	)
	if act == null:
		return
	var before: Dictionary = _domain_fixture(bc, seat)
	var resp: ActionResolution = _apply(bc, act)
	if resp == null:
		return
	assert_false(resp.accepted)
	assert_eq(resp.error_code, ActionResolution.NOT_ENABLED)
	assert_eq(_count_type(bc.get("events") as Array, "ACTION_APPLIED"), 0)
	assert_eq(_e5_found(bc.get("events") as Array).size(), 0)
	_assert_domain_unchanged(before, _domain_fixture(bc, seat), "ITEM_USE")
	assert_eq((bc.call("action_journal") as Array).size(), 0, "ITEM_USE 拒绝不进 journal")
func test_human_ai_replay_only_apply_action_into_journal() -> void:
	var sources: Array = [ActionSource.HUMAN, ActionSource.AI, ActionSource.REPLAY]
	var seq: int = 0
	for source in sources:
		seq += 1
		assert_true(ActionSource.is_valid(source), "source 合法 %s" % str(source))
		var bc: Object = _make_bc(40 + seq)
		if bc == null:
			return
		var ent: Dictionary = _enter_discard(bc)
		if ent.is_empty():
			return
		var seat: int = int(ent["seat"])
		var ctx: DecisionContext = _ctx(bc, seat)
		if ctx == null:
			return
		var offers: Array = _discard_offer_iids(ctx)
		if offers.is_empty():
			return
		assert_eq((bc.call("action_journal") as Array).size(), 0, "来源 %s apply 前" % str(source))
		var act: Action = _action(
			"DISCARD", {"tile_instance_id": int(offers[0])},
			seat, int(ent["hand_seq"]), ctx.decision_id, seq
		)
		if act == null:
			return
		# REPLAY 不得在无 loaded expected journal 时直接 accepted
		if source == ActionSource.REPLAY:
			assert_true(
				bool(bc.call("load_replay_journal", [Action.from_dict(act.to_dict())])),
				"REPLAY 须先装载期望"
			)
			assert_eq(bc.call("replay_status"), &"LOADED")
			assert_eq((bc.call("action_journal") as Array).size(), 0, "装载后 journal 仍空")
		var resp: ActionResolution = _apply(bc, act, source)
		if resp == null:
			return
		assert_true(resp.accepted, "来源 %s 合法 DISCARD" % str(source))
		assert_eq(resp.error_code, &"", "空 StringName")
		_assert_journal_element_deepcopy(bc, act, 1, "source %s journal" % str(source))
func test_replay_api_load_running_mismatch_and_lifecycle_unconsumed() -> void:
	var methods: Array = _script_names(BC_PATH, "method")
	for m in ["action_journal", "load_replay_journal", "replay_status", "run_to_end"]:
		assert_true(methods.has(m), "BATTLE_RED: 缺 %s" % m)
	for m in FORBIDDEN_METHODS:
		assert_false(methods.has(m), "BATTLE_RED: 旧 API %s" % m)
	var recorder: Object = _make_bc(61)
	if recorder == null:
		return
	var ent: Dictionary = _enter_discard(recorder)
	if ent.is_empty():
		return
	var seat: int = int(ent["seat"])
	var ctx: DecisionContext = _ctx(recorder, seat)
	if ctx == null:
		return
	var offers: Array = _discard_offer_iids(ctx)
	if offers.is_empty():
		return
	assert_eq((recorder.call("action_journal") as Array).size(), 0, "录制前")
	var recorded: Action = _action(
		"DISCARD", {"tile_instance_id": int(offers[0])},
		seat, int(ent["hand_seq"]), ctx.decision_id, 1
	)
	if recorded == null:
		return
	var rec_resp: ActionResolution = _apply(recorder, recorded, ActionSource.HUMAN)
	if rec_resp == null:
		return
	assert_true(rec_resp.accepted)
	_assert_journal_element_deepcopy(recorder, recorded, 1, "recorded journal")
	var recorded_action: Action = Action.from_dict(
		((recorder.call("action_journal") as Array)[0] as Action).to_dict()
	)
	assert_eq(recorded_action.to_dict(), recorded.to_dict())
	var bad: Object = _make_bc(62)
	if bad == null:
		return
	assert_false(bool(bad.call("load_replay_journal", [{"kind": "DISCARD"}])))
	assert_false(bool(bad.call("load_replay_journal", "nope")))
	assert_eq(bad.call("replay_status"), &"IDLE")
	assert_eq((bad.call("action_journal") as Array).size(), 0, "非法装载后 journal 仍空")
	# complete：装载后 journal 空；外部数组 clear 不影响；消费完 → COMPLETED
	var complete: Object = _make_bc(61)
	if complete == null:
		return
	assert_eq(complete.call("replay_status"), &"IDLE")
	var raw_in: Array = [Action.from_dict(recorded_action.to_dict())]
	assert_true(bool(complete.call("load_replay_journal", raw_in)), "Action[] 装载")
	assert_eq(complete.call("replay_status"), &"LOADED")
	assert_eq((complete.call("action_journal") as Array).size(), 0, "装载后 journal 仍空")
	raw_in[0] = null
	raw_in.clear()
	if _enter_discard(complete).is_empty():
		return
	if _ctx(complete, int((complete.get("state") as BattleState).current_seat)) == null:
		return
	var r_ok: ActionResolution = _apply(
		complete, Action.from_dict(recorded_action.to_dict()), ActionSource.REPLAY
	)
	if r_ok == null:
		return
	assert_true(r_ok.accepted, "匹配期望的 REPLAY 必须 accepted")
	assert_eq(complete.call("replay_status"), &"COMPLETED")
	_assert_journal_element_deepcopy(complete, recorded_action, 1, "done journal")
	# mismatch：同 seed 真实窗；load 期望 recorded；提交另一条领域合法不同 DISCARD
	var mis: Object = _make_bc(61)
	if mis == null:
		return
	assert_true(bool(mis.call("load_replay_journal", [Action.from_dict(recorded_action.to_dict())])))
	assert_eq((mis.call("action_journal") as Array).size(), 0, "mismatch 装载后")
	var ent_m: Dictionary = _enter_discard(mis)
	if ent_m.is_empty():
		return
	var seat_m: int = int(ent_m["seat"])
	var ctx_m: DecisionContext = _ctx(mis, seat_m)
	if ctx_m == null:
		return
	var offers_m: Array = _discard_offer_iids(ctx_m)
	if offers_m.is_empty():
		return
	var alt_iid: int = int(offers_m[0])
	if offers_m.size() >= 2 and alt_iid == int(recorded_action.payload["tile_instance_id"]):
		alt_iid = int(offers_m[1])
	assert_true(ctx_m.allows("DISCARD", {"tile_instance_id": alt_iid}))
	var alt: Action = _action(
		"DISCARD", {"tile_instance_id": alt_iid},
		seat_m, int(ent_m["hand_seq"]), ctx_m.decision_id, 50
	)
	if alt == null:
		return
	assert_ne(alt.to_dict(), recorded_action.to_dict())
	var r_mis: ActionResolution = _apply(mis, alt, ActionSource.REPLAY)
	if r_mis == null:
		return
	assert_false(r_mis.accepted)
	assert_eq(r_mis.error_code, ActionResolution.REPLAY_MISMATCH, "不得被 WRONG_* 抢走")
	assert_eq(mis.call("replay_status"), &"MISMATCH")
	assert_eq((mis.call("action_journal") as Array).size(), 0, "mismatch 拒绝不进 journal")
	# partial：2 条期望只成功消费第 1 条 → RUNNING（生命周期未结束）
	var running: Object = _make_bc(61)
	if running == null:
		return
	var extra_expect: Action = _action(
		"DISCARD", {"tile_instance_id": int(offers[0])},
		seat, int(ent["hand_seq"]), ctx.decision_id, 2
	)
	if extra_expect == null:
		return
	assert_true(bool(running.call("load_replay_journal", [
		Action.from_dict(recorded_action.to_dict()),
		Action.from_dict(extra_expect.to_dict()),
	])))
	assert_eq((running.call("action_journal") as Array).size(), 0, "partial 装载后")
	if _enter_discard(running).is_empty():
		return
	var r_run: ActionResolution = _apply(
		running, Action.from_dict(recorded_action.to_dict()), ActionSource.REPLAY
	)
	if r_run == null:
		return
	assert_true(r_run.accepted)
	assert_eq(running.call("replay_status"), &"RUNNING", "部分消费须 RUNNING 非 UNCONSUMED")
	assert_eq((running.call("action_journal") as Array).size(), 1)
	# UNCONSUMED：完整生命周期结束后仍有剩余期望
	const UNC_SEED := 77
	const TAIL_SEQ := 999999999999
	var life_rec: Object = _make_bc(UNC_SEED, 0, 0, true)
	if life_rec == null:
		return
	var rec_end: Variant = life_rec.call("run_to_end")
	assert_true(typeof(rec_end) == TYPE_DICTIONARY, "recorder run_to_end 须 Dictionary settle")
	var full_j: Array = life_rec.call("action_journal") as Array
	assert_gt(full_j.size(), 0, "heuristic run_to_end 须产出非空 action_journal")
	var bloated: Array = []
	for item in full_j:
		assert_true(item is Action, "journal 元素须 Action")
		var cloned: Action = Action.from_dict((item as Action).to_dict())
		assert_not_null(cloned, "journal Action 可 round-trip")
		bloated.append(cloned)
	# 尾项协议合法但 command_id/client_seq 唯一，避免幂等/重复拒绝
	var tail_wire: Dictionary = (full_j[-1] as Action).to_dict()
	tail_wire["command_id"] = _cmd_uuid(TAIL_SEQ)
	tail_wire["client_seq"] = TAIL_SEQ
	var tail: Action = Action.from_dict(tail_wire)
	assert_not_null(tail, "尾部追加合法 Action（唯一 command_id）")
	assert_ne(tail.to_dict(), (full_j[-1] as Action).to_dict(), "尾项须与 journal 末条不同")
	bloated.append(tail)
	assert_eq(bloated.size(), full_j.size() + 1)
	var life_rep: Object = _make_bc(UNC_SEED, 0, 0, true)
	if life_rep == null:
		return
	assert_true(bool(life_rep.call("load_replay_journal", bloated)), "bloated journal 装载")
	assert_eq(life_rep.call("replay_status"), &"LOADED")
	assert_eq((life_rep.call("action_journal") as Array).size(), 0, "lifecycle 装载后 journal 空")
	var rep_end: Variant = life_rep.call("run_to_end")
	assert_true(typeof(rep_end) == TYPE_DICTIONARY, "replayer run_to_end 须 Dictionary settle")
	assert_eq(
		life_rep.call("replay_status"), &"UNCONSUMED",
		"权威生命周期结束后仍有剩余 → UNCONSUMED"
	)
func test_controller_events_battle_event_only() -> void:
	var bc: Object = _make_bc(3)
	if bc == null:
		return
	var ent: Dictionary = _enter_discard(bc)
	if ent.is_empty():
		return
	var seat: int = int(ent["seat"])
	var ctx: DecisionContext = _ctx(bc, seat)
	if ctx == null:
		return
	var offers: Array = _discard_offer_iids(ctx)
	if offers.is_empty():
		return
	assert_eq((bc.call("action_journal") as Array).size(), 0, "events 测试 apply 前")
	var act: Action = _action(
		"DISCARD", {"tile_instance_id": int(offers[0])},
		seat, int(ent["hand_seq"]), ctx.decision_id, 1
	)
	if act == null:
		return
	var before_n: int = (bc.get("events") as Array).size()
	var resp: ActionResolution = _apply(bc, act, ActionSource.HUMAN)
	if resp == null:
		return
	assert_true(resp.accepted, "合法 DISCARD 必须 accepted")
	assert_eq(resp.error_code, &"", "空 StringName")
	_assert_battle_events_only(resp.events, "ActionResolution.events")
	assert_eq(_count_type(resp.events, "ACTION_APPLIED"), 1)
	assert_gt(resp.events.size(), 0)
	if not resp.events.is_empty():
		assert_eq((resp.events[0] as BattleEvent).type, &"ACTION_APPLIED",
			"accepted DISCARD 的事件段必须以 ACTION_APPLIED 开始")
	_assert_battle_events_only(bc.get("events") as Array, "controller.events")
	assert_eq(_count_type((bc.get("events") as Array).slice(before_n), "ACTION_APPLIED"), 1)
