class_name ItemInventoryGoldFixtures extends RefCounted

# E5-05 / #253 Round 8：硬编码生产事件黄金 fixture。
# 完整 NBC 可回放流：res://meta/item_inventory_gold_stream.json（离线冻结生产字节）。
# 禁止运行时用被测发奖/序列化实现拼 expected。

const MATCH_NS := "session_gold_253"
const ROOM_ID := "session_gold_253"
const WINDOW_ID := "hand_0_window_0"
const WINDOW_NEXT := "hand_0_window_1"
const RULE_VERSION := "trash_talk_rules_v1"
const ASSIGNMENT_VERSION := "assign_v1"
const COMMAND_USE := "550e8400-e29b-41d4-a716-0000000000c1"
const PROTOCOL_VERSION := 1
const GOLD_STREAM_PATH := "res://meta/item_inventory_gold_stream.json"

# 与 item_inventory_gold_stream.json 内 seat0..3 四次 ITEM_GRANTED 字节一致
const GOLD_ASSIGNMENT := {
	"0": "wall_peek_v1",
	"1": "dora_charm_v1",
	"2": "iron_shield_v1",
	"3": "double_payout_v1",
}

const GOLD_INSTANCE_IDS := {
	"0": "ii_session_gold_253_hand_0_window_0_s0_wall_peek_v1",
	"1": "ii_session_gold_253_hand_0_window_0_s1_dora_charm_v1",
	"2": "ii_session_gold_253_hand_0_window_0_s2_iron_shield_v1",
	"3": "ii_session_gold_253_hand_0_window_0_s3_double_payout_v1",
}


static func all() -> Array:
	return [
		gold_instance_id_formula(),
		gold_grant_order_seats(),
		gold_dual_instance_ids(),
		gold_public_item_event_trace(),
	]


static func gold_instance_id_formula() -> Dictionary:
	return {
		"fixture_id": "item_gold_instance_id_v1",
		"match_namespace": MATCH_NS,
		"window_id": WINDOW_ID,
		"assignment": GOLD_ASSIGNMENT.duplicate(true),
		"expected_instance_ids": {
			"0": "ii_session_gold_253_hand_0_window_0_s0_wall_peek_v1",
			"1": "ii_session_gold_253_hand_0_window_0_s1_dora_charm_v1",
			"2": "ii_session_gold_253_hand_0_window_0_s2_iron_shield_v1",
			"3": "ii_session_gold_253_hand_0_window_0_s3_double_payout_v1",
		},
	}


static func gold_grant_order_seats() -> Dictionary:
	return {
		"fixture_id": "item_gold_grant_order_v1",
		"expected_seat_order": [0, 1, 2, 3],
		"expected_count": 4,
	}


static func gold_dual_instance_ids() -> Dictionary:
	return {
		"fixture_id": "item_gold_dual_instance_v1",
		"match_namespace": MATCH_NS,
		"window_a": "hand_0_window_0",
		"window_b": "hand_0_window_1",
		"seat": 0,
		"item_id": "iron_shield_v1",
		"expected_a": "ii_session_gold_253_hand_0_window_0_s0_iron_shield_v1",
		"expected_b": "ii_session_gold_253_hand_0_window_1_s0_iron_shield_v1",
	}


## 完整生产 journal（ROOM_SNAPSHOT + FULL_GRANT + USE/效果 + MATCH）。
## 自冻结 JSON 文件加载；失败返回 []。
## JSON 解析会把整数变成 float：加载时按 NetworkedEvent 契约强制回 int。
static func gold_public_networked_events() -> Array:
	if not FileAccess.file_exists(GOLD_STREAM_PATH):
		return []
	var f: FileAccess = FileAccess.open(GOLD_STREAM_PATH, FileAccess.READ)
	if f == null:
		return []
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_ARRAY:
		return []
	var out: Array = []
	for raw in parsed as Array:
		if typeof(raw) != TYPE_DICTIONARY:
			return []
		out.append(_coerce_event_ints(raw as Dictionary))
	return out


static func _coerce_event_ints(d: Dictionary) -> Dictionary:
	# JSON 全树整型 float → int（协议字段与 SNAP 嵌套均依赖 TYPE_INT）
	return _coerce_deep_numeric_ints(d) as Dictionary


static func _coerce_deep_numeric_ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = {}
			for k in (v as Dictionary).keys():
				d[k] = _coerce_deep_numeric_ints((v as Dictionary)[k])
			return d
		TYPE_ARRAY:
			var a: Array = []
			for item in v as Array:
				a.append(_coerce_deep_numeric_ints(item))
			return a
		TYPE_FLOAT:
			var f: float = float(v)
			if is_equal_approx(f, roundf(f)) and absf(f) <= 9007199254740991.0:
				return int(roundf(f))
			return v
		_:
			return v


static func gold_public_item_event_trace() -> Dictionary:
	var events: Array = gold_public_networked_events()
	return {
		"fixture_id": "item_gold_public_event_trace_v1",
		"room_id": ROOM_ID,
		"recipient_seat": 0,
		"events": events,
		"canonical_json": JSON.stringify(events),
	}


## 从完整流抽取 item/match 相关 kind 序列（供 schema 烟测）。
static func gold_item_related_kinds() -> Array:
	var out: Array = []
	for raw in gold_public_networked_events():
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var k := str((raw as Dictionary).get("kind", ""))
		if k.begins_with("ITEM_") or k == "MATCH_SETTLED" or k == "ROOM_SNAPSHOT":
			# 仅保留与道具契约强相关的片段标记；完整序在 stream 文件
			if k != "ROOM_SNAPSHOT":
				out.append(k)
	return out
