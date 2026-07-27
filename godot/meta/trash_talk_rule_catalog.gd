class_name TrashTalkRuleCatalog extends RefCounted

# E5-01 / #249：版本化垃圾话内容规则库。
# 只冻结内容与契约；不实现 TextAnalyzer / 评分引擎 / RewardWindow / 发奖。

const RULE_VERSION := "trash_talk_rules_v1"
const SCORE_COMPONENT_ORDER: Array[String] = ["persona", "item_tag", "public_context", "expression"]
const LANGUAGES: Array[String] = ["zh", "en", "ja"]
const AFFINITY_KEYS: Array[String] = ["DOMINATION", "CALM", "CUNNING", "PASSION", "MYSTIC"]
const PUBLIC_CONTEXT_TAGS: Array[String] = [
	"CTX_RIICHI_OPEN",
	"CTX_MELD_SEEN",
	"CTX_SEAT_LEADING",
	"CTX_SEAT_TRAILING",
	"CTX_WINDOW_LATE",
	"CTX_DORA_REVEALED",
	# E5-03 / #251：庄家 / 和牌公开事实（逐席；CANCELLED 路径供适配器审计）
	"CTX_IS_DEALER",
	"CTX_RON_WINNER",
	"CTX_TSUMO_WINNER",
	"CTX_DEAL_IN_LOSER",
]

static func rule_version() -> String:
	return RULE_VERSION

static func score_component_order() -> Array:
	return SCORE_COMPONENT_ORDER.duplicate()

static func version_meta() -> Dictionary:
	return {
		"rule_version": RULE_VERSION,
		"score_component_order": score_component_order(),
		"component_min": 0,
		"component_max": 1000,
		"once_per_window_seat": true,
		"accumulation_order": score_component_order(),
	}

static func character_ids() -> Array:
	var out: Array = []
	for c in CharacterPool.all():
		out.append(String(c.id))
	return out

static func character_persona(character_id: StringName) -> Dictionary:
	var table: Dictionary = _persona_table()
	if not table.has(String(character_id)):
		return {}
	var row: Dictionary = table[String(character_id)].duplicate(true)
	var c: Character = CharacterPool.find(character_id)
	if c != null:
		row["affinity_primary"] = String(c.affinity_primary)
		row["affinity_secondary"] = String(c.affinity_secondary)
		row["id"] = String(c.id)
	return row

static func grantable_item_ids() -> Array:
	return ItemCatalog.grantable_ids()


static func is_alpha_grantable(item_id: String) -> bool:
	var id := String(item_id).strip_edges()
	var definition := ItemCatalog.definition(StringName(id))
	return definition != null and definition.is_grantable

static func item_def(item_id: StringName) -> Dictionary:
	var table: Dictionary = _item_table()
	var key := String(item_id)
	if not table.has(key):
		return {}
	return table[key].duplicate(true)

static func all_rules() -> Array:
	var out: Array = []
	out.append_array(persona_rules())
	out.append_array(expression_rules())
	out.append_array(public_context_rules())
	for item_id in grantable_item_ids():
		var def: Dictionary = item_def(StringName(item_id))
		for r in def.get("rules", []):
			out.append(r)
	return out

static func persona_rules() -> Array:
	var out: Array = _persona_rules_table().duplicate(true)
	# E5-02 / #250：从已冻结 human + AI 文案生成稳定 PERSONA_TEMPLATE rule_id
	out.append_array(_persona_template_rules_table())
	return out

## 每角色 × 每语言 1 条 PERSONA_TEMPLATE；patterns = human_templates + ai_templates.text。
## rule_id 稳定：r_persona_<character_id>_tpl_<lang>_01；points=100。
static func _persona_template_rules_table() -> Array:
	var out: Array = []
	var table: Dictionary = _persona_table()
	var cids: Array = table.keys()
	cids.sort()
	for cid_v in cids:
		var cid := String(cid_v)
		var row: Dictionary = table[cid]
		var hum: Dictionary = row.get("human_templates", {})
		var ai: Dictionary = row.get("ai_templates", {})
		for lang in LANGUAGES:
			var patterns: Array = []
			if hum.has(lang) and hum[lang] is Array:
				for p in hum[lang]:
					var s := String(p).strip_edges()
					if not s.is_empty():
						patterns.append(s)
			if ai.has(lang) and ai[lang] is Array:
				for line in ai[lang]:
					if typeof(line) != TYPE_DICTIONARY:
						continue
					var t := String(line.get("text", "")).strip_edges()
					if not t.is_empty():
						patterns.append(t)
			if patterns.is_empty():
				continue
			out.append({
				"rule_id": "r_persona_%s_tpl_%s_01" % [cid, lang],
				"component": "persona",
				"points": 100,
				"cap": 1000,
				"once_per_window_seat": true,
				"match": {
					"kind": "PERSONA_TEMPLATE",
					"language": lang,
					"character_id": cid,
					"patterns": patterns,
				},
			})
	return out

static func expression_rules() -> Array:
	return _expression_rules_table().duplicate(true)

static func public_context_rules() -> Array:
	return _public_context_rules_table().duplicate(true)

static func has_rule_id(rule_id: String) -> bool:
	for r in all_rules():
		if String(r.get("rule_id", "")) == rule_id:
			return true
	return false

static func ai_lines_sorted(character_id: StringName, language: String) -> Array:
	var persona: Dictionary = character_persona(character_id)
	if persona.is_empty():
		return []
	var ai: Dictionary = persona.get("ai_templates", {})
	if not ai.has(language):
		return []
	var lines: Array = ai[language].duplicate(true)
	lines.sort_custom(func(a, b): return String(a.get("line_id", "")) < String(b.get("line_id", "")))
	return lines


## 按公开上下文过滤 AI 模板：无条件（空 tags）或 tags 均为当前公开标签子集。
## public_context_tags 调用前须已字典序规范化；候选按 line_id 字典序。
static func ai_lines_for_public_context(
	character_id: StringName,
	language: String,
	public_context_tags: Array
) -> Array:
	var active: Dictionary = {}
	for t in public_context_tags:
		active[String(t)] = true
	var out: Array = []
	for line in ai_lines_sorted(character_id, language):
		var tags: Array = line.get("context_tags", [])
		if tags.is_empty():
			out.append(line)
			continue
		var ok := true
		for tag in tags:
			if not active.has(String(tag)):
				ok = false
				break
		if ok:
			out.append(line)
	return out


static func public_context_tag_set() -> Array:
	return PUBLIC_CONTEXT_TAGS.duplicate()


static func all_visible_text_blob() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for cid in character_ids():
		var p: Dictionary = character_persona(StringName(cid))
		parts.append(str(p))
	for item_id in grantable_item_ids():
		parts.append(str(item_def(StringName(item_id))))
	for r in all_rules():
		parts.append(str(r))
	return " ".join(parts)


static func validate_schema() -> Dictionary:
	var errors: Array = []
	if rule_version().is_empty():
		errors.append("empty rule_version")
	if score_component_order() != ["persona", "item_tag", "public_context", "expression"]:
		errors.append("score order mismatch")
	var pool_ids: Array = []
	for c in CharacterPool.all():
		pool_ids.append(String(c.id))
	pool_ids.sort()
	var cat_ids: Array = character_ids()
	var cat_sorted: Array = cat_ids.duplicate()
	cat_sorted.sort()
	if cat_sorted != pool_ids:
		errors.append("character set drift vs CharacterPool")
	# #253：grantable 是图鉴中由统一道具定义显式启用的子集。
	var codex_ids: Array = []
	for row in LobbyCodexCatalog.new().items():
		codex_ids.append(String(row.get("id", "")))
	codex_ids.sort()
	var grant: Array = grantable_item_ids()
	var grant_sorted: Array = grant.duplicate()
	grant_sorted.sort()
	var expected_grant: Array = []
	for cid in codex_ids:
		var item := ItemCatalog.definition(StringName(String(cid)))
		if item != null and item.is_grantable:
			expected_grant.append(String(cid))
	expected_grant.sort()
	if grant_sorted != expected_grant:
		errors.append("grantable set drift vs LobbyCodexCatalog and ItemCatalog")
	if grant_sorted.size() != expected_grant.size():
		errors.append("grantable count mismatch")
	for value in ItemCatalog.all():
		var definition := value as ItemDefinition
		if definition != null and not definition.is_grantable \
				and grant_sorted.has(String(definition.id)):
			errors.append("non-grantable leaked: %s" % definition.id)
	var allowed_ctx: Dictionary = {}
	for t in PUBLIC_CONTEXT_TAGS:
		allowed_ctx[t] = true
	var seen_rules := {}
	var seen_line_ids := {}
	for r in all_rules():
		var rid := String(r.get("rule_id", ""))
		if rid.is_empty():
			errors.append("empty rule_id")
			continue
		if seen_rules.has(rid):
			errors.append("duplicate rule_id %s" % rid)
		seen_rules[rid] = true
		if not bool(r.get("once_per_window_seat", false)):
			errors.append("once_per_window_seat false: %s" % rid)
		var comp := String(r.get("component", ""))
		if not SCORE_COMPONENT_ORDER.has(comp):
			errors.append("bad component %s" % rid)
		var points := int(r.get("points", -1))
		var cap := int(r.get("cap", -1))
		if points < 0 or points > 1000 or cap < 0 or cap > 1000 or points > cap:
			errors.append("points/cap invalid %s" % rid)
		var match: Dictionary = r.get("match", {})
		if match.is_empty():
			errors.append("missing match %s" % rid)
		else:
			_validate_match(match, rid, grant_sorted, pool_ids, allowed_ctx, errors)
	for item_id in grant:
		var def: Dictionary = item_def(StringName(item_id))
		if def.is_empty():
			errors.append("missing item_def %s" % item_id)
			continue
		if not def.has("priority") or typeof(def["priority"]) != TYPE_INT:
			errors.append("item priority missing/int %s" % item_id)
		else:
			var pri: int = def["priority"]
			if pri < 1 or pri > 100:
				errors.append("item priority range %s" % item_id)
		if not def.has("specificity") or typeof(def["specificity"]) != TYPE_INT:
			errors.append("item specificity missing/int %s" % item_id)
		else:
			var spec: int = def["specificity"]
			if spec < 1 or spec > 100:
				errors.append("item specificity range %s" % item_id)
		var pats: Dictionary = def.get("patterns", {})
		for lang in LANGUAGES:
			if not pats.has(lang) or not (pats[lang] is Array) or pats[lang].is_empty():
				errors.append("item patterns.%s empty %s" % [lang, item_id])
			else:
				for p in pats[lang]:
					if String(p).strip_edges().is_empty():
						errors.append("item pattern blank %s/%s" % [item_id, lang])
		for tag in def.get("tags", []):
			if String(tag).is_empty():
				errors.append("empty tag on %s" % item_id)
		for ct in def.get("public_context_tags", []):
			if not allowed_ctx.has(String(ct)):
				errors.append("item ctx illegal %s %s" % [item_id, ct])
	for cid in character_ids():
		var p: Dictionary = character_persona(StringName(cid))
		var c: Character = CharacterPool.find(StringName(cid))
		if c == null:
			errors.append("missing pool char %s" % cid)
			continue
		if String(p.get("affinity_primary", "")) != String(c.affinity_primary):
			errors.append("affinity primary drift %s" % cid)
		if String(p.get("affinity_secondary", "")) != String(c.affinity_secondary):
			errors.append("affinity secondary drift %s" % cid)
		for lang in LANGUAGES:
			var kws: Array = p.get("keywords", {}).get(lang, [])
			var hum: Array = p.get("human_templates", {}).get(lang, [])
			var ai: Array = p.get("ai_templates", {}).get(lang, [])
			if kws.size() < 6 or hum.is_empty() or ai.size() < 3:
				errors.append("lang incomplete %s/%s" % [cid, lang])
			var has_generic := false
			var has_ctx := false
			for line in ai:
				var lid := String(line.get("line_id", ""))
				if lid.is_empty():
					errors.append("empty line_id %s/%s" % [cid, lang])
				elif seen_line_ids.has(lid):
					errors.append("duplicate line_id %s" % lid)
				else:
					seen_line_ids[lid] = true
				var tags: Array = line.get("context_tags", [])
				if tags.is_empty():
					has_generic = true
				else:
					has_ctx = true
					for tag in tags:
						if not allowed_ctx.has(String(tag)):
							errors.append("ai ctx illegal %s %s" % [lid, tag])
				if String(line.get("text", "")).strip_edges().is_empty():
					errors.append("empty ai text %s" % lid)
			if not has_generic:
				errors.append("missing generic ai %s/%s" % [cid, lang])
			if not has_ctx:
				errors.append("missing contextual ai %s/%s" % [cid, lang])
	return {"ok": errors.is_empty(), "errors": errors}


static func _validate_match(
	match: Dictionary,
	rid: String,
	grant_ids: Array,
	pool_ids: Array,
	allowed_ctx: Dictionary,
	errors: Array
) -> void:
	var kind := String(match.get("kind", ""))
	match kind:
		"PERSONA_KEYWORD", "PERSONA_TEMPLATE":
			var lang := String(match.get("language", ""))
			if not LANGUAGES.has(lang):
				errors.append("match lang %s @ %s" % [lang, rid])
			var cid := String(match.get("character_id", ""))
			if not pool_ids.has(cid):
				errors.append("match character %s @ %s" % [cid, rid])
			var pats: Array = match.get("patterns", [])
			if pats.is_empty():
				errors.append("match patterns empty %s" % rid)
		"EXPRESSION":
			var lang2 := String(match.get("language", ""))
			if not LANGUAGES.has(lang2):
				errors.append("expr lang %s @ %s" % [lang2, rid])
			if match.get("patterns", []).is_empty():
				errors.append("expr patterns empty %s" % rid)
		"PUBLIC_CONTEXT":
			var ct := String(match.get("context_tag", ""))
			if not allowed_ctx.has(ct):
				errors.append("public ctx %s @ %s" % [ct, rid])
		"ITEM_TAG":
			var iid := String(match.get("item_id", ""))
			if not grant_ids.has(iid):
				errors.append("item_id %s @ %s" % [iid, rid])
			if String(match.get("tag", "")).is_empty():
				errors.append("item tag empty %s" % rid)
			var mp: Dictionary = match.get("patterns", {})
			for lang3 in LANGUAGES:
				if not mp.has(lang3) or not (mp[lang3] is Array) or mp[lang3].is_empty():
					errors.append("item rule patterns.%s %s" % [lang3, rid])
		_:
			errors.append("unknown match kind %s @ %s" % [kind, rid])

static func _persona_table() -> Dictionary:
	return {
		"lin_yeche": {
			"id": "lin_yeche",
			"display_name": "林夜彻",
			"affinity_primary": "CUNNING",
			"affinity_secondary": "MYSTIC",
			"keywords": {
				"zh": ["读脊", "信息差", "透视", "安静", "算好了", "下家", "陷阱", "看穿"],
				"en": ["read you", "info edge", "peek", "quiet", "calculated", "downstream", "trap", "see through"],
				"ja": ["背を読む", "情報差", "透視", "静か", "計算済み", "下家", "罠", "見透かす"],
			},
			"human_templates": {
				"zh": ["牌背的纹路比你的表情诚实。", "我只需要一张信息，就够了。"],
				"en": ["Your tile backs are louder than your face.", "One scrap of info is enough."],
				"ja": ["牌背の方が表情より正直だ。", "情報は一枚で足りる。"],
			},
			"ai_templates": {
				"zh": [
					{"line_id": "ai_lin_yeche_zh_01", "text": "安静点，让我把你的脊梁读完。", "context_tags": []},
					{"line_id": "ai_lin_yeche_zh_02", "text": "信息差已经拉开了，别急着送。", "context_tags": []},
					{"line_id": "ai_lin_yeche_zh_03", "text": "巡数拉长了，你的牌河比嘴还诚实。", "context_tags": ["CTX_WINDOW_LATE"]},
				],
				"en": [
					{"line_id": "ai_lin_yeche_en_01", "text": "Quiet. I'm still reading your spine.", "context_tags": []},
					{"line_id": "ai_lin_yeche_en_02", "text": "Info edge is mine—don't rush the gift.", "context_tags": []},
					{"line_id": "ai_lin_yeche_en_03", "text": "Late window—your river talks louder than you.", "context_tags": ["CTX_WINDOW_LATE"]},
				],
				"ja": [
					{"line_id": "ai_lin_yeche_ja_01", "text": "静かにして。まだ背を読んでる。", "context_tags": []},
					{"line_id": "ai_lin_yeche_ja_02", "text": "情報差は開いた。急いで送りつけるな。", "context_tags": []},
					{"line_id": "ai_lin_yeche_ja_03", "text": "終盤だ。河の方が口より正直だ。", "context_tags": ["CTX_WINDOW_LATE"]},
				],
			},
		},
		"qiu_jue": {
			"id": "qiu_jue",
			"display_name": "裘绝",
			"affinity_primary": "PASSION",
			"affinity_secondary": "DOMINATION",
			"keywords": {
				"zh": ["燃烧", "绝崖", "翻盘", "必胜", "点棒见底", "热血", "来吧", "全力"],
				"en": ["burn", "cliff edge", "comeback", "must win", "bottom score", "blood pump", "bring it", "all in"],
				"ja": ["燃えろ", "絶崖", "逆転", "必勝", "点棒底", "熱血", "来い", "全力"],
			},
			"human_templates": {
				"zh": ["越危险，我越兴奋。", "见底的点棒，才是我的舞台。"],
				"en": ["Danger is the only warm-up I need.", "Bottom of the table is my stage."],
				"ja": ["危ないほど燃える。", "点棒が底を打つときが本番だ。"],
			},
			"ai_templates": {
				"zh": [
					{"line_id": "ai_qiu_jue_zh_01", "text": "燃烧起来！这局我必胜翻盘！", "context_tags": []},
					{"line_id": "ai_qiu_jue_zh_02", "text": "绝崖之上，才配看见风景。", "context_tags": []},
					{"line_id": "ai_qiu_jue_zh_03", "text": "垫底正好——绝崖翻盘从这里起跳。", "context_tags": ["CTX_SEAT_TRAILING"]},
				],
				"en": [
					{"line_id": "ai_qiu_jue_en_01", "text": "Burn it up! This hand is my comeback!", "context_tags": []},
					{"line_id": "ai_qiu_jue_en_02", "text": "Cliff edge view only—no soft landings.", "context_tags": []},
					{"line_id": "ai_qiu_jue_en_03", "text": "Bottom seat? Perfect cliff for a comeback.", "context_tags": ["CTX_SEAT_TRAILING"]},
				],
				"ja": [
					{"line_id": "ai_qiu_jue_ja_01", "text": "燃えろ！この局で逆転必勝だ！", "context_tags": []},
					{"line_id": "ai_qiu_jue_ja_02", "text": "絶崖の上だけが景色を見る資格がある。", "context_tags": []},
					{"line_id": "ai_qiu_jue_ja_03", "text": "最下位？ちょうどいい絶崖だ。", "context_tags": ["CTX_SEAT_TRAILING"]},
				],
			},
		},
		"bai_touli": {
			"id": "bai_touli",
			"display_name": "白透璃",
			"affinity_primary": "MYSTIC",
			"affinity_secondary": "CUNNING",
			"keywords": {
				"zh": ["透璃", "礼貌", "全桌", "透视", "信息压迫", "感应", "看穿", "客气"],
				"en": ["glass clear", "polite", "whole table", "see through", "info pressure", "sense", "pierce", "courtesy"],
				"ja": ["透璃", "礼儀", "卓全体", "透視", "情報圧", "感応", "見破る", "ご丁寧"],
			},
			"human_templates": {
				"zh": ["请原谅我的礼貌——和全桌透视。", "信息压迫，也可以很温柔。"],
				"en": ["Pardon my manners—and the full-table peek.", "Pressure can still be soft-spoken."],
				"ja": ["失礼、礼儀と透視は両立する。", "圧力も穏やかにかけられる。"],
			},
			"ai_templates": {
				"zh": [
					{"line_id": "ai_bai_touli_zh_01", "text": "失礼了，我已经看过各位的两张牌。", "context_tags": []},
					{"line_id": "ai_bai_touli_zh_02", "text": "透璃之下，没有秘密可以躲。", "context_tags": []},
					{"line_id": "ai_bai_touli_zh_03", "text": "鸣牌一响，全桌信息又多了一层。", "context_tags": ["CTX_MELD_SEEN"]},
				],
				"en": [
					{"line_id": "ai_bai_touli_en_01", "text": "Excuse me. I've already seen two tiles from each of you.", "context_tags": []},
					{"line_id": "ai_bai_touli_en_02", "text": "Under clear glass, secrets don't hide.", "context_tags": []},
					{"line_id": "ai_bai_touli_en_03", "text": "A call just layered the whole table's info.", "context_tags": ["CTX_MELD_SEEN"]},
				],
				"ja": [
					{"line_id": "ai_bai_touli_ja_01", "text": "失礼。皆さん二枚ずつ拝見しました。", "context_tags": []},
					{"line_id": "ai_bai_touli_ja_02", "text": "透璃の下に秘密は隠せない。", "context_tags": []},
					{"line_id": "ai_bai_touli_ja_03", "text": "鳴き一回で、卓の情報が増えた。", "context_tags": ["CTX_MELD_SEEN"]},
				],
			},
		},
		"hua_ling": {
			"id": "hua_ling",
			"display_name": "华岭澄",
			"affinity_primary": "DOMINATION",
			"affinity_secondary": "PASSION",
			"keywords": {
				"zh": ["岭华", "宝牌", "强运", "绽放", "碾压", "额外", "跟我", "华丽"],
				"en": ["ridge bloom", "dora", "hot streak", "blossom", "crush", "extra", "follow me", "flashy"],
				"ja": ["嶺華", "ドラ", "強運", "咲く", "圧倒", "追加", "ついて来い", "華やか"],
			},
			"human_templates": {
				"zh": ["宝牌喜欢跟着我走。", "强运不是运气，是气场。"],
				"en": ["Dora likes walking with me.", "A hot streak is just aura with math."],
				"ja": ["ドラは私の後ろをついて来る。", "強運は気位の別名だ。"],
			},
			"ai_templates": {
				"zh": [
					{"line_id": "ai_hua_ling_zh_01", "text": "岭华一绽，场上就该安静了。", "context_tags": []},
					{"line_id": "ai_hua_ling_zh_02", "text": "宝牌在我这边，别跟强运抬杠。", "context_tags": []},
					{"line_id": "ai_hua_ling_zh_03", "text": "新宝翻开了，强运该找我了。", "context_tags": ["CTX_DORA_REVEALED"]},
				],
				"en": [
					{"line_id": "ai_hua_ling_en_01", "text": "When the ridge blooms, the table goes quiet.", "context_tags": []},
					{"line_id": "ai_hua_ling_en_02", "text": "Dora's on my side—don't argue with a streak.", "context_tags": []},
					{"line_id": "ai_hua_ling_en_03", "text": "Fresh dora revealed—streak's looking for me.", "context_tags": ["CTX_DORA_REVEALED"]},
				],
				"ja": [
					{"line_id": "ai_hua_ling_ja_01", "text": "嶺華が咲けば、卓は黙るべきだ。", "context_tags": []},
					{"line_id": "ai_hua_ling_ja_02", "text": "ドラはこちら。強運に逆らうな。", "context_tags": []},
					{"line_id": "ai_hua_ling_ja_03", "text": "ドラがめくれた。強運は私を探す。", "context_tags": ["CTX_DORA_REVEALED"]},
				],
			},
		},
		"lian_yao": {
			"id": "lian_yao",
			"display_name": "连曜真",
			"affinity_primary": "DOMINATION",
			"affinity_secondary": "PASSION",
			"keywords": {
				"zh": ["连曜", "连斩", "叠层", "越和越重", "连胜", "压迫", "再来", "加番"],
				"en": ["linked blaze", "chain cut", "stack", "heavier each win", "streak", "pressure", "again", "extra han"],
				"ja": ["連曜", "連斬", "重ね", "勝つほど重い", "連勝", "圧", "もう一回", "翻数追加"],
			},
			"human_templates": {
				"zh": ["一次不够，叠起来才像样。", "连斩的节奏，别打断。"],
				"en": ["Once is noise. Stacks are style.", "Don't break a chain-cut rhythm."],
				"ja": ["一回じゃ足りない。重ねてこそだ。", "連斬の拍を崩すな。"],
			},
			"ai_templates": {
				"zh": [
					{"line_id": "ai_lian_yao_zh_01", "text": "连曜起跳，下一刀更重。", "context_tags": []},
					{"line_id": "ai_lian_yao_zh_02", "text": "越和越重——你跟得上吗？", "context_tags": []},
					{"line_id": "ai_lian_yao_zh_03", "text": "领先席也别松气，连斩还在叠。", "context_tags": ["CTX_SEAT_LEADING"]},
				],
				"en": [
					{"line_id": "ai_lian_yao_en_01", "text": "Linked blaze—next cut lands harder.", "context_tags": []},
					{"line_id": "ai_lian_yao_en_02", "text": "Heavier each win. Keep up.", "context_tags": []},
					{"line_id": "ai_lian_yao_en_03", "text": "Even in the lead—chain cuts still stack.", "context_tags": ["CTX_SEAT_LEADING"]},
				],
				"ja": [
					{"line_id": "ai_lian_yao_ja_01", "text": "連曜が跳ねる。次はもっと重い。", "context_tags": []},
					{"line_id": "ai_lian_yao_ja_02", "text": "勝つほど重い——ついて来れるか？", "context_tags": []},
					{"line_id": "ai_lian_yao_ja_03", "text": "トップでも気を抜くな。連斬は続く。", "context_tags": ["CTX_SEAT_LEADING"]},
				],
			},
		},
		"an_cheng": {
			"id": "an_cheng",
			"display_name": "安澄青",
			"affinity_primary": "CALM",
			"affinity_secondary": "MYSTIC",
			"keywords": {
				"zh": ["澄安", "安全", "冷静", "净界", "观察", "预知", "稳", "计算"],
				"en": ["still water", "safe first", "calm", "clear field", "observe", "foresee", "steady", "calculate"],
				"ja": ["澄安", "安全", "冷静", "浄界", "観察", "予見", "安定", "計算"],
			},
			"human_templates": {
				"zh": ["安全先于进攻。", "风停了，牌才会听话。"],
				"en": ["Safety before aggression.", "When the wind dies, tiles listen."],
				"ja": ["攻めより安全が先。", "風が止まれば牌は従う。"],
			},
			"ai_templates": {
				"zh": [
					{"line_id": "ai_an_cheng_zh_01", "text": "先清桌面，再谈胜负。", "context_tags": []},
					{"line_id": "ai_an_cheng_zh_02", "text": "冷静不是慢，是不犯错。", "context_tags": []},
					{"line_id": "ai_an_cheng_zh_03", "text": "立直亮了，我先把桌面擦干净。", "context_tags": ["CTX_RIICHI_OPEN"]},
				],
				"en": [
					{"line_id": "ai_an_cheng_en_01", "text": "Clear the table first. Score later.", "context_tags": []},
					{"line_id": "ai_an_cheng_en_02", "text": "Calm isn't slow—it's error-free.", "context_tags": []},
					{"line_id": "ai_an_cheng_en_03", "text": "Riichi is up—I'll clear the table first.", "context_tags": ["CTX_RIICHI_OPEN"]},
				],
				"ja": [
					{"line_id": "ai_an_cheng_ja_01", "text": "まず場を清めてから勝負だ。", "context_tags": []},
					{"line_id": "ai_an_cheng_ja_02", "text": "冷静は遅いことじゃない。ミスしないことだ。", "context_tags": []},
					{"line_id": "ai_an_cheng_ja_03", "text": "リーチが出た。先に場を整える。", "context_tags": ["CTX_RIICHI_OPEN"]},
				],
			},
		},
		"yuan_xi": {
			"id": "yuan_xi",
			"display_name": "渊汐",
			"affinity_primary": "MYSTIC",
			"affinity_secondary": "CALM",
			"keywords": {
				"zh": ["渊掌", "海底", "河底", "潮汐", "墙顶", "深", "末巡", "压底"],
				"en": ["abyss palm", "last draw", "river bottom", "tide", "wall top", "deep", "late turn", "bottom pressure"],
				"ja": ["淵掌", "海底", "河底", "潮", "山の天辺", "深い", "終盤", "底圧"],
			},
			"human_templates": {
				"zh": ["底牌才是主菜。", "潮落之处，我最清醒。"],
				"en": ["Bottom tiles are the main course.", "I think clearest at low tide."],
				"ja": ["底の牌がメインだ。", "潮が引くときがいちばん冴える。"],
			},
			"ai_templates": {
				"zh": [
					{"line_id": "ai_yuan_xi_zh_01", "text": "渊潮上来了，末巡别眨眼。", "context_tags": []},
					{"line_id": "ai_yuan_xi_zh_02", "text": "海底河底，都是我的水域。", "context_tags": []},
					{"line_id": "ai_yuan_xi_zh_03", "text": "末巡潮水上来，底牌才是主菜。", "context_tags": ["CTX_WINDOW_LATE"]},
				],
				"en": [
					{"line_id": "ai_yuan_xi_en_01", "text": "Abyss tide rising—don't blink late.", "context_tags": []},
					{"line_id": "ai_yuan_xi_en_02", "text": "Last draw, river bottom—my water.", "context_tags": []},
					{"line_id": "ai_yuan_xi_en_03", "text": "Late tide rising—bottom tiles are dinner.", "context_tags": ["CTX_WINDOW_LATE"]},
				],
				"ja": [
					{"line_id": "ai_yuan_xi_ja_01", "text": "淵の潮が来る。終盤で瞬くな。", "context_tags": []},
					{"line_id": "ai_yuan_xi_ja_02", "text": "海底も河底も、こっちの水域だ。", "context_tags": []},
					{"line_id": "ai_yuan_xi_ja_03", "text": "終盤の潮が来る。底牌がメインだ。", "context_tags": ["CTX_WINDOW_LATE"]},
				],
			},
		},
		"ji_shu": {
			"id": "ji_shu",
			"display_name": "纪枢",
			"affinity_primary": "CALM",
			"affinity_secondary": "CUNNING",
			"keywords": {
				"zh": ["算枢", "概率", "圣裁", "听牌", "分析", "公式", "冷静刀", "读型"],
				"en": ["pivot math", "odds", "verdict", "tenpai", "analyze", "formula", "cold blade", "read shape"],
				"ja": ["算枢", "確率", "裁決", "聴牌", "分析", "式", "冷静の刃", "形読み"],
			},
			"human_templates": {
				"zh": ["概率不站队，只站我。", "听牌成型时，桌面最吵。"],
				"en": ["Odds don't pick sides—except mine.", "Tenpai is when the table gets loud."],
				"ja": ["確率は中立じゃない。私側だ。", "聴牌が一番うるさい。"],
			},
			"ai_templates": {
				"zh": [
					{"line_id": "ai_ji_shu_zh_01", "text": "公式写完了，轮到你交差。", "context_tags": []},
					{"line_id": "ai_ji_shu_zh_02", "text": "听牌一响，我就翻你一张。", "context_tags": []},
					{"line_id": "ai_ji_shu_zh_03", "text": "立直宣告后，概率公式该改写了。", "context_tags": ["CTX_RIICHI_OPEN"]},
				],
				"en": [
					{"line_id": "ai_ji_shu_en_01", "text": "Formula's done. Your turn to submit.", "context_tags": []},
					{"line_id": "ai_ji_shu_en_02", "text": "Tenpai rings—I flip one of yours.", "context_tags": []},
					{"line_id": "ai_ji_shu_en_03", "text": "After riichi, the odds formula rewrites.", "context_tags": ["CTX_RIICHI_OPEN"]},
				],
				"ja": [
					{"line_id": "ai_ji_shu_ja_01", "text": "式はできた。提出はそっちの番。", "context_tags": []},
					{"line_id": "ai_ji_shu_ja_02", "text": "聴牌の音で、一枚めくる。", "context_tags": []},
					{"line_id": "ai_ji_shu_ja_03", "text": "リーチ後、確率の式を書き換える。", "context_tags": ["CTX_RIICHI_OPEN"]},
				],
			},
		},
		"xian_shi": {
			"id": "xian_shi",
			"display_name": "先示",
			"affinity_primary": "MYSTIC",
			"affinity_secondary": "CALM",
			"keywords": {
				"zh": ["先示", "四席", "下一张", "窥运", "预告", "命运线", "早看", "全知"],
				"en": ["first reveal", "four seats", "next tile", "peek fate", "preview", "fate line", "early look", "foreknow"],
				"ja": ["先示", "四家", "次の牌", "運を覗く", "予告", "運命線", "先見", "見通し"],
			},
			"human_templates": {
				"zh": ["开局我就看过四席的下一张。", "命运喜欢提前剧透给我。"],
				"en": ["I saw all four next draws at open.", "Fate likes spoiling me early."],
				"ja": ["開局で四家の次牌を見た。", "運命は私にネタバレしたがる。"],
			},
			"ai_templates": {
				"zh": [
					{"line_id": "ai_xian_shi_zh_01", "text": "先示已毕，别装作意外。", "context_tags": []},
					{"line_id": "ai_xian_shi_zh_02", "text": "四席的下一张，早在我清单上。", "context_tags": []},
					{"line_id": "ai_xian_shi_zh_03", "text": "鸣牌过桌，下一张的预告更吵了。", "context_tags": ["CTX_MELD_SEEN"]},
				],
				"en": [
					{"line_id": "ai_xian_shi_en_01", "text": "First reveal done. Don't fake surprise.", "context_tags": []},
					{"line_id": "ai_xian_shi_en_02", "text": "All four next tiles—already listed.", "context_tags": []},
					{"line_id": "ai_xian_shi_en_03", "text": "Calls across the table—next-tile spoilers get loud.", "context_tags": ["CTX_MELD_SEEN"]},
				],
				"ja": [
					{"line_id": "ai_xian_shi_ja_01", "text": "先示は済んだ。驚いたふりをするな。", "context_tags": []},
					{"line_id": "ai_xian_shi_ja_02", "text": "四家の次牌はもうリストにある。", "context_tags": []},
					{"line_id": "ai_xian_shi_ja_03", "text": "鳴きが渡る。次牌の予告がうるさい。", "context_tags": ["CTX_MELD_SEEN"]},
				],
			},
		},
		"bao_luo": {
			"id": "bao_luo",
			"display_name": "宝络绯",
			"affinity_primary": "PASSION",
			"affinity_secondary": "MYSTIC",
			"keywords": {
				"zh": ["宝络", "红线", "赤宝", "缠腕", "运势", "绯色", "吸宝", "热线"],
				"en": ["treasure thread", "red string", "red dora", "wrist bind", "luck line", "scarlet", "pull dora", "hot line"],
				"ja": ["宝絡", "赤い糸", "赤ドラ", "手首", "運気", "緋", "ドラ引き寄せ", "熱線"],
			},
			"human_templates": {
				"zh": ["红线一缠，宝牌就听话。", "绯色运势，不讲道理。"],
				"en": ["One red string and dora behaves.", "Scarlet luck doesn't do polite."],
				"ja": ["赤い糸を巻けばドラは従う。", "緋の運は理屈を聞かない。"],
			},
			"ai_templates": {
				"zh": [
					{"line_id": "ai_bao_luo_zh_01", "text": "宝络收紧，别跟红线抢人。", "context_tags": []},
					{"line_id": "ai_bao_luo_zh_02", "text": "赤宝喜欢我的手腕。", "context_tags": []},
					{"line_id": "ai_bao_luo_zh_03", "text": "宝指示一亮，红线就该收紧了。", "context_tags": ["CTX_DORA_REVEALED"]},
				],
				"en": [
					{"line_id": "ai_bao_luo_en_01", "text": "Treasure thread tightens—don't fight the string.", "context_tags": []},
					{"line_id": "ai_bao_luo_en_02", "text": "Red dora likes my wrist.", "context_tags": []},
					{"line_id": "ai_bao_luo_en_03", "text": "Dora indicator lit—tighten the red string.", "context_tags": ["CTX_DORA_REVEALED"]},
				],
				"ja": [
					{"line_id": "ai_bao_luo_ja_01", "text": "宝絡が締まる。糸と争うな。", "context_tags": []},
					{"line_id": "ai_bao_luo_ja_02", "text": "赤ドラは私の手首が好きだ。", "context_tags": []},
					{"line_id": "ai_bao_luo_ja_03", "text": "ドラ表示が光った。赤い糸を締めろ。", "context_tags": ["CTX_DORA_REVEALED"]},
				],
			},
		},
		"ying_li": {
			"id": "ying_li",
			"display_name": "影立静",
			"affinity_primary": "CUNNING",
			"affinity_secondary": "CALM",
			"keywords": {
				"zh": ["影立", "立直", "消影", "一发", "蓄势", "潜伏", "静刃", "后手"],
				"en": ["shadow stand", "riichi", "vanish", "ippatsu", "primed", "lurk", "quiet blade", "second move"],
				"ja": ["影立", "リーチ", "消影", "一発", "仕込み", "潜伏", "静刃", "後手"],
			},
			"human_templates": {
				"zh": ["立直之后，影子才会出刀。", "安静的一发，最疼。"],
				"en": ["After riichi, the shadow draws.", "A quiet ippatsu hurts most."],
				"ja": ["リーチのあと、影が刃を出す。", "静かな一発がいちばん痛い。"],
			},
			"ai_templates": {
				"zh": [
					{"line_id": "ai_ying_li_zh_01", "text": "影已立，请对线。", "context_tags": []},
					{"line_id": "ai_ying_li_zh_02", "text": "消影一发，不吵不嚷。", "context_tags": []},
					{"line_id": "ai_ying_li_zh_03", "text": "有人立直，影刃正好出鞘。", "context_tags": ["CTX_RIICHI_OPEN"]},
				],
				"en": [
					{"line_id": "ai_ying_li_en_01", "text": "Shadow stands. Match the line.", "context_tags": []},
					{"line_id": "ai_ying_li_en_02", "text": "Vanish-shot. No noise required.", "context_tags": []},
					{"line_id": "ai_ying_li_en_03", "text": "Someone riichi'd—shadow blade leaves the sheath.", "context_tags": ["CTX_RIICHI_OPEN"]},
				],
				"ja": [
					{"line_id": "ai_ying_li_ja_01", "text": "影は立った。線を合わせて。", "context_tags": []},
					{"line_id": "ai_ying_li_ja_02", "text": "消影の一発。騒ぎは不要。", "context_tags": []},
					{"line_id": "ai_ying_li_ja_03", "text": "誰かがリーチ。影の刃が出る。", "context_tags": ["CTX_RIICHI_OPEN"]},
				],
			},
		},
		"ju_jin": {
			"id": "ju_jin",
			"display_name": "局进吾",
			"affinity_primary": "DOMINATION",
			"affinity_secondary": "CUNNING",
			"keywords": {
				"zh": ["局进", "阶升", "累加", "必杀", "每回更狠", "进阶", "压迫感", "加码"],
				"en": ["table climb", "step up", "stacking", "finisher", "harder each time", "rank up", "pressure", "raise stakes"],
				"ja": ["局進", "階昇", "累加", "必殺", "回ごと", "ランクアップ", "圧", "上乗せ"],
			},
			"human_templates": {
				"zh": ["每和一次，台阶就高一格。", "局进不是喊出来的，是叠出来的。"],
				"en": ["Each win raises the stair.", "Climb is stacked, not shouted."],
				"ja": ["和るたび階段が一段上がる。", "局進は叫ばず積むものだ。"],
			},
			"ai_templates": {
				"zh": [
					{"line_id": "ai_ju_jin_zh_01", "text": "第一阶很轻，后面会教你礼貌。", "context_tags": []},
					{"line_id": "ai_ju_jin_zh_02", "text": "累加启动，别站在阶梯中间。", "context_tags": []},
					{"line_id": "ai_ju_jin_zh_03", "text": "领先也得加码，阶梯不会自己停。", "context_tags": ["CTX_SEAT_LEADING"]},
				],
				"en": [
					{"line_id": "ai_ju_jin_en_01", "text": "Step one is light. Later ones teach manners.", "context_tags": []},
					{"line_id": "ai_ju_jin_en_02", "text": "Stacking live—don't stand mid-stair.", "context_tags": []},
					{"line_id": "ai_ju_jin_en_03", "text": "Even leading needs a raise—stairs don't stop alone.", "context_tags": ["CTX_SEAT_LEADING"]},
				],
				"ja": [
					{"line_id": "ai_ju_jin_ja_01", "text": "一階は軽い。後で礼儀を教える。", "context_tags": []},
					{"line_id": "ai_ju_jin_ja_02", "text": "累加が動いた。階段の途中に立つな。", "context_tags": []},
					{"line_id": "ai_ju_jin_ja_03", "text": "トップでも上乗せ。階段は止まらない。", "context_tags": ["CTX_SEAT_LEADING"]},
				],
			},
		},
	}

static func _persona_rules_table() -> Array:
	return [
		{
			"rule_id": "r_persona_lin_yeche_kw_zh_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "zh",
				"character_id": "lin_yeche",
				"patterns": ["读脊", "信息差", "透视"],
			},
		},
		{
			"rule_id": "r_persona_lin_yeche_kw_en_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "en",
				"character_id": "lin_yeche",
				"patterns": ["read you", "info edge", "peek"],
			},
		},
		{
			"rule_id": "r_persona_lin_yeche_kw_ja_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "ja",
				"character_id": "lin_yeche",
				"patterns": ["背を読む", "情報差", "透視"],
			},
		},
		{
			"rule_id": "r_persona_qiu_jue_kw_zh_01",
			"component": "persona",
			"points": 220,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "zh",
				"character_id": "qiu_jue",
				"patterns": ["燃烧", "绝崖", "翻盘"],
			},
		},
		{
			"rule_id": "r_persona_qiu_jue_kw_en_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "en",
				"character_id": "qiu_jue",
				"patterns": ["burn", "cliff edge", "comeback"],
			},
		},
		{
			"rule_id": "r_persona_qiu_jue_kw_ja_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "ja",
				"character_id": "qiu_jue",
				"patterns": ["燃えろ", "絶崖", "逆転"],
			},
		},
		{
			"rule_id": "r_persona_bai_touli_kw_zh_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "zh",
				"character_id": "bai_touli",
				"patterns": ["透璃", "礼貌", "全桌"],
			},
		},
		{
			"rule_id": "r_persona_bai_touli_kw_en_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "en",
				"character_id": "bai_touli",
				"patterns": ["glass clear", "polite", "whole table"],
			},
		},
		{
			"rule_id": "r_persona_bai_touli_kw_ja_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "ja",
				"character_id": "bai_touli",
				"patterns": ["透璃", "礼儀", "卓全体"],
			},
		},
		{
			"rule_id": "r_persona_hua_ling_kw_zh_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "zh",
				"character_id": "hua_ling",
				"patterns": ["岭华", "宝牌", "强运"],
			},
		},
		{
			"rule_id": "r_persona_hua_ling_kw_en_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "en",
				"character_id": "hua_ling",
				"patterns": ["ridge bloom", "dora", "hot streak"],
			},
		},
		{
			"rule_id": "r_persona_hua_ling_kw_ja_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "ja",
				"character_id": "hua_ling",
				"patterns": ["嶺華", "ドラ", "強運"],
			},
		},
		{
			"rule_id": "r_persona_lian_yao_kw_zh_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "zh",
				"character_id": "lian_yao",
				"patterns": ["连曜", "连斩", "叠层"],
			},
		},
		{
			"rule_id": "r_persona_lian_yao_kw_en_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "en",
				"character_id": "lian_yao",
				"patterns": ["linked blaze", "chain cut", "stack"],
			},
		},
		{
			"rule_id": "r_persona_lian_yao_kw_ja_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "ja",
				"character_id": "lian_yao",
				"patterns": ["連曜", "連斬", "重ね"],
			},
		},
		{
			"rule_id": "r_persona_an_cheng_kw_zh_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "zh",
				"character_id": "an_cheng",
				"patterns": ["澄安", "安全", "冷静"],
			},
		},
		{
			"rule_id": "r_persona_an_cheng_kw_en_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "en",
				"character_id": "an_cheng",
				"patterns": ["still water", "safe first", "calm"],
			},
		},
		{
			"rule_id": "r_persona_an_cheng_kw_ja_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "ja",
				"character_id": "an_cheng",
				"patterns": ["澄安", "安全", "冷静"],
			},
		},
		{
			"rule_id": "r_persona_yuan_xi_kw_zh_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "zh",
				"character_id": "yuan_xi",
				"patterns": ["渊掌", "海底", "河底"],
			},
		},
		{
			"rule_id": "r_persona_yuan_xi_kw_en_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "en",
				"character_id": "yuan_xi",
				"patterns": ["abyss palm", "last draw", "river bottom"],
			},
		},
		{
			"rule_id": "r_persona_yuan_xi_kw_ja_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "ja",
				"character_id": "yuan_xi",
				"patterns": ["淵掌", "海底", "河底"],
			},
		},
		{
			"rule_id": "r_persona_ji_shu_kw_zh_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "zh",
				"character_id": "ji_shu",
				"patterns": ["算枢", "概率", "圣裁"],
			},
		},
		{
			"rule_id": "r_persona_ji_shu_kw_en_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "en",
				"character_id": "ji_shu",
				"patterns": ["pivot math", "odds", "verdict"],
			},
		},
		{
			"rule_id": "r_persona_ji_shu_kw_ja_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "ja",
				"character_id": "ji_shu",
				"patterns": ["算枢", "確率", "裁決"],
			},
		},
		{
			"rule_id": "r_persona_xian_shi_kw_zh_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "zh",
				"character_id": "xian_shi",
				"patterns": ["先示", "四席", "下一张"],
			},
		},
		{
			"rule_id": "r_persona_xian_shi_kw_en_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "en",
				"character_id": "xian_shi",
				"patterns": ["first reveal", "four seats", "next tile"],
			},
		},
		{
			"rule_id": "r_persona_xian_shi_kw_ja_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "ja",
				"character_id": "xian_shi",
				"patterns": ["先示", "四家", "次の牌"],
			},
		},
		{
			"rule_id": "r_persona_bao_luo_kw_zh_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "zh",
				"character_id": "bao_luo",
				"patterns": ["宝络", "红线", "赤宝"],
			},
		},
		{
			"rule_id": "r_persona_bao_luo_kw_en_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "en",
				"character_id": "bao_luo",
				"patterns": ["treasure thread", "red string", "red dora"],
			},
		},
		{
			"rule_id": "r_persona_bao_luo_kw_ja_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "ja",
				"character_id": "bao_luo",
				"patterns": ["宝絡", "赤い糸", "赤ドラ"],
			},
		},
		{
			"rule_id": "r_persona_ying_li_kw_zh_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "zh",
				"character_id": "ying_li",
				"patterns": ["影立", "立直", "消影"],
			},
		},
		{
			"rule_id": "r_persona_ying_li_kw_en_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "en",
				"character_id": "ying_li",
				"patterns": ["shadow stand", "riichi", "vanish"],
			},
		},
		{
			"rule_id": "r_persona_ying_li_kw_ja_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "ja",
				"character_id": "ying_li",
				"patterns": ["影立", "リーチ", "消影"],
			},
		},
		{
			"rule_id": "r_persona_ju_jin_kw_zh_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "zh",
				"character_id": "ju_jin",
				"patterns": ["局进", "阶升", "累加"],
			},
		},
		{
			"rule_id": "r_persona_ju_jin_kw_en_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "en",
				"character_id": "ju_jin",
				"patterns": ["table climb", "step up", "stacking"],
			},
		},
		{
			"rule_id": "r_persona_ju_jin_kw_ja_01",
			"component": "persona",
			"points": 200,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_KEYWORD",
				"language": "ja",
				"character_id": "ju_jin",
				"patterns": ["局進", "階昇", "累加"],
			},
		},
	]

static func _expression_rules_table() -> Array:
	return [
		{
			"rule_id": "r_expr_generic_zh_01",
			"component": "expression",
			"points": 180,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "EXPRESSION",
				"language": "zh",
				"patterns": ["必胜", "翻盘", "燃烧"],
			},
		},
		{
			"rule_id": "r_expr_generic_en_01",
			"component": "expression",
			"points": 180,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "EXPRESSION",
				"language": "en",
				"patterns": ["comeback", "must win", "burn"],
			},
		},
		{
			"rule_id": "r_expr_generic_ja_01",
			"component": "expression",
			"points": 180,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "EXPRESSION",
				"language": "ja",
				"patterns": ["必勝", "逆転", "燃え"],
			},
		},
	]

static func _public_context_rules_table() -> Array:
	return [
		{
			"rule_id": "r_ctx_riichi_open_01",
			"component": "public_context",
			"points": 120,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PUBLIC_CONTEXT",
				"context_tag": "CTX_RIICHI_OPEN",
			},
		},
		{
			"rule_id": "r_ctx_meld_seen_01",
			"component": "public_context",
			"points": 100,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PUBLIC_CONTEXT",
				"context_tag": "CTX_MELD_SEEN",
			},
		},
		{
			"rule_id": "r_ctx_seat_leading_01",
			"component": "public_context",
			"points": 110,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PUBLIC_CONTEXT",
				"context_tag": "CTX_SEAT_LEADING",
			},
		},
		{
			"rule_id": "r_ctx_seat_trailing_01",
			"component": "public_context",
			"points": 110,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PUBLIC_CONTEXT",
				"context_tag": "CTX_SEAT_TRAILING",
			},
		},
		{
			"rule_id": "r_ctx_window_late_01",
			"component": "public_context",
			"points": 100,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PUBLIC_CONTEXT",
				"context_tag": "CTX_WINDOW_LATE",
			},
		},
		{
			"rule_id": "r_ctx_dora_revealed_01",
			"component": "public_context",
			"points": 115,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PUBLIC_CONTEXT",
				"context_tag": "CTX_DORA_REVEALED",
			},
		},
		{
			"rule_id": "r_ctx_is_dealer_01",
			"component": "public_context",
			"points": 90,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PUBLIC_CONTEXT",
				"context_tag": "CTX_IS_DEALER",
			},
		},
		{
			"rule_id": "r_ctx_ron_winner_01",
			"component": "public_context",
			"points": 130,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PUBLIC_CONTEXT",
				"context_tag": "CTX_RON_WINNER",
			},
		},
		{
			"rule_id": "r_ctx_tsumo_winner_01",
			"component": "public_context",
			"points": 130,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PUBLIC_CONTEXT",
				"context_tag": "CTX_TSUMO_WINNER",
			},
		},
		{
			"rule_id": "r_ctx_deal_in_loser_01",
			"component": "public_context",
			"points": 100,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PUBLIC_CONTEXT",
				"context_tag": "CTX_DEAL_IN_LOSER",
			},
		},
	]

static func _item_table() -> Dictionary:
	return {
		"iron_shield_v1": {
			"item_id": "iron_shield_v1",
			"priority": 40,
			"specificity": 55,
			"tags": ["CALM", "DEFENSE"],
			"public_context_tags": ["CTX_SEAT_TRAILING", "CTX_WINDOW_LATE"],
			"patterns": {
				"zh": ["铁盾", "抵消荣胡", "防御"],
				"en": ["iron shield", "cancel deal-in", "defense"],
				"ja": ["鉄盾", "放銃無効", "防御"],
			},
			"rules": [
				{
					"rule_id": "r_item_iron_shield_tag_01",
					"item_id": "iron_shield_v1",
					"component": "item_tag",
					"points": 140,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "iron_shield_v1",
						"tag": "CALM",
						"patterns": {
							"zh": ["铁盾", "抵消荣胡", "防御"],
							"en": ["iron shield", "cancel deal-in", "defense"],
							"ja": ["鉄盾", "放銃無効", "防御"],
						},
					},
				},
			],
		},
		"wall_peek_v1": {
			"item_id": "wall_peek_v1",
			"priority": 45,
			"specificity": 60,
			"tags": ["CUNNING", "INFO"],
			"public_context_tags": ["CTX_WINDOW_LATE"],
			"patterns": {
				"zh": ["千里眼", "牌墙", "透视"],
				"en": ["wall peek", "wall top", "info"],
				"ja": ["千里眼", "山", "透視"],
			},
			"rules": [
				{
					"rule_id": "r_item_wall_peek_tag_01",
					"item_id": "wall_peek_v1",
					"component": "item_tag",
					"points": 130,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "wall_peek_v1",
						"tag": "CUNNING",
						"patterns": {
							"zh": ["千里眼", "牌墙", "透视"],
							"en": ["wall peek", "wall top", "info"],
							"ja": ["千里眼", "山", "透視"],
						},
					},
				},
			],
		},
		"double_payout_v1": {
			"item_id": "double_payout_v1",
			"priority": 70,
			"specificity": 75,
			"tags": ["DOMINATION", "SCORE"],
			"public_context_tags": ["CTX_RIICHI_OPEN", "CTX_SEAT_LEADING"],
			"patterns": {
				"zh": ["倍率券", "番数翻倍", "碾压"],
				"en": ["double payout", "double han", "crush"],
				"ja": ["倍率券", "翻数2倍", "圧倒"],
			},
			"rules": [
				{
					"rule_id": "r_item_double_payout_tag_01",
					"item_id": "double_payout_v1",
					"component": "item_tag",
					"points": 150,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "double_payout_v1",
						"tag": "DOMINATION",
						"patterns": {
							"zh": ["倍率券", "番数翻倍", "碾压"],
							"en": ["double payout", "double han", "crush"],
							"ja": ["倍率券", "翻数2倍", "圧倒"],
						},
					},
				},
			],
		},
		"dora_charm_v1": {
			"item_id": "dora_charm_v1",
			"priority": 65,
			"specificity": 70,
			"tags": ["PASSION", "DORA"],
			"public_context_tags": ["CTX_DORA_REVEALED"],
			"patterns": {
				"zh": ["宝牌护符", "额外宝牌", "强运"],
				"en": ["dora charm", "extra dora", "luck"],
				"ja": ["ドラ護符", "追加ドラ", "強運"],
			},
			"rules": [
				{
					"rule_id": "r_item_dora_charm_tag_01",
					"item_id": "dora_charm_v1",
					"component": "item_tag",
					"points": 145,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "dora_charm_v1",
						"tag": "PASSION",
						"patterns": {
							"zh": ["宝牌护符", "额外宝牌", "强运"],
							"en": ["dora charm", "extra dora", "luck"],
							"ja": ["ドラ護符", "追加ドラ", "強運"],
						},
					},
				},
			],
		},
		"wall_collapse_v1": {
			"item_id": "wall_collapse_v1",
			"priority": 50,
			"specificity": 45,
			"tags": ["DOMINATION", "TEMPO"],
			"public_context_tags": ["CTX_WINDOW_LATE"],
			"patterns": {
				"zh": ["牌墙崩塌", "缩墙", "节奏"],
				"en": ["wall collapse", "short wall", "tempo"],
				"ja": ["牌山崩壊", "山短縮", "テンポ"],
			},
			"rules": [
				{
					"rule_id": "r_item_wall_collapse_tag_01",
					"item_id": "wall_collapse_v1",
					"component": "item_tag",
					"points": 125,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "wall_collapse_v1",
						"tag": "DOMINATION",
						"patterns": {
							"zh": ["牌墙崩塌", "缩墙", "节奏"],
							"en": ["wall collapse", "short wall", "tempo"],
							"ja": ["牌山崩壊", "山短縮", "テンポ"],
						},
					},
				},
			],
		},
		"dora_flip_v1": {
			"item_id": "dora_flip_v1",
			"priority": 55,
			"specificity": 65,
			"tags": ["MYSTIC", "DORA"],
			"public_context_tags": ["CTX_DORA_REVEALED"],
			"patterns": {
				"zh": ["翻宝牌", "额外指示", "神秘"],
				"en": ["dora flip", "extra indicator", "mystic"],
				"ja": ["ドラめくり", "表示追加", "神秘"],
			},
			"rules": [
				{
					"rule_id": "r_item_dora_flip_tag_01",
					"item_id": "dora_flip_v1",
					"component": "item_tag",
					"points": 135,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "dora_flip_v1",
						"tag": "MYSTIC",
						"patterns": {
							"zh": ["翻宝牌", "额外指示", "神秘"],
							"en": ["dora flip", "extra indicator", "mystic"],
							"ja": ["ドラめくり", "表示追加", "神秘"],
						},
					},
				},
			],
		},
		"seat_swap_v1": {
			"item_id": "seat_swap_v1",
			"priority": 35,
			"specificity": 40,
			"tags": ["CUNNING", "TEMPO"],
			"public_context_tags": ["CTX_MELD_SEEN"],
			"patterns": {
				"zh": ["换座", "座位", "打乱"],
				"en": ["seat swap", "rotate seats", "disrupt"],
				"ja": ["席替え", "座席", "攪乱"],
			},
			"rules": [
				{
					"rule_id": "r_item_seat_swap_tag_01",
					"item_id": "seat_swap_v1",
					"component": "item_tag",
					"points": 120,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "seat_swap_v1",
						"tag": "CUNNING",
						"patterns": {
							"zh": ["换座", "座位", "打乱"],
							"en": ["seat swap", "rotate seats", "disrupt"],
							"ja": ["席替え", "座席", "攪乱"],
						},
					},
				},
			],
		},
		"furiten_bomb_v1": {
			"item_id": "furiten_bomb_v1",
			"priority": 75,
			"specificity": 80,
			"tags": ["CUNNING", "DISRUPT"],
			"public_context_tags": ["CTX_RIICHI_OPEN"],
			"patterns": {
				"zh": ["振听炸弹", "取消荣胡", "陷阱"],
				"en": ["furiten bomb", "block ron", "trap"],
				"ja": ["振聴爆弾", "ロン無効", "罠"],
			},
			"rules": [
				{
					"rule_id": "r_item_furiten_bomb_tag_01",
					"item_id": "furiten_bomb_v1",
					"component": "item_tag",
					"points": 155,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "furiten_bomb_v1",
						"tag": "CUNNING",
						"patterns": {
							"zh": ["振听炸弹", "取消荣胡", "陷阱"],
							"en": ["furiten bomb", "block ron", "trap"],
							"ja": ["振聴爆弾", "ロン無効", "罠"],
						},
					},
				},
			],
		},
		"point_shield_v1": {
			"item_id": "point_shield_v1",
			"priority": 48,
			"specificity": 58,
			"tags": ["CALM", "DEFENSE"],
			"public_context_tags": ["CTX_SEAT_TRAILING"],
			"patterns": {
				"zh": ["点棒护盾", "偷回点数", "防守"],
				"en": ["point shield", "claw back", "guard"],
				"ja": ["点棒シールド", "回収", "守り"],
			},
			"rules": [
				{
					"rule_id": "r_item_point_shield_tag_01",
					"item_id": "point_shield_v1",
					"component": "item_tag",
					"points": 140,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "point_shield_v1",
						"tag": "CALM",
						"patterns": {
							"zh": ["点棒护盾", "偷回点数", "防守"],
							"en": ["point shield", "claw back", "guard"],
							"ja": ["点棒シールド", "回収", "守り"],
						},
					},
				},
			],
		},
		"tsubame_v1": {
			"item_id": "tsubame_v1",
			"priority": 42,
			"specificity": 50,
			"tags": ["PASSION", "TEMPO"],
			"public_context_tags": ["CTX_WINDOW_LATE"],
			"patterns": {
				"zh": ["燕返", "重洗手牌", "再起"],
				"en": ["swallow return", "reshuffle hand", "reset"],
				"ja": ["燕返し", "手牌再配", "仕切り直し"],
			},
			"rules": [
				{
					"rule_id": "r_item_tsubame_tag_01",
					"item_id": "tsubame_v1",
					"component": "item_tag",
					"points": 125,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "tsubame_v1",
						"tag": "PASSION",
						"patterns": {
							"zh": ["燕返", "重洗手牌", "再起"],
							"en": ["swallow return", "reshuffle hand", "reset"],
							"ja": ["燕返し", "手牌再配", "仕切り直し"],
						},
					},
				},
			],
		},
		"relic_lucky_cat_v1": {
			"item_id": "relic_lucky_cat_v1",
			"priority": 52,
			"specificity": 55,
			"tags": ["PASSION", "DORA"],
			"public_context_tags": ["CTX_DORA_REVEALED"],
			"patterns": {
				"zh": ["招财猫", "胡牌宝牌", "运气"],
				"en": ["lucky cat", "win dora", "fortune"],
				"ja": ["招き猫", "和了ドラ", "運"],
			},
			"rules": [
				{
					"rule_id": "r_item_relic_lucky_cat_tag_01",
					"item_id": "relic_lucky_cat_v1",
					"component": "item_tag",
					"points": 130,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "relic_lucky_cat_v1",
						"tag": "PASSION",
						"patterns": {
							"zh": ["招财猫", "胡牌宝牌", "运气"],
							"en": ["lucky cat", "win dora", "fortune"],
							"ja": ["招き猫", "和了ドラ", "運"],
						},
					},
				},
			],
		},
		"relic_iron_will_v1": {
			"item_id": "relic_iron_will_v1",
			"priority": 50,
			"specificity": 52,
			"tags": ["CALM", "DEFENSE"],
			"public_context_tags": ["CTX_SEAT_TRAILING"],
			"patterns": {
				"zh": ["铁壁意志", "减番", "坚韧"],
				"en": ["iron will", "reduce han", "tough"],
				"ja": ["鉄壁の意志", "1翻減少", "粘り"],
			},
			"rules": [
				{
					"rule_id": "r_item_relic_iron_will_tag_01",
					"item_id": "relic_iron_will_v1",
					"component": "item_tag",
					"points": 135,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "relic_iron_will_v1",
						"tag": "CALM",
						"patterns": {
							"zh": ["铁壁意志", "减番", "坚韧"],
							"en": ["iron will", "reduce han", "tough"],
							"ja": ["鉄壁の意志", "1翻減少", "粘り"],
						},
					},
				},
			],
		},
		"relic_soul_mirror_v1": {
			"item_id": "relic_soul_mirror_v1",
			"priority": 68,
			"specificity": 72,
			"tags": ["CUNNING", "SCORE"],
			"public_context_tags": ["CTX_MELD_SEEN"],
			"patterns": {
				"zh": ["魂镜", "偷分", "镜像"],
				"en": ["soul mirror", "steal score", "mirror"],
				"ja": ["魂鏡", "点奪取", "鏡"],
			},
			"rules": [
				{
					"rule_id": "r_item_relic_soul_mirror_tag_01",
					"item_id": "relic_soul_mirror_v1",
					"component": "item_tag",
					"points": 145,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "relic_soul_mirror_v1",
						"tag": "CUNNING",
						"patterns": {
							"zh": ["魂镜", "偷分", "镜像"],
							"en": ["soul mirror", "steal score", "mirror"],
							"ja": ["魂鏡", "点奪取", "鏡"],
						},
					},
				},
			],
		},
		"relic_wall_eye_v1": {
			"item_id": "relic_wall_eye_v1",
			"priority": 72,
			"specificity": 78,
			"tags": ["MYSTIC", "INFO"],
			"public_context_tags": ["CTX_WINDOW_LATE"],
			"patterns": {
				"zh": ["墙眼", "预知摸牌", "信息"],
				"en": ["wall eye", "next tile", "info"],
				"ja": ["壁の目", "次牌予見", "情報"],
			},
			"rules": [
				{
					"rule_id": "r_item_relic_wall_eye_tag_01",
					"item_id": "relic_wall_eye_v1",
					"component": "item_tag",
					"points": 150,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "relic_wall_eye_v1",
						"tag": "MYSTIC",
						"patterns": {
							"zh": ["墙眼", "预知摸牌", "信息"],
							"en": ["wall eye", "next tile", "info"],
							"ja": ["壁の目", "次牌予見", "情報"],
						},
					},
				},
			],
		},
		"relic_red_string_v1": {
			"item_id": "relic_red_string_v1",
			"priority": 58,
			"specificity": 68,
			"tags": ["PASSION", "DORA"],
			"public_context_tags": ["CTX_DORA_REVEALED"],
			"patterns": {
				"zh": ["红线", "赤宝", "缠运"],
				"en": ["red string", "red dora", "bind"],
				"ja": ["赤い糸", "赤ドラ", "縁"],
			},
			"rules": [
				{
					"rule_id": "r_item_relic_red_string_tag_01",
					"item_id": "relic_red_string_v1",
					"component": "item_tag",
					"points": 140,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "relic_red_string_v1",
						"tag": "PASSION",
						"patterns": {
							"zh": ["红线", "赤宝", "缠运"],
							"en": ["red string", "red dora", "bind"],
							"ja": ["赤い糸", "赤ドラ", "縁"],
						},
					},
				},
			],
		},
		"relic_dragon_seal_v1": {
			"item_id": "relic_dragon_seal_v1",
			"priority": 60,
			"specificity": 62,
			"tags": ["DOMINATION", "SCORE"],
			"public_context_tags": ["CTX_SEAT_LEADING"],
			"patterns": {
				"zh": ["龙印", "三元", "加番"],
				"en": ["dragon seal", "dragons", "extra han"],
				"ja": ["龍印", "三元", "1翻追加"],
			},
			"rules": [
				{
					"rule_id": "r_item_relic_dragon_seal_tag_01",
					"item_id": "relic_dragon_seal_v1",
					"component": "item_tag",
					"points": 140,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "relic_dragon_seal_v1",
						"tag": "DOMINATION",
						"patterns": {
							"zh": ["龙印", "三元", "加番"],
							"en": ["dragon seal", "dragons", "extra han"],
							"ja": ["龍印", "三元", "1翻追加"],
						},
					},
				},
			],
		},
		"relic_wind_charm_v1": {
			"item_id": "relic_wind_charm_v1",
			"priority": 44,
			"specificity": 48,
			"tags": ["MYSTIC", "TEMPO"],
			"public_context_tags": ["CTX_RIICHI_OPEN"],
			"patterns": {
				"zh": ["风铃", "风役", "节奏"],
				"en": ["wind charm", "wind yaku", "tempo"],
				"ja": ["風鈴", "風役", "テンポ"],
			},
			"rules": [
				{
					"rule_id": "r_item_relic_wind_charm_tag_01",
					"item_id": "relic_wind_charm_v1",
					"component": "item_tag",
					"points": 125,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "relic_wind_charm_v1",
						"tag": "MYSTIC",
						"patterns": {
							"zh": ["风铃", "风役", "节奏"],
							"en": ["wind charm", "wind yaku", "tempo"],
							"ja": ["風鈴", "風役", "テンポ"],
						},
					},
				},
			],
		},
		"relic_speed_demon_v1": {
			"item_id": "relic_speed_demon_v1",
			"priority": 66,
			"specificity": 70,
			"tags": ["DOMINATION", "TEMPO"],
			"public_context_tags": ["CTX_WINDOW_LATE"],
			"patterns": {
				"zh": ["速攻鬼", "早巡", "压迫"],
				"en": ["speed demon", "early turns", "pressure"],
				"ja": ["速攻鬼", "序盤", "圧"],
			},
			"rules": [
				{
					"rule_id": "r_item_relic_speed_demon_tag_01",
					"item_id": "relic_speed_demon_v1",
					"component": "item_tag",
					"points": 145,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "relic_speed_demon_v1",
						"tag": "DOMINATION",
						"patterns": {
							"zh": ["速攻鬼", "早巡", "压迫"],
							"en": ["speed demon", "early turns", "pressure"],
							"ja": ["速攻鬼", "序盤", "圧"],
						},
					},
				},
			],
		},
		"relic_patience_stone_v1": {
			"item_id": "relic_patience_stone_v1",
			"priority": 38,
			"specificity": 42,
			"tags": ["CALM", "ENDURANCE"],
			"public_context_tags": ["CTX_WINDOW_LATE"],
			"patterns": {
				"zh": ["忍石", "流局得点", "忍耐"],
				"en": ["patience stone", "draw bonus", "endure"],
				"ja": ["忍石", "流局加点", "忍耐"],
			},
			"rules": [
				{
					"rule_id": "r_item_relic_patience_stone_tag_01",
					"item_id": "relic_patience_stone_v1",
					"component": "item_tag",
					"points": 130,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "relic_patience_stone_v1",
						"tag": "CALM",
						"patterns": {
							"zh": ["忍石", "流局得点", "忍耐"],
							"en": ["patience stone", "draw bonus", "endure"],
							"ja": ["忍石", "流局加点", "忍耐"],
						},
					},
				},
			],
		},
		"relic_han_crystal_v1": {
			"item_id": "relic_han_crystal_v1",
			"priority": 74,
			"specificity": 76,
			"tags": ["PASSION", "SCORE"],
			"public_context_tags": ["CTX_RIICHI_OPEN"],
			"patterns": {
				"zh": ["番水晶", "立直加番", "爆发"],
				"en": ["han crystal", "riichi han", "burst"],
				"ja": ["翻数水晶", "リーチ時1翻追加", "爆発"],
			},
			"rules": [
				{
					"rule_id": "r_item_relic_han_crystal_tag_01",
					"item_id": "relic_han_crystal_v1",
					"component": "item_tag",
					"points": 150,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "relic_han_crystal_v1",
						"tag": "PASSION",
						"patterns": {
							"zh": ["番水晶", "立直加番", "爆发"],
							"en": ["han crystal", "riichi han", "burst"],
							"ja": ["翻数水晶", "リーチ時1翻追加", "爆発"],
						},
					},
				},
			],
		},
		"relic_comeback_crown_v1": {
			"item_id": "relic_comeback_crown_v1",
			"priority": 80,
			"specificity": 85,
			"tags": ["DOMINATION", "SCORE"],
			"public_context_tags": ["CTX_SEAT_TRAILING"],
			"patterns": {
				"zh": ["逆转王冠", "最低分加番", "翻盘"],
				"en": ["comeback crown", "last place boost", "upset"],
				"ja": ["逆転王冠", "最下位補正", "大逆転"],
			},
			"rules": [
				{
					"rule_id": "r_item_relic_comeback_crown_tag_01",
					"item_id": "relic_comeback_crown_v1",
					"component": "item_tag",
					"points": 160,
					"cap": 1000,
					"once_per_window_seat": true,
					"match": {
						"kind": "ITEM_TAG",
						"item_id": "relic_comeback_crown_v1",
						"tag": "DOMINATION",
						"patterns": {
							"zh": ["逆转王冠", "最低分加番", "翻盘"],
							"en": ["comeback crown", "last place boost", "upset"],
							"ja": ["逆転王冠", "最下位補正", "大逆転"],
						},
					},
				},
			],
		},
	}
