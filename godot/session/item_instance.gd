class_name ItemInstance extends RefCounted

# E5-05 / #253：同场多实例库存条目（纯数据）。
# 身份以 item_instance_id 为准；同 item_id 可并存，不合并、不替换。

## held=库存可用；armed=延迟效果已注册待触发；consumed=已结算移除
const STATUS_HELD := "held"
const STATUS_ARMED := "armed"
const STATUS_CONSUMED := "consumed"

var item_instance_id: String = ""
var item_id: String = ""
var seat: int = -1
var window_id: String = ""
var hand_seq: int = 0
var score: int = 0
var affinity_match: bool = false
var armed_for_window_id = null # String | null
var status: String = STATUS_HELD
## 延迟武装时绑定的 command_id（触发后写 CONSUMED/APPLIED）
var arm_command_id: String = ""


func _init(
	p_instance_id: String = "",
	p_item_id: String = "",
	p_seat: int = -1,
	p_window_id: String = "",
	p_hand_seq: int = 0,
	p_score: int = 0,
	p_affinity_match: bool = false,
	p_armed_for = null
) -> void:
	item_instance_id = p_instance_id
	item_id = p_item_id
	seat = p_seat
	window_id = p_window_id
	hand_seq = p_hand_seq
	score = p_score
	affinity_match = p_affinity_match
	armed_for_window_id = p_armed_for
	status = STATUS_HELD
	arm_command_id = ""


func to_dict() -> Dictionary:
	return {
		"item_instance_id": item_instance_id,
		"item_id": item_id,
		"seat": seat,
		"window_id": window_id,
		"hand_seq": hand_seq,
		"score": score,
		"affinity_match": affinity_match,
		"armed_for_window_id": armed_for_window_id,
		"status": status,
		"arm_command_id": arm_command_id,
	}


static func from_dict(raw: Variant) -> ItemInstance:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = raw
	var iid := String(d.get("item_instance_id", "")).strip_edges()
	var raw_item_id := String(d.get("item_id", "")).strip_edges()
	if iid.is_empty() or raw_item_id.is_empty():
		return null
	if typeof(d.get("seat", null)) != TYPE_INT:
		return null
	var raw_seat: int = int(d["seat"])
	if raw_seat < 0 or raw_seat > 3:
		return null
	if typeof(d.get("hand_seq", null)) != TYPE_INT:
		return null
	if typeof(d.get("score", null)) != TYPE_INT:
		return null
	if typeof(d.get("affinity_match", null)) != TYPE_BOOL:
		return null
	var armed = d.get("armed_for_window_id", null)
	if armed != null:
		var as_s := String(armed).strip_edges()
		if as_s.is_empty():
			return null
		armed = as_s
	var inst := ItemInstance.new(
		iid, raw_item_id, raw_seat,
		String(d.get("window_id", "")),
		int(d["hand_seq"]), int(d["score"]),
		bool(d["affinity_match"]), armed
	)
	var st := String(d.get("status", STATUS_HELD))
	if st != STATUS_HELD and st != STATUS_ARMED and st != STATUS_CONSUMED:
		return null
	inst.status = st
	inst.arm_command_id = String(d.get("arm_command_id", ""))
	return inst


## 确定性、跨 match 全局唯一、可回放的实例 ID。
## p_match_ns：公开 session_id 或 room_id（不含 seed/隐藏信息）。
static func make_instance_id(
	p_match_ns: String, p_window_id: String, p_seat: int, p_item_id: String
) -> String:
	var ns := String(p_match_ns).strip_edges()
	if ns.is_empty():
		ns = "ns"
	# 规范化：空白→下划线，避免 payload 空白
	ns = ns.replace(" ", "_")
	return "ii_%s_%s_s%d_%s" % [ns, p_window_id, p_seat, p_item_id]
