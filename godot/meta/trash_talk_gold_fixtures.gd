class_name TrashTalkGoldFixtures extends RefCounted

# E5-01 / #249 + E5-03 / #251：黄金数值 fixture（全零 + 有文本）。
# expected.matrix_components 必须与 scorer 每 cell 冻结字段字节级一致：
# seat, item_id, persona, item_tag, public_context, expression, total_score, matched_rule_ids


static func all() -> Array:
	return [gold_zero(), gold_text()]


static func gold_zero() -> Dictionary:
	var seats := [0, 1, 2, 3]
	# 字典序冻结奖池（与评分器 _normalize_pool_item_ids 一致）
	var items := [
		"dora_charm_v1",
		"double_payout_v1",
		"iron_shield_v1",
		"wall_peek_v1",
	]
	var matrix: Array = []
	var matched := {}
	for seat in seats:
		matched[str(seat)] = []
		for item_id in items:
			matrix.append({
				"seat": seat,
				"item_id": item_id,
				"persona": 0,
				"item_tag": 0,
				"public_context": 0,
				"expression": 0,
				"total_score": 0,
				"matched_rule_ids": [],
			})
	return {
		"fixture_id": "gold_zero_v1",
		"rule_version": TrashTalkRuleCatalog.rule_version(),
		"window_id": "hand_0_window_0",
		"hand_seq": 0,
		"character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"language": "zh",
		"texts_by_seat": {"0": "", "1": "", "2": "", "3": ""},
		"public_context_tags_active": [],
		"pool_item_ids": items,
		"expected": {
			"matrix_components": matrix,
			"matched_rule_ids_by_seat": matched,
		},
	}


static func gold_text() -> Dictionary:
	# seat1=裘绝 AI 模板整句；CTX_RIICHI_OPEN；奖池字典序
	# persona: keyword 220 + template 100 = 320
	# expression: 180
	# public_context: riichi 120（仅有文本活动席）
	# item_tag: double_payout 150（secondary DOMINATION）+ relic_lucky_cat 130（primary PASSION）
	var items := [
		"double_payout_v1",
		"iron_shield_v1",
		"relic_lucky_cat_v1",
		"wall_peek_v1",
	]
	var seat1_base := [
		"r_ctx_riichi_open_01",
		"r_expr_generic_zh_01",
		"r_persona_qiu_jue_kw_zh_01",
		"r_persona_qiu_jue_tpl_zh_01",
	]
	var seat1_all := [
		"r_ctx_riichi_open_01",
		"r_expr_generic_zh_01",
		"r_item_double_payout_tag_01",
		"r_item_relic_lucky_cat_tag_01",
		"r_persona_qiu_jue_kw_zh_01",
		"r_persona_qiu_jue_tpl_zh_01",
	]
	var matrix: Array = []
	var matched := {
		"0": [],
		"1": seat1_all.duplicate(),
		"2": [],
		"3": [],
	}
	for seat in [0, 1, 2, 3]:
		for item_id in items:
			var persona := 0
			var item_tag := 0
			var public_context := 0
			var expression := 0
			var cell_rules: Array = []
			if seat == 1:
				persona = 320
				expression = 180
				public_context = 120
				cell_rules = seat1_base.duplicate()
				if item_id == "double_payout_v1":
					item_tag = 150
					cell_rules.append("r_item_double_payout_tag_01")
				elif item_id == "relic_lucky_cat_v1":
					item_tag = 130
					cell_rules.append("r_item_relic_lucky_cat_tag_01")
				cell_rules.sort()
			var total: int = persona + item_tag + public_context + expression
			matrix.append({
				"seat": seat,
				"item_id": item_id,
				"persona": persona,
				"item_tag": item_tag,
				"public_context": public_context,
				"expression": expression,
				"total_score": total,
				"matched_rule_ids": cell_rules,
			})
	return {
		"fixture_id": "gold_text_v1",
		"rule_version": TrashTalkRuleCatalog.rule_version(),
		"window_id": "hand_1_window_0",
		"hand_seq": 1,
		"character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"language": "zh",
		"texts_by_seat": {
			"0": "",
			"1": "燃烧起来！这局我必胜翻盘！",
			"2": "",
			"3": "",
		},
		"public_context_tags_active": ["CTX_RIICHI_OPEN"],
		"pool_item_ids": items,
		"expected": {
			"matrix_components": matrix,
			"matched_rule_ids_by_seat": matched,
		},
	}


## 稳定摘要：FNV-1a 32-bit 十六进制（小写 8 位），对 stable_stringify 结果计算。
static func stable_digest(value: Variant) -> String:
	return _fnv1a32_hex(stable_stringify(value))


## 键排序 + 字符串转义的确定序列化（无歧义）。
static func stable_stringify(value: Variant) -> String:
	return _stable(value)


static func _stable(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var d: Dictionary = value
			var keys: Array = d.keys()
			keys.sort_custom(func(a, b): return str(a) < str(b))
			var parts: PackedStringArray = PackedStringArray()
			for k in keys:
				# key 同样加引号并转义，避免 key 含冒号/逗号/引号时产生歧义
				parts.append("\"%s\":%s" % [_escape_string(str(k)), _stable(d[k])])
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var parts2: PackedStringArray = PackedStringArray()
			for item in value:
				parts2.append(_stable(item))
			return "[" + ",".join(parts2) + "]"
		TYPE_STRING:
			return "\"%s\"" % _escape_string(String(value))
		TYPE_STRING_NAME:
			return "\"%s\"" % _escape_string(String(value))
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			# 禁止依赖浮点；fixture 应仅用 int
			return "f:%s" % str(value)
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_NIL:
			return "null"
		_:
			return "\"%s\"" % _escape_string(str(value))


static func _escape_string(s: String) -> String:
	var out := ""
	for i in range(s.length()):
		var ch := s[i]
		var code := s.unicode_at(i)
		match ch:
			"\\":
				out += "\\\\"
			"\"":
				out += "\\\""
			"\n":
				out += "\\n"
			"\r":
				out += "\\r"
			"\t":
				out += "\\t"
			_:
				if code < 0x20:
					out += "\\u%04x" % code
				else:
					out += ch
	return out


static func _fnv1a32_hex(text: String) -> String:
	var h: int = 2166136261
	for i in range(text.length()):
		h = int((h ^ text.unicode_at(i)) * 16777619) & 0xffffffff
	return "%08x" % h
