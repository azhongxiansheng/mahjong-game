extends GutTest
## E2-02 Red：decision_id 确定性（canonical lowercase UUID v4+variant）
## 动态 load BC；唯一投影 decision_context_for_seat；唯一行动 apply_action。
## 无 fallback / has_method / 源码扫描 / 旧 API。

const ROOM := "room_determinism"
const SEED := 4242
const HAND_SEQ := 7
const BC_SCRIPT := "res://battle/battle_controller.gd"
const ENVELOPE_KEYS := [
	"protocol_version", "command_id", "room_id", "seat", "hand_seq",
	"decision_id", "kind", "payload", "client_seq",
]
## RFC4122 v4 + variant 10xx，仅 lowercase hex
const UUID_V4_RE := \
	"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"


func _is_uuid_v4(s: String) -> bool:
	if s.length() != 36 or s != s.to_lower():
		return false
	var re := RegEx.new()
	return re.compile(UUID_V4_RE) == OK and re.search(s) != null


func _cmd_uuid(n: int) -> String:
	return "550e8400-e29b-41d4-a716-%012d" % n


## 动态 load；失败 BATTLE_RED 后 return null（Parse Red 隔离）。
func _make_bc(p_seed: int, hand_seq: int) -> Object:
	var script: GDScript = load(BC_SCRIPT) as GDScript
	assert_true(
		script != null and script.can_instantiate(),
		"BATTLE_RED: BattleController 不可实例化（%s）" % BC_SCRIPT
	)
	if script == null or not script.can_instantiate():
		return null
	return script.new(p_seed, 0, false, TileId.E, hand_seq)


## 唯一投影 → typed DecisionContext；缺失/错型 BATTLE_RED 后 null。
func _ctx(bc: Object, seat: int) -> DecisionContext:
	var raw: Variant = bc.call("decision_context_for_seat", seat)
	assert_true(
		raw is DecisionContext,
		"BATTLE_RED: decision_context_for_seat 必须返回 DecisionContext，got=%s" % type_string(typeof(raw))
	)
	if not (raw is DecisionContext):
		return null
	return raw as DecisionContext


func _apply(bc: Object, action: Action) -> Variant:
	return bc.call("apply_action", action, ActionSource.HUMAN)


## 权威座位：BattleState.current_seat（非 TurnEngine）。
func _current_seat(bc: Object) -> int:
	var state: BattleState = bc.get("state") as BattleState
	assert_not_null(state, "BATTLE_RED: BattleState 不得 null")
	if state == null:
		return -1
	return state.current_seat


## DRAW → 真实摸牌 → DISCARD，再取 typed TURN Context。
func _enter_turn(bc: Object) -> DecisionContext:
	var state: BattleState = bc.get("state") as BattleState
	assert_not_null(state, "BATTLE_RED: BattleState 不得 null")
	if state == null:
		return null
	assert_eq(state.phase, BattlePhase.Kind.DRAW, "进回合前 phase 须为 DRAW")
	var engine: TurnEngine = bc.get("engine") as TurnEngine
	assert_not_null(engine, "BATTLE_RED: TurnEngine 不得 null")
	if engine == null:
		return null
	var drawn: Tile = engine.draw_for_current()
	assert_not_null(drawn, "draw_for_current 必须返回真实 Tile")
	if drawn == null:
		return null
	assert_eq(state.phase, BattlePhase.Kind.DISCARD, "摸牌后 phase 须为 DISCARD")
	return _ctx(bc, state.current_seat)


func _assert_uuid(id: String, label: String) -> void:
	assert_true(
		_is_uuid_v4(id),
		"%s decision_id 必须 canonical lowercase UUID v4+variant: %s" % [label, id]
	)


func _assert_claim_ctx(ctx: DecisionContext, seat: int, label: String) -> void:
	assert_not_null(ctx, "%s CLAIM ctx 不得 null" % label)
	if ctx == null:
		return
	assert_eq(ctx.window_kind, "CLAIM", "%s window_kind 须 CLAIM" % label)
	assert_eq(ctx.seat, seat, "%s seat 须为投影目标座位" % label)
	assert_eq(ctx.hand_seq, HAND_SEQ, "%s hand_seq 须为 HAND_SEQ" % label)


## exact 九键 Action.from_dict；payload 仅 tile_instance_id
func _discard_action(
	command_id: String,
	decision_id: String,
	hand_seq: int,
	seat: int,
	tile_instance_id: int,
	client_seq: int = 1
) -> Action:
	var wire := {
		"protocol_version": 1,
		"command_id": command_id,
		"room_id": ROOM,
		"seat": seat,
		"hand_seq": hand_seq,
		"decision_id": decision_id,
		"kind": "DISCARD",
		"payload": {"tile_instance_id": tile_instance_id},
		"client_seq": client_seq,
	}
	assert_eq(wire.keys().size(), ENVELOPE_KEYS.size(), "Action wire exact 九键")
	for k in ENVELOPE_KEYS:
		assert_true(wire.has(k), "缺 envelope 键: %s" % k)
	var action: Action = Action.from_dict(wire)
	assert_not_null(action, "Action.from_dict 必须非 null（exact 九键 + 合法 UUID）")
	return action


## 先 type guard assert+return，再 cast/size（坏生产输出不得炸测试 runtime）。
func _first_discard_iid(ctx: DecisionContext) -> int:
	assert_not_null(ctx, "ctx 不得 null")
	if ctx == null:
		return -1
	for offer in ctx.allowed_actions:
		assert_eq(typeof(offer), TYPE_DICTIONARY, "offer 必须是 Dictionary")
		if typeof(offer) != TYPE_DICTIONARY:
			return -1
		var d: Dictionary = offer
		assert_eq(d.keys().size(), 2, "offer exact 两键 {kind, payload_options}")
		assert_true(d.has("kind") and d.has("payload_options"))
		if d.keys().size() != 2 or not d.has("kind") or not d.has("payload_options"):
			return -1
		if str(d["kind"]) != "DISCARD":
			continue
		var opts_raw: Variant = d["payload_options"]
		assert_eq(typeof(opts_raw), TYPE_ARRAY, "payload_options 必须是 Array")
		if typeof(opts_raw) != TYPE_ARRAY:
			return -1
		var opts: Array = opts_raw
		assert_gt(opts.size(), 0, "DISCARD payload_options 不得空")
		if opts.is_empty():
			return -1
		var first_raw: Variant = opts[0]
		assert_eq(typeof(first_raw), TYPE_DICTIONARY, "option 必须是 Dictionary")
		if typeof(first_raw) != TYPE_DICTIONARY:
			return -1
		var fd: Dictionary = first_raw
		assert_true(fd.has("tile_instance_id"), "DISCARD option 必须含 tile_instance_id")
		if not fd.has("tile_instance_id"):
			return -1
		return int(fd["tile_instance_id"])
	assert_true(false, "必须有 DISCARD offer")
	return -1


func test_same_seed_hand_seq_turn_decision_id_identical() -> void:
	var bc_a: Object = _make_bc(SEED, HAND_SEQ)
	if bc_a == null:
		return
	var bc_b: Object = _make_bc(SEED, HAND_SEQ)
	if bc_b == null:
		return
	var ctx_a: DecisionContext = _enter_turn(bc_a)
	var ctx_b: DecisionContext = _enter_turn(bc_b)
	assert_not_null(ctx_a, "decision_context_for_seat 不得 null")
	assert_not_null(ctx_b, "decision_context_for_seat 不得 null")
	if ctx_a == null or ctx_b == null:
		return
	_assert_uuid(ctx_a.decision_id, "bc_a TURN")
	_assert_uuid(ctx_b.decision_id, "bc_b TURN")
	assert_eq(ctx_a.decision_id, ctx_b.decision_id, "同 seed+hand_seq 同一步骤 TURN decision_id 必须相同")


func test_reproject_same_window_same_id_different_context_ref() -> void:
	var bc: Object = _make_bc(SEED, HAND_SEQ)
	if bc == null:
		return
	var ctx1: DecisionContext = _enter_turn(bc)
	assert_not_null(ctx1, "enter_turn context 不得 null")
	if ctx1 == null:
		return
	var seat := _current_seat(bc)
	if seat < 0:
		return
	var ctx2: DecisionContext = _ctx(bc, seat)
	assert_not_null(ctx2, "重复投影不得 null")
	if ctx2 == null:
		return
	assert_eq(ctx2.decision_id, ctx1.decision_id, "同一 window 重复投影 decision_id 必须相同")
	assert_false(is_same(ctx1, ctx2), "重复投影必须返回不同 Context 引用")
	var offers1: Array = ctx1.allowed_actions
	var snap_size: int = offers1.size()
	offers1.append({"kind": "FORGED", "payload_options": [{}]})
	var offers2: Array = ctx2.allowed_actions
	assert_eq(offers2.size(), snap_size, "深拷贝：污染一侧不得改另一侧 offers 长度")
	for o in offers2:
		assert_ne(str((o as Dictionary).get("kind", "")), "FORGED", "不得交叉泄露 FORGED")


func test_discard_then_claim_ids_match_across_controllers() -> void:
	var bc_a: Object = _make_bc(SEED, HAND_SEQ)
	if bc_a == null:
		return
	var bc_b: Object = _make_bc(SEED, HAND_SEQ)
	if bc_b == null:
		return
	var ctx_a: DecisionContext = _enter_turn(bc_a)
	var ctx_b: DecisionContext = _enter_turn(bc_b)
	assert_not_null(ctx_a)
	assert_not_null(ctx_b)
	if ctx_a == null or ctx_b == null:
		return

	var turn_id := ctx_a.decision_id
	assert_eq(turn_id, ctx_b.decision_id, "DISCARD 前 TURN id 应一致")
	_assert_uuid(turn_id, "TURN")

	var tile_a := _first_discard_iid(ctx_a)
	var tile_b := _first_discard_iid(ctx_b)
	assert_ne(tile_a, -1, "ctx_a 必须有 DISCARD offer")
	assert_ne(tile_b, -1, "ctx_b 必须有 DISCARD offer")
	assert_eq(tile_a, tile_b, "同 seed 首张可弃实体 id 应一致")

	var seat_a := _current_seat(bc_a)
	var seat_b := _current_seat(bc_b)
	if seat_a < 0 or seat_b < 0:
		return
	var action_a := _discard_action(_cmd_uuid(1), turn_id, HAND_SEQ, seat_a, tile_a, 1)
	var action_b := _discard_action(_cmd_uuid(2), turn_id, HAND_SEQ, seat_b, tile_b, 1)
	if action_a == null or action_b == null:
		return

	var res_a = _apply(bc_a, action_a)
	var res_b = _apply(bc_b, action_b)
	assert_true(res_a is ActionResolution, "apply_action 必须返回 ActionResolution")
	assert_true(res_b is ActionResolution, "apply_action 必须返回 ActionResolution")
	if not (res_a is ActionResolution) or not (res_b is ActionResolution):
		return
	assert_true((res_a as ActionResolution).accepted, "bc_a 合法 DISCARD 须 accepted")
	assert_true((res_b as ActionResolution).accepted, "bc_b 合法 DISCARD 须 accepted")

	var subject := seat_a
	var claim_ids: Array = []
	var offers_by_seat: Dictionary = {}
	for s in range(4):
		if s == subject:
			continue
		var claim_a: DecisionContext = _ctx(bc_a, s)
		var claim_b: DecisionContext = _ctx(bc_b, s)
		_assert_claim_ctx(claim_a, s, "bc_a seat=%d" % s)
		_assert_claim_ctx(claim_b, s, "bc_b seat=%d" % s)
		if claim_a == null or claim_b == null:
			return
		_assert_uuid(claim_a.decision_id, "CLAIM seat=%d" % s)
		assert_eq(claim_a.decision_id, claim_b.decision_id, "两 controller 同 seat CLAIM id 必须相同")
		assert_ne(claim_a.decision_id, turn_id, "CLAIM decision_id 必须与 TURN 不同")
		claim_ids.append(claim_a.decision_id)
		offers_by_seat[s] = claim_a.allowed_actions

	assert_gt(claim_ids.size(), 0, "至少应有一个非 subject CLAIM seat")
	var shared_claim := str(claim_ids[0])
	for id in claim_ids:
		assert_eq(str(id), shared_claim, "同一 CLAIM window 各 seat 共用同一 window ID")

	var seats: Array = offers_by_seat.keys()
	assert_gt(seats.size(), 1, "CLAIM 至少两个非 subject seat")
	var s0 := int(seats[0])
	var s1 := int(seats[1])
	var poisoned: Array = offers_by_seat[s0]
	var size1_before: int = (offers_by_seat[s1] as Array).size()
	poisoned.append({"kind": "FORGED", "payload_options": [{}]})
	var again: DecisionContext = _ctx(bc_a, s1)
	_assert_claim_ctx(again, s1, "再投影 seat=%d" % s1)
	if again == null:
		return
	assert_eq(again.decision_id, shared_claim)
	var clean: Array = again.allowed_actions
	assert_eq(clean.size(), size1_before, "私有 offers 不得交叉泄露长度")
	for o in clean:
		assert_ne(str((o as Dictionary).get("kind", "")), "FORGED")


func test_different_hand_seq_yields_different_decision_id() -> void:
	var bc7: Object = _make_bc(SEED, 7)
	if bc7 == null:
		return
	var bc8: Object = _make_bc(SEED, 8)
	if bc8 == null:
		return
	var ctx7: DecisionContext = _enter_turn(bc7)
	var ctx8: DecisionContext = _enter_turn(bc8)
	assert_not_null(ctx7)
	assert_not_null(ctx8)
	if ctx7 == null or ctx8 == null:
		return
	_assert_uuid(ctx7.decision_id, "hand_seq=7")
	_assert_uuid(ctx8.decision_id, "hand_seq=8")
	assert_ne(ctx7.decision_id, ctx8.decision_id, "hand_seq 不同 decision_id 必须不同")
