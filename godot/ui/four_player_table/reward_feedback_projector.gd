extends RefCounted

# E4-04 / #246：最小奖励反馈投影（仅 display）。
# 无全局 class_name。只接受经 NetworkedEvent 校验的权威事件。
# 不调用 RewardWindowModule / inventory；不构造权威事件。

const MSG_FULL_GRANT := "分配完成，等待到账事件"
const MSG_DISPLAY_ONLY := "仅展示，未发放"
const MSG_CANCELLED_BY_WIN := "和牌优先，本窗作废"
const MSG_ITEM_GRANTED := "到账"


## 接受 NetworkedEvent 实例，或完整六键 wire Dictionary（经 from_dict 验证）。
func project(event: Variant) -> Dictionary:
	var ne: NetworkedEvent = _coerce_networked_event(event)
	if ne == null:
		return _reject("SCHEMA_REJECTED")
	var kind := String(ne.kind)
	var payload: Dictionary = ne.payload
	match kind:
		"REWARD_WINDOW_SETTLED":
			return _project_settled(payload)
		"REWARD_WINDOW_CANCELLED":
			return _project_cancelled(payload)
		"ITEM_GRANTED":
			return _project_item_granted(payload)
	return _reject("UNSUPPORTED_KIND")


static func _coerce_networked_event(event: Variant) -> NetworkedEvent:
	if event is NetworkedEvent:
		return event as NetworkedEvent
	if typeof(event) == TYPE_DICTIONARY:
		return NetworkedEvent.from_dict(event)
	return null


func _project_settled(payload: Dictionary) -> Dictionary:
	var outcome := String(payload.get("outcome", "")).strip_edges()
	match outcome:
		"FULL_GRANT":
			return {
				"ok": true,
				"message": MSG_FULL_GRANT,
				"feedback_kind": "SETTLED_FULL_GRANT",
			}
		"DISPLAY_ONLY":
			return {
				"ok": true,
				"message": MSG_DISPLAY_ONLY,
				"feedback_kind": "SETTLED_DISPLAY_ONLY",
			}
	return _reject("INVALID_OUTCOME")


func _project_cancelled(payload: Dictionary) -> Dictionary:
	var reason := String(payload.get("cancel_reason", "")).strip_edges()
	if reason != "CANCELLED_BY_WIN":
		return _reject("INVALID_CANCEL_REASON")
	return {
		"ok": true,
		"message": MSG_CANCELLED_BY_WIN,
		"feedback_kind": "CANCELLED_BY_WIN",
	}


func _project_item_granted(_payload: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"message": MSG_ITEM_GRANTED,
		"feedback_kind": "ITEM_GRANTED",
	}


static func _reject(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
