class_name TextAnalyzer

# E5-02 / #250：中英日确定性文本标准化与规则命中累计。
# 只产文本特征；不评分 4×4、不发奖、不读公开上下文。
#
# accumulate_window 输入契约（调用方须从 GameSessionConfig.rule_version 传入，不接 #252）：
#   rule_version: 必须 == TrashTalkRuleCatalog.rule_version()，否则整窗拒绝 {}
#   window_id, seat(0..3), character_id
#   language: 可选窗口默认 zh|en|ja
#   utterances: [{utterance_id, text, language?}]
# 语言优先级：utterance.language > window.language；解析后必须为 zh|en|ja，否则整窗拒绝。
# 同 utterance_id：相同 text+language 幂等；冲突（text/language 不同）整窗拒绝（与输入序无关）。

const KEYWORDS: Dictionary = {
	Momentum.Attribute.DOMINATION: ["必胜", "绝对", "王者", "统治", "碾压", "无敌", "最强"],
	Momentum.Attribute.CALM: ["计算", "分析", "概率", "冷静", "观察", "读牌", "安全"],
	Momentum.Attribute.CUNNING: ["陷阱", "诱饵", "骗", "装", "阴", "暗算", "计谋"],
	Momentum.Attribute.PASSION: ["燃烧", "热血", "立直", "一发", "勝負", "来吧", "全力"],
	Momentum.Attribute.MYSTIC: ["命运", "天意", "奇迹", "预言", "感应", "直觉", "冥冥"],
}

const AFFINITY_KEYS: Array[String] = [
	"DOMINATION", "CALM", "CUNNING", "PASSION", "MYSTIC",
]

const ALLOWED_LANGS: Array[String] = ["zh", "en", "ja"]

const _TEXT_KINDS: Array[String] = [
	"PERSONA_KEYWORD", "PERSONA_TEMPLATE", "EXPRESSION", "ITEM_TAG",
]

# 半角片假名 U+FF66..U+FF9D → 全角片假名
const _HW_KATA_BASE: Array[int] = [
	0x30F2, # ヲ FF66
	0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9, # ァィゥェォ
	0x30E3, 0x30E5, 0x30E7, # ャュョ
	0x30C3, # ッ
	0x30FC, # ー FF70
	0x30A2, 0x30A4, 0x30A6, 0x30A8, 0x30AA, # アイウエオ
	0x30AB, 0x30AD, 0x30AF, 0x30B1, 0x30B3, # カキクケコ
	0x30B5, 0x30B7, 0x30B9, 0x30BB, 0x30BD, # サシスセソ
	0x30BF, 0x30C1, 0x30C4, 0x30C6, 0x30C8, # タチツテト
	0x30CA, 0x30CB, 0x30CC, 0x30CD, 0x30CE, # ナニヌネノ
	0x30CF, 0x30D2, 0x30D5, 0x30D8, 0x30DB, # ハヒフヘホ
	0x30DE, 0x30DF, 0x30E0, 0x30E1, 0x30E2, # マミムメモ
	0x30E4, 0x30E6, 0x30E8, # ヤユヨ
	0x30E9, 0x30EA, 0x30EB, 0x30EC, 0x30ED, # ラリルレロ
	0x30EF, 0x30F3, # ワン
]

# 显式浊音：清音全角片假名 → 浊音
const _DAKUTEN_MAP: Dictionary = {
	0x30AB: 0x30AC, # カ→ガ
	0x30AD: 0x30AE, # キ→ギ
	0x30AF: 0x30B0, # ク→グ
	0x30B1: 0x30B2, # ケ→ゲ
	0x30B3: 0x30B4, # コ→ゴ
	0x30B5: 0x30B6, # サ→ザ
	0x30B7: 0x30B8, # シ→ジ
	0x30B9: 0x30BA, # ス→ズ
	0x30BB: 0x30BC, # セ→ゼ
	0x30BD: 0x30BE, # ソ→ゾ
	0x30BF: 0x30C0, # タ→ダ
	0x30C1: 0x30C2, # チ→ヂ
	0x30C4: 0x30C5, # ツ→ヅ
	0x30C6: 0x30C7, # テ→デ
	0x30C8: 0x30C9, # ト→ド
	0x30CF: 0x30D0, # ハ→バ
	0x30D2: 0x30D3, # ヒ→ビ
	0x30D5: 0x30D6, # フ→ブ
	0x30D8: 0x30D9, # ヘ→ベ
	0x30DB: 0x30DC, # ホ→ボ
	0x30A6: 0x30F4, # ウ→ヴ
}

# 显式半浊音：ハ行 → パ行
const _HANDAKUTEN_MAP: Dictionary = {
	0x30CF: 0x30D1, # ハ→パ
	0x30D2: 0x30D4, # ヒ→ピ
	0x30D5: 0x30D7, # フ→プ
	0x30D8: 0x30DA, # ヘ→ペ
	0x30DB: 0x30DD, # ホ→ポ
}


## 旧路径兼容：返回 {Momentum.Attribute: float 0..1}。新累计不得依赖此函数。
static func analyze(text: String) -> Dictionary:
	var result: Dictionary = {}
	for attr in KEYWORDS:
		result[attr] = 0.0
	if text.is_empty():
		return result
	var lower: String = text.to_lower()
	for attr in KEYWORDS:
		var keywords: Array = KEYWORDS[attr]
		var hits: int = 0
		for kw in keywords:
			if lower.contains(kw):
				hits += 1
		result[attr] = clampf(float(hits) / 3.0, 0.0, 1.0)
	return result


## 确定性规范化（匹配用）。顺序固定，禁止浮点/语义折叠。
static func normalize(text: String) -> String:
	if text.is_empty():
		return ""
	var chars: PackedStringArray = PackedStringArray()
	var i := 0
	var n := text.length()
	while i < n:
		var code: int = text.unicode_at(i)
		# N2: 全角 ASCII FF01-FF5E → 半角
		if code >= 0xFF01 and code <= 0xFF5E:
			code = code - 0xFEE0
		# N7: 半角片假名
		elif code >= 0xFF66 and code <= 0xFF9D:
			code = _HW_KATA_BASE[code - 0xFF66]
		# 半角浊点/半浊点：接到前一全角片假名上（显式映射表）
		elif code == 0xFF9E or code == 0xFF9F:
			if chars.size() > 0:
				var prev: String = chars[chars.size() - 1]
				var prev_code: int = prev.unicode_at(0)
				var combined: int = _apply_dakuten(prev_code, code == 0xFF9E)
				if combined > 0:
					chars[chars.size() - 1] = String.chr(combined)
					i += 1
					continue
			i += 1
			continue
		# N3: 全角空格与控制空白 → 空格
		elif code == 0x3000 or code == 0x09 or code == 0x0A or code == 0x0D \
				or code == 0x0B or code == 0x0C:
			code = 0x20
		# N6: 删除基础标点（含半角日文标点）
		if _is_basic_punct(code):
			i += 1
			continue
		# N5: Latin 小写
		if code >= 0x41 and code <= 0x5A:
			code = code + 0x20
		chars.append(String.chr(code))
		i += 1
	# N4: 压缩空白 + strip
	var out := ""
	var prev_space := false
	for ch in chars:
		if ch == " ":
			if prev_space:
				continue
			prev_space = true
			out += ch
		else:
			prev_space = false
			out += ch
	return out.strip_edges()


## 窗口文本累计。非法输入返回 {}（稳定拒绝，不部分累计）。
static func accumulate_window(input: Dictionary) -> Dictionary:
	if typeof(input) != TYPE_DICTIONARY or input.is_empty():
		return {}

	# rule_version：必须显式且与当前 catalog 一致
	var rv_v: Variant = input.get("rule_version", null)
	if typeof(rv_v) != TYPE_STRING and typeof(rv_v) != TYPE_STRING_NAME:
		return {}
	var rule_version := String(rv_v)
	if rule_version != TrashTalkRuleCatalog.rule_version():
		return {}

	var window_v: Variant = input.get("window_id", null)
	if typeof(window_v) != TYPE_STRING and typeof(window_v) != TYPE_STRING_NAME:
		return {}
	var window_id := String(window_v).strip_edges()
	if window_id.is_empty():
		return {}
	if not _is_int(input.get("seat", null)):
		return {}
	var seat: int = int(input["seat"])
	if seat < 0 or seat > 3:
		return {}
	var char_v: Variant = input.get("character_id", null)
	if typeof(char_v) != TYPE_STRING and typeof(char_v) != TYPE_STRING_NAME:
		return {}
	var character_id := String(char_v).strip_edges()
	if character_id.is_empty():
		return {}

	var window_lang := _optional_lang(input.get("language", null))

	# 解析 utterances：同 ID 冲突整窗拒绝；同 payload 幂等；与输入序无关
	var by_uid: Dictionary = {}
	var raw_utts: Variant = input.get("utterances", [])
	if not (raw_utts is Array):
		return {}
	for u in raw_utts:
		if typeof(u) != TYPE_DICTIONARY:
			continue
		var uid_v: Variant = u.get("utterance_id", null)
		if typeof(uid_v) != TYPE_STRING and typeof(uid_v) != TYPE_STRING_NAME:
			continue
		var uid := String(uid_v)
		if uid.is_empty():
			continue
		var text_v: Variant = u.get("text", "")
		var text := String(text_v) if text_v != null else ""
		var u_lang := _optional_lang(u.get("language", null))
		var resolved := ""
		if u_lang != "":
			resolved = u_lang
		elif window_lang != "":
			resolved = window_lang
		else:
			return {}
		if not ALLOWED_LANGS.has(resolved):
			return {}
		if by_uid.has(uid):
			var prev: Dictionary = by_uid[uid]
			if String(prev["text"]) != text or String(prev["language"]) != resolved:
				return {}
			# 同 payload：忽略重复
			continue
		by_uid[uid] = {"utterance_id": uid, "text": text, "language": resolved}

	var utterances: Array = by_uid.values()
	utterances.sort_custom(func(a, b): return String(a["utterance_id"]) < String(b["utterance_id"]))

	var affinity: Dictionary = _zero_affinity()
	var specificity: int = 0
	var expression_quality: int = 0
	var matched: Dictionary = {}
	var primary := _character_primary_affinity(character_id)
	var rules: Array = _catalog_text_rules()

	for u in utterances:
		var lang: String = u["language"]
		var norm_text: String = normalize(String(u["text"]))
		if norm_text.is_empty():
			continue
		for rule in rules:
			if typeof(rule) != TYPE_DICTIONARY:
				continue
			var rid := String(rule.get("rule_id", ""))
			if rid.is_empty() or matched.has(rid):
				continue
			if not _rule_matches(rule, norm_text, character_id, lang):
				continue
			matched[rid] = true
			var points: int = int(rule.get("points", 0))
			var cap: int = int(rule.get("cap", 1000))
			if points < 0:
				points = 0
			if cap < 0:
				cap = 0
			if cap > 1000:
				cap = 1000
			var kind := String(rule.get("match", {}).get("kind", ""))
			if kind == "PERSONA_KEYWORD" or kind == "PERSONA_TEMPLATE":
				if primary != "" and affinity.has(primary):
					affinity[primary] = mini(1000, int(affinity[primary]) + points)
			elif kind == "EXPRESSION":
				expression_quality = mini(cap, expression_quality + points)
			elif kind == "ITEM_TAG":
				var match: Dictionary = rule.get("match", {})
				var tag := String(match.get("tag", "")).to_upper()
				if affinity.has(tag):
					affinity[tag] = mini(1000, int(affinity[tag]) + points)
				var item_id := String(match.get("item_id", rule.get("item_id", "")))
				var def: Dictionary = TrashTalkRuleCatalog.item_def(StringName(item_id))
				if not def.is_empty():
					var spec: int = int(def.get("specificity", 0))
					if spec < 0:
						spec = 0
					if spec > 100:
						spec = 100
					var mapped: int = spec * 10
					if mapped > specificity:
						specificity = mapped

	var matched_ids: Array = matched.keys()
	matched_ids.sort()

	return {
		"rule_version": rule_version,
		"window_id": window_id,
		"seat": seat,
		"character_id": character_id,
		"matched_rule_ids": matched_ids,
		"affinity": affinity,
		"specificity": specificity,
		"expression_quality": expression_quality,
	}


static func _catalog_text_rules() -> Array:
	var out: Array = []
	for r in TrashTalkRuleCatalog.all_rules():
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var kind := String(r.get("match", {}).get("kind", ""))
		if _TEXT_KINDS.has(kind):
			out.append(r)
	return out


static func _rule_matches(
	rule: Dictionary,
	norm_text: String,
	character_id: String,
	language: String
) -> bool:
	var match: Dictionary = rule.get("match", {})
	if match.is_empty():
		return false
	var kind := String(match.get("kind", ""))
	if not _TEXT_KINDS.has(kind):
		return false
	if kind == "PERSONA_KEYWORD" or kind == "PERSONA_TEMPLATE":
		if String(match.get("character_id", "")) != character_id:
			return false
		if String(match.get("language", "")) != language:
			return false
		return _any_pattern_hits(match.get("patterns", []), norm_text)
	if kind == "EXPRESSION":
		if String(match.get("language", "")) != language:
			return false
		return _any_pattern_hits(match.get("patterns", []), norm_text)
	if kind == "ITEM_TAG":
		var mp: Variant = match.get("patterns", {})
		if mp is Dictionary:
			if not mp.has(language):
				return false
			var arr: Variant = mp[language]
			return _any_pattern_hits(arr, norm_text)
		# 非字典形态不匹配（生产 catalog 均为三语 Dictionary）
		return false
	return false


static func _any_pattern_hits(patterns: Variant, norm_text: String) -> bool:
	if not (patterns is Array):
		return false
	for p in patterns:
		var pn := normalize(String(p))
		if pn.is_empty():
			continue
		if norm_text.contains(pn):
			return true
	return false


static func _optional_lang(v: Variant) -> String:
	if typeof(v) != TYPE_STRING and typeof(v) != TYPE_STRING_NAME:
		return ""
	var s := String(v).strip_edges().to_lower()
	if ALLOWED_LANGS.has(s):
		return s
	# 非法非空：返回哨兵，由调用方拒绝（与空区分：非法也走拒绝）
	if not s.is_empty():
		return "__invalid__"
	return ""


static func _character_primary_affinity(character_id: String) -> String:
	var c: Character = CharacterPool.find(StringName(character_id))
	if c == null:
		var persona: Dictionary = TrashTalkRuleCatalog.character_persona(StringName(character_id))
		return String(persona.get("affinity_primary", "")).to_upper()
	return String(Character.normalize_affinity(c.affinity_primary))


static func _zero_affinity() -> Dictionary:
	var d: Dictionary = {}
	for k in AFFINITY_KEYS:
		d[k] = 0
	return d


static func _is_int(v: Variant) -> bool:
	return typeof(v) == TYPE_INT


static func _is_basic_punct(code: int) -> bool:
	# 半角 ASCII 标点
	match code:
		0x21, 0x22, 0x27, 0x28, 0x29, 0x2C, 0x2E, 0x3A, 0x3B, 0x3F:
			return true
		0x3001, 0x3002: # 、。
			return true
		0xFF0C, 0xFF0E, 0xFF01, 0xFF1F, 0xFF1A, 0xFF1B:
			return true
		0x201C, 0x201D, 0x2018, 0x2019:
			return true
		# 半角日文标点：｡ ｢ ｣ ､ ･
		0xFF61, 0xFF62, 0xFF63, 0xFF64, 0xFF65:
			return true
		_:
			return false


static func _apply_dakuten(base: int, is_dakuten: bool) -> int:
	if is_dakuten:
		if _DAKUTEN_MAP.has(base):
			return int(_DAKUTEN_MAP[base])
		return 0
	if _HANDAKUTEN_MAP.has(base):
		return int(_HANDAKUTEN_MAP[base])
	return 0
