class_name DecisionWindow
extends RefCounted
## 一局决策窗：按座位挂 DecisionContext，登记各座位 intent；to_dict 不泄露私有 offer。

const KIND_TURN := "TURN"
const KIND_CLAIM := "CLAIM"
const KIND_ROB_KAN := "ROB_KAN"

var _kind: String = ""
var kind: String:
	get:
		return _kind

var _hand_seq: int = 0
var hand_seq: int:
	get:
		return _hand_seq

var _decision_id: String = ""
var decision_id: String:
	get:
		return _decision_id

var _subject_seat: int = -1
var subject_seat: int:
	get:
		return _subject_seat

var _subject_tile_instance_id: int = -1
var subject_tile_instance_id: int:
	get:
		return _subject_tile_instance_id

var _discarder_seat: int = -1
var discarder_seat: int:
	get:
		return _discarder_seat

var _contexts_by_seat: Dictionary = {}
var _intents_by_seat: Dictionary = {}


static func make(
	p_kind: String,
	p_hand_seq: int,
	p_decision_id: String,
	p_subject_seat: int = -1,
	p_subject_tile_instance_id: int = -1,
	p_discarder_seat: int = -1
) -> DecisionWindow:
	if p_kind != KIND_TURN and p_kind != KIND_CLAIM and p_kind != KIND_ROB_KAN:
		return null
	if typeof(p_hand_seq) != TYPE_INT:
		return null
	if p_hand_seq < 0 or p_hand_seq > ProtocolConstants.MAX_HAND_SEQ:
		return null
	if not ProtocolUuid.is_canonical_v4(p_decision_id):
		return null
	if typeof(p_subject_seat) != TYPE_INT or p_subject_seat < 0 or p_subject_seat > 3:
		return null
	if not _validate_subject_discarder(
		p_kind, p_subject_seat, p_subject_tile_instance_id, p_discarder_seat, p_hand_seq
	):
		return null

	var win := DecisionWindow.new()
	win._kind = p_kind
	win._hand_seq = p_hand_seq
	win._decision_id = p_decision_id
	win._subject_seat = p_subject_seat
	win._subject_tile_instance_id = p_subject_tile_instance_id
	win._discarder_seat = p_discarder_seat
	win._contexts_by_seat = {}
	win._intents_by_seat = {}
	return win


static func _validate_subject_discarder(
	p_kind: String, subject: int, tile_iid: int, discarder: int, p_hand_seq: int
) -> bool:
	if p_kind == KIND_TURN:
		if discarder != -1:
			return false
		# TURN subject 可为 INVALID -1；否则必须本局命名空间
		if tile_iid == Tile.INVALID_INSTANCE_ID:
			return true
		return Tile.is_instance_id_in_hand_seq(tile_iid, p_hand_seq)
	# CLAIM / ROB_KAN：subject == discarder，tile 必须本局命名空间（不可 -1）
	if discarder != subject:
		return false
	if discarder < 0 or discarder > 3:
		return false
	return Tile.is_instance_id_in_hand_seq(tile_iid, p_hand_seq)


func add_context(ctx: DecisionContext) -> bool:
	if ctx == null:
		return false
	if ctx.window_kind != _kind:
		return false
	if ctx.hand_seq != _hand_seq:
		return false
	if ctx.decision_id != _decision_id:
		return false
	if ctx.seat < 0 or ctx.seat > 3:
		return false
	if _contexts_by_seat.has(ctx.seat):
		return false
	if _kind == KIND_TURN:
		if ctx.seat != _subject_seat:
			return false
		if not _contexts_by_seat.is_empty():
			return false
		if ctx.claimed_tile_instance_id != -1 or ctx.discarder_seat != -1:
			return false
	else:
		# CLAIM / ROB_KAN：不可挂 subject（= discarder）；claimed/discarder 须对齐
		if ctx.seat == _subject_seat:
			return false
		if ctx.claimed_tile_instance_id != _subject_tile_instance_id:
			return false
		if ctx.discarder_seat != _discarder_seat:
			return false
	# ctx 已由 DecisionContext.make 严格校验；这里只做隔离深拷贝，避免重复解析 offers。
	var cloned: DecisionContext = ctx._clone_validated()
	if cloned == null:
		return false
	_contexts_by_seat[ctx.seat] = cloned
	return true


func context_for_seat(seat: int) -> DecisionContext:
	if not _contexts_by_seat.has(seat):
		return null
	var stored: DecisionContext = _contexts_by_seat[seat] as DecisionContext
	if stored == null:
		return null
	return stored._clone_validated()


## 仅供权威 BattleController 同步调用链内部读取；不得越过 controller 边界返回。
## DecisionContext 没有公开 mutator，内部复用可避免同一 action 重复深拷贝 offer。
func _context_ref_for_seat(seat: int) -> DecisionContext:
	if not _contexts_by_seat.has(seat):
		return null
	return _contexts_by_seat[seat] as DecisionContext


func seats() -> Array:
	var result: Array = _contexts_by_seat.keys()
	result.sort()
	return result


func register_intent(action: Action) -> bool:
	if action == null:
		return false
	if action.hand_seq != _hand_seq:
		return false
	if action.decision_id != _decision_id:
		return false
	var seat: int = action.seat
	if not _contexts_by_seat.has(seat):
		return false
	if _intents_by_seat.has(seat):
		return false
	var ctx: DecisionContext = _contexts_by_seat[seat] as DecisionContext
	if ctx == null:
		return false
	var payload: Dictionary = action.payload
	if not ctx.allows(action.kind, payload):
		return false
	var stored: Action = Action.from_dict(action.to_dict())
	if stored == null:
		return false
	_intents_by_seat[seat] = stored
	return true


func intent_for_seat(seat: int) -> Action:
	if not _intents_by_seat.has(seat):
		return null
	var stored: Action = _intents_by_seat[seat] as Action
	if stored == null:
		return null
	return Action.from_dict(stored.to_dict())


func has_responded(seat: int) -> bool:
	return _intents_by_seat.has(seat)


## 仅供 BattleController 在最后一个 intent 的领域事务失败时精确回滚。
func _rollback_intent(seat: int) -> bool:
	return _intents_by_seat.erase(seat)


func is_complete() -> bool:
	if _contexts_by_seat.is_empty():
		return false
	for seat in _contexts_by_seat.keys():
		if not _intents_by_seat.has(seat):
			return false
	return true


func intents() -> Array:
	var seat_list: Array = _intents_by_seat.keys()
	seat_list.sort()
	var result: Array = []
	for seat in seat_list:
		var stored: Action = _intents_by_seat[seat] as Action
		if stored == null:
			continue
		result.append(Action.from_dict(stored.to_dict()))
	return result


func to_dict() -> Dictionary:
	var responded: Array = _intents_by_seat.keys()
	responded.sort()
	return {
		"kind": _kind,
		"hand_seq": _hand_seq,
		"decision_id": _decision_id,
		"subject_seat": _subject_seat,
		"subject_tile_instance_id": _subject_tile_instance_id,
		"discarder_seat": _discarder_seat,
		"seats": seats(),
		"responded_seats": responded.duplicate(),
	}


## 深拷贝：复制标量、contexts 与已登记 intents；对外仍只读（读写仍走 add/register/for_seat）。
func deep_copy() -> DecisionWindow:
	var win := DecisionWindow.new()
	win._kind = _kind
	win._hand_seq = _hand_seq
	win._decision_id = _decision_id
	win._subject_seat = _subject_seat
	win._subject_tile_instance_id = _subject_tile_instance_id
	win._discarder_seat = _discarder_seat
	win._contexts_by_seat = {}
	win._intents_by_seat = {}
	for seat in _contexts_by_seat.keys():
		var stored_ctx: DecisionContext = _contexts_by_seat[seat] as DecisionContext
		if stored_ctx == null:
			continue
		var cloned_ctx: DecisionContext = stored_ctx._clone_validated()
		if cloned_ctx != null:
			win._contexts_by_seat[seat] = cloned_ctx
	for seat in _intents_by_seat.keys():
		var stored_act: Action = _intents_by_seat[seat] as Action
		if stored_act == null:
			continue
		var cloned_act: Action = Action.from_dict(stored_act.to_dict())
		if cloned_act != null:
			win._intents_by_seat[seat] = cloned_act
	return win
