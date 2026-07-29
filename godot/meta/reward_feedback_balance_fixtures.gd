extends RefCounted

# E5-06 / #254 rework-6：自洽平衡黄金 case。
# FULL_GRANT 输入来自真实 LocalLoopbackServer 生产 journal 冻结流
# （res://meta/reward_feedback_full_grant_stream.json）；禁止手工伪造 view_hash/ROOM_SNAPSHOT。
# expected 全部硬编码；禁止被测 UI 生成 expected。
# all() 仅含「每局」基线；STT 失败为显示语义子夹具，见 gold_stt_silent_baseline()。

const FIXTURE_VERSION := "reward_feedback_balance_v6"
const RULE_VERSION := "trash_talk_rules_v1"
const SEED := 11
const HAND_SEQ := 0
const WINDOW_INDEX := 0
const MATCH_NS := "session_bal_254_r5"
const ROOM_ID := "session_bal_254_r5"
const WINDOW_ID := "hand_0_window_0"
const GOLD_STREAM_PATH := "res://meta/reward_feedback_full_grant_stream.json"
const GOLD_STREAM_SEAT2_PATH := "res://meta/reward_feedback_full_grant_stream_seat2.json"

# seed=11 hand=0 window=0 → 真实 LocalLoopback FULL_GRANT（探针 2026-07-25）
const FULL_GRANT_PRIZE_POOL := [
	"double_payout_v1",
	"relic_red_string_v1",
	"relic_wall_eye_v1",
	"relic_iron_will_v1",
]
const FULL_GRANT_ASSIGNMENT := {
	"0": "double_payout_v1",
	"1": "relic_iron_will_v1",
	"2": "relic_red_string_v1",
	"3": "relic_wall_eye_v1",
}
const FULL_GRANT_INSTANCE_IDS := {
	"0": "ii_session_bal_254_r5_hand_0_window_0_s0_double_payout_v1",
	"1": "ii_session_bal_254_r5_hand_0_window_0_s1_relic_iron_will_v1",
	"2": "ii_session_bal_254_r5_hand_0_window_0_s2_relic_red_string_v1",
	"3": "ii_session_bal_254_r5_hand_0_window_0_s3_relic_wall_eye_v1",
}
const FULL_GRANT_DISTRIBUTION := {
	"double_payout_v1": 1,
	"relic_iron_will_v1": 1,
	"relic_red_string_v1": 1,
	"relic_wall_eye_v1": 1,
}

const CASE_FULL_GRANT := {
	"fixture_id": "bal_full_grant_real_loopback_v5",
	"seed": SEED,
	"hand_seq": HAND_SEQ,
	"window_index": WINDOW_INDEX,
	"rule_version": RULE_VERSION,
	"match_namespace": MATCH_NS,
	"room_id": ROOM_ID,
	"window_id": WINDOW_ID,
	"prize_pool": FULL_GRANT_PRIZE_POOL,
	"assignment": FULL_GRANT_ASSIGNMENT,
	"instance_ids": FULL_GRANT_INSTANCE_IDS,
	"outcome": "FULL_GRANT",
	"grant_count": 4,
	"inventory_total_after_grants": 4,
	"same_id_max_count": 1,
	"item_distribution": FULL_GRANT_DISTRIBUTION,
	"affinity_activation_numerator": 0,
	"affinity_activation_denominator": 4,
	"expected_settled_message": "分配完成，等待到账事件",
	"expected_arrival_message": "到账",
}

const CASE_DISPLAY_ONLY := {
	"fixture_id": "bal_display_only_rw_module_v5",
	"seed": SEED,
	"hand_seq": HAND_SEQ,
	"window_index": WINDOW_INDEX,
	"rule_version": RULE_VERSION,
	"outcome": "DISPLAY_ONLY",
	"grant_count": 0,
	"inventory_total": 0,
	"same_id_count": 0,
	"item_distribution": {},
	"show_assignment": true,
	"show_arrival": false,
	"expected_message": "仅本场统计，未发放",
	"scored": true,
	"affinity_activation_numerator": 0,
	"affinity_activation_denominator": 4,
}

const CASE_CANCELLED := {
	"fixture_id": "bal_cancelled_rw_module_v5",
	"seed": 7,
	"hand_seq": HAND_SEQ,
	"window_index": WINDOW_INDEX,
	"rule_version": RULE_VERSION,
	"outcome": "CANCELLED_BY_WIN",
	"grant_count": 0,
	"inventory_total": 0,
	"same_id_count": 0,
	"item_distribution": {},
	"show_scores": false,
	"show_assignment": false,
	"show_arrival": false,
	"scored": false,
	"expected_message": "和牌优先，本窗作废",
	"affinity_activation_numerator": 0,
	"affinity_activation_denominator": 4,
}

const CASE_MULTI := {
	"fixture_id": "bal_multi_instance_v5",
	"match_namespace": MATCH_NS,
	"seat": 0,
	"item_id": "wall_peek_v1",
	"window_a": "hand_0_window_0",
	"window_b": "hand_0_window_1",
	"expected_instance_ids": [
		"ii_session_bal_254_r5_hand_0_window_0_s0_wall_peek_v1",
		"ii_session_bal_254_r5_hand_0_window_1_s0_wall_peek_v1",
	],
	"inventory_total": 2,
	"same_id_count": 2,
	"item_distribution": {"wall_peek_v1": 2},
	"affinity_activation_numerator": 0,
	"affinity_activation_denominator": 2,
}

# 中英日/AI/静默驱动真实 DISPLAY_ONLY scorer 的每局基线（探针 2026-07-25 r6）
# affinity 激活率：3 席非零 / 4 席；grant/inventory 均为 0（DISPLAY_ONLY 不发库存）
const MULTILINGUAL_MATRIX_SCORES := [
	[640, 630, 490, 490],
	[630, 620, 480, 480],
	[630, 620, 480, 480],
	[0, 0, 0, 0],
]
const CASE_MULTILINGUAL := {
	"fixture_id": "bal_multilingual_hand_v6",
	"seed": SEED,
	"hand_seq": HAND_SEQ,
	"window_index": WINDOW_INDEX,
	"rule_version": RULE_VERSION,
	"room_id": "room_ml",
	"character_ids": ["qiu_jue", "qiu_jue", "qiu_jue", "hua_ling"],
	"participants": ["HUMAN", "HUMAN", "AI", "HUMAN"],
	"outcome": "DISPLAY_ONLY",
	"grant_count": 0,
	"inventory_total": 0,
	"same_id_count": 0,
	"item_distribution": {},
	"affinity_activation_numerator": 3,
	"affinity_activation_denominator": 4,
	"prize_pool": FULL_GRANT_PRIZE_POOL,
	"assignment": FULL_GRANT_ASSIGNMENT,
	"matrix_summary": {"scores": MULTILINGUAL_MATRIX_SCORES},
	"expected_message": "仅本场统计，未发放",
	"scored": true,
	"seats": {
		"0": {
			"language": "zh",
			"source": "server_stt",
			"character_id": "qiu_jue",
			"text": "燃烧起来！热血立直一发！",
			"role": "human_zh",
			"matched_rule_ids": ["r_expr_generic_zh_01", "r_persona_qiu_jue_kw_zh_01"],
			"affinity": {
				"DOMINATION": 0, "CALM": 0, "CUNNING": 0, "PASSION": 220, "MYSTIC": 0,
			},
		},
		"1": {
			"language": "en",
			"source": "server_stt",
			"character_id": "qiu_jue",
			"text": "Burn it up! This hand is my comeback!",
			"role": "human_en",
			"matched_rule_ids": [
				"r_expr_generic_en_01",
				"r_persona_qiu_jue_kw_en_01",
				"r_persona_qiu_jue_tpl_en_01",
			],
			"affinity": {
				"DOMINATION": 0, "CALM": 0, "CUNNING": 0, "PASSION": 300, "MYSTIC": 0,
			},
		},
		"2": {
			"language": "ja",
			"source": "ai_text",
			"character_id": "qiu_jue",
			"text": "燃えろ！この局で逆転必勝だ！",
			"role": "ai_ja",
			"matched_rule_ids": [
				"r_expr_generic_ja_01",
				"r_persona_qiu_jue_kw_ja_01",
				"r_persona_qiu_jue_tpl_ja_01",
			],
			"affinity": {
				"DOMINATION": 0, "CALM": 0, "CUNNING": 0, "PASSION": 300, "MYSTIC": 0,
			},
		},
		"3": {
			"language": "zh",
			"source": "silent",
			"character_id": "hua_ling",
			"text": "",
			"role": "silent",
			"matched_rule_ids": [],
			"affinity": {
				"DOMINATION": 0, "CALM": 0, "CUNNING": 0, "PASSION": 0, "MYSTIC": 0,
			},
		},
	},
}

# 显示语义子夹具：不进 all() 每局基线列表
const CASE_STT := {
	"fixture_id": "bal_stt_display_subfixture_v6",
	"kind": "display_subfixture",
	"stt_failed_text": "转写失败或超时 · 未计分",
	"stt_failed_is_reward": false,
}


static func fixture_version() -> String:
	return FIXTURE_VERSION


static func gold_digest() -> String:
	return "rfb_v6_real_loopback_ml_hand"


## 仅「每局」平衡基线（FULL_GRANT / DISPLAY_ONLY / CANCELLED / multi / 多语局）。
## STT 失败不在此列，见 gold_stt_silent_baseline()。
static func all() -> Array:
	return [
		gold_full_grant_baseline(),
		gold_display_only_baseline(),
		gold_cancelled_baseline(),
		gold_multi_instance_baseline(),
		gold_multilingual_inputs(),
	]


static func gold_full_grant_baseline() -> Dictionary:
	return CASE_FULL_GRANT.duplicate(true)


static func gold_display_only_baseline() -> Dictionary:
	return CASE_DISPLAY_ONLY.duplicate(true)


static func gold_cancelled_baseline() -> Dictionary:
	return CASE_CANCELLED.duplicate(true)


static func gold_multi_instance_baseline() -> Dictionary:
	return CASE_MULTI.duplicate(true)


static func gold_multilingual_inputs() -> Dictionary:
	return CASE_MULTILINGUAL.duplicate(true)


static func gold_stt_silent_baseline() -> Dictionary:
	return CASE_STT.duplicate(true)


## 真实 LocalLoopback 生产 journal（含完整 ROOM_SNAPSHOT / view_hash）。
## JSON 解析会把整数变成 float：加载时按 NetworkedEvent 契约强制回 int。
static func self_consistent_full_grant_events() -> Array:
	return _load_stream(GOLD_STREAM_PATH)


static func self_consistent_full_grant_events_seat2() -> Array:
	return _load_stream(GOLD_STREAM_SEAT2_PATH)


## FULL_GRANT 本窗片段：首 OPEN → 4×ITEM_GRANTED → 匹配 SNAP；不含下一窗 OPEN。
## 用于到账/库存 UI 断言（下一 OPEN 会合法刷新奖池文案）。
static func self_consistent_full_grant_window_events() -> Array:
	return _slice_until_next_open(self_consistent_full_grant_events())


static func self_consistent_full_grant_window_events_seat2() -> Array:
	return _slice_until_next_open(self_consistent_full_grant_events_seat2())


static func _slice_until_next_open(events: Array) -> Array:
	var out: Array = []
	var open_n := 0
	var grant_n := 0
	for raw in events:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = raw
		var kind := String(d.get("kind", ""))
		if kind == "REWARD_WINDOW_OPENED":
			open_n += 1
			if open_n > 1:
				break
		out.append(d)
		if kind == "ITEM_GRANTED":
			grant_n += 1
	# 确保切片含完整 4 grant（否则返回空避免假绿）
	if grant_n < 4:
		return []
	return out


static func _load_stream(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
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
	# #374：与 item_inventory gold stream 同策略——注入 matching_meta 并重算 hash
	return ItemInventoryGoldFixtures._ensure_matching_meta_on_snapshots(out)


static func _coerce_event_ints(d: Dictionary) -> Dictionary:
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
			var fl: float = float(v)
			if is_equal_approx(fl, roundf(fl)) and absf(fl) <= 9007199254740991.0:
				return int(roundf(fl))
			return v
		_:
			return v


# 兼容旧符号
const GOLD_PRIZE_POOL := FULL_GRANT_PRIZE_POOL
const GOLD_STREAM_ASSIGNMENT := FULL_GRANT_ASSIGNMENT
