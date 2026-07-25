class_name ActionResolution extends RefCounted

const INVALID_ACTION: StringName = &"INVALID_ACTION"
const WRONG_HAND: StringName = &"WRONG_HAND"
const WRONG_DECISION: StringName = &"WRONG_DECISION"
const WRONG_SEAT: StringName = &"WRONG_SEAT"
const WRONG_PHASE: StringName = &"WRONG_PHASE"
const WRONG_ROOM: StringName = &"WRONG_ROOM"
const NOT_OFFERED: StringName = &"NOT_OFFERED"
const ALREADY_RESPONDED: StringName = &"ALREADY_RESPONDED"
const ENTITY_NOT_FOUND: StringName = &"ENTITY_NOT_FOUND"
const RULE_REJECTED: StringName = &"RULE_REJECTED"
const NOT_ENABLED: StringName = &"NOT_ENABLED"
## E2-04：game_mode 硬隔离拒绝（与 E5 未实现的 NOT_ENABLED 可区分）
const MODE_FORBIDDEN: StringName = &"MODE_FORBIDDEN"
const REPLAY_MISMATCH: StringName = &"REPLAY_MISMATCH"

var _accepted: bool = false
var _error_code: StringName = &""
var _events: Array = []

var accepted: bool:
	get:
		return _accepted

var error_code: StringName:
	get:
		return _error_code

var events: Array:
	get:
		return _clone_events(_events)


static func success(raw_events: Variant) -> ActionResolution:
	if typeof(raw_events) != TYPE_ARRAY:
		return null
	var cloned: Variant = _clone_events(raw_events)
	if cloned == null:
		return null
	var result := ActionResolution.new()
	result._accepted = true
	result._error_code = &""
	result._events = cloned as Array
	return result


static func rejected(raw_code: Variant) -> ActionResolution:
	if typeof(raw_code) != TYPE_STRING_NAME:
		return null
	match raw_code:
		INVALID_ACTION, WRONG_HAND, WRONG_DECISION, WRONG_SEAT, WRONG_PHASE, WRONG_ROOM, NOT_OFFERED, ALREADY_RESPONDED, ENTITY_NOT_FOUND, RULE_REJECTED, NOT_ENABLED, MODE_FORBIDDEN, REPLAY_MISMATCH:
			pass
		_:
			return null
	var result := ActionResolution.new()
	result._accepted = false
	result._error_code = raw_code
	result._events = []
	return result


func to_dict() -> Dictionary:
	var event_dicts: Array = []
	for ev in _events:
		event_dicts.append(ev.to_dict())
	return {
		"accepted": _accepted,
		"error_code": _error_code,
		"events": event_dicts,
	}


static func _clone_events(raw_events: Array) -> Variant:
	var out: Array = []
	for item in raw_events:
		if not (item is BattleEvent):
			return null
		var snap: Variant = BattleEvent.from_dict(item.to_dict())
		if snap == null or not (snap is BattleEvent):
			return null
		out.append(snap)
	return out
