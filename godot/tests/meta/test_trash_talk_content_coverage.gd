extends GutTest

# E5-01 / #249：12 角色 / 21 道具 / 五 affinity / 三语 / AI；真源反查。

const LANGS := ["zh", "en", "ja"]
const AFFINITIES := ["DOMINATION", "CALM", "CUNNING", "PASSION", "MYSTIC"]
const MIN_KEYWORDS := 6
const MIN_AI_LINES := 3
const MIN_HUMAN_TEMPLATES := 1
const ALLOWED_CTX := [
	"CTX_RIICHI_OPEN", "CTX_MELD_SEEN", "CTX_SEAT_LEADING",
	"CTX_SEAT_TRAILING", "CTX_WINDOW_LATE", "CTX_DORA_REVEALED",
]


func test_exactly_twelve_characters_match_character_pool() -> void:
	var pool_ids: Array = []
	for c in CharacterPool.all():
		pool_ids.append(String(c.id))
	pool_ids.sort()
	var cat_ids: Array = TrashTalkRuleCatalog.character_ids()
	var sorted_cat: Array = cat_ids.duplicate()
	sorted_cat.sort()
	assert_eq(sorted_cat.size(), 12)
	assert_eq(sorted_cat, pool_ids)


func test_affinity_primary_secondary_match_character_pool() -> void:
	for c in CharacterPool.all():
		var persona: Dictionary = TrashTalkRuleCatalog.character_persona(c.id)
		assert_false(persona.is_empty())
		assert_eq(String(persona.get("affinity_primary", "")), String(c.affinity_primary))
		assert_eq(String(persona.get("affinity_secondary", "")), String(c.affinity_secondary))
		assert_true(AFFINITIES.has(String(c.affinity_primary)))
		assert_true(AFFINITIES.has(String(c.affinity_secondary)))


func test_five_affinity_enum_only_no_multipliers() -> void:
	var keys: Array = Character.affinity_keys()
	var as_str: Array = []
	for k in keys:
		as_str.append(String(k))
	assert_eq(as_str, AFFINITIES)
	var src: String = load("res://meta/trash_talk_rule_catalog.gd").source_code
	assert_false(src.contains("skill_effect_multiplier"))
	assert_false(src.contains("total_momentum"))


func test_languages_keywords_templates_and_ai_context_coverage() -> void:
	for cid in TrashTalkRuleCatalog.character_ids():
		var persona: Dictionary = TrashTalkRuleCatalog.character_persona(StringName(cid))
		var keywords: Dictionary = persona.get("keywords", {})
		var human: Dictionary = persona.get("human_templates", {})
		var ai: Dictionary = persona.get("ai_templates", {})
		for lang in LANGS:
			assert_true(keywords.has(lang))
			assert_true(human.has(lang))
			assert_true(ai.has(lang))
			assert_true(keywords[lang].size() >= MIN_KEYWORDS)
			assert_true(human[lang].size() >= MIN_HUMAN_TEMPLATES)
			var lines: Array = ai[lang]
			assert_true(lines.size() >= MIN_AI_LINES)
			var has_generic := false
			var has_ctx := false
			for line in lines:
				assert_false(String(line.get("line_id", "")).is_empty())
				assert_false(String(line.get("text", "")).strip_edges().is_empty())
				var tags: Array = line.get("context_tags", [])
				if tags.is_empty():
					has_generic = true
				else:
					has_ctx = true
					for tag in tags:
						assert_true(ALLOWED_CTX.has(String(tag)),
							"非法 context_tag %s @ %s" % [tag, line.get("line_id")])
			assert_true(has_generic, "%s/%s 须有通用人设模板" % [cid, lang])
			assert_true(has_ctx, "%s/%s 须有公开情境模板" % [cid, lang])


func test_grantable_items_match_lobby_codex_catalog_exactly() -> void:
	var codex := LobbyCodexCatalog.new()
	var expected: Array = []
	for row in codex.items():
		expected.append(String(row.get("id", "")))
	expected.sort()
	var actual: Array = TrashTalkRuleCatalog.grantable_item_ids()
	var sorted_actual: Array = actual.duplicate()
	sorted_actual.sort()
	assert_eq(sorted_actual.size(), 21)
	assert_eq(sorted_actual, expected)
	for forbidden in ["hp_potion_v1", "gold_doubler_v1", "relic_pity_breaker_v1"]:
		assert_false(sorted_actual.has(forbidden))


func test_each_item_has_priority_specificity_patterns_tags_rules() -> void:
	var rule_ids := {}
	for item_id in TrashTalkRuleCatalog.grantable_item_ids():
		var def: Dictionary = TrashTalkRuleCatalog.item_def(StringName(item_id))
		assert_false(def.is_empty(), "缺道具: %s" % item_id)
		assert_false(def.has("owner_character_id"))
		assert_typeof(def.get("priority"), TYPE_INT)
		assert_typeof(def.get("specificity"), TYPE_INT)
		var pri: int = def["priority"]
		var spec: int = def["specificity"]
		assert_true(pri >= 1 and pri <= 100, "priority 范围 %s" % item_id)
		assert_true(spec >= 1 and spec <= 100, "specificity 范围 %s" % item_id)
		var tags: Array = def.get("tags", [])
		assert_true(tags.size() >= 1)
		var ctx: Array = def.get("public_context_tags", [])
		assert_true(ctx.size() >= 1)
		for ct in ctx:
			assert_true(ALLOWED_CTX.has(String(ct)))
		var pats: Dictionary = def.get("patterns", {})
		for lang in LANGS:
			assert_true(pats.has(lang), "%s 缺 patterns.%s" % [item_id, lang])
			assert_true(pats[lang] is Array and pats[lang].size() > 0)
			for p in pats[lang]:
				assert_false(String(p).strip_edges().is_empty())
		var rules: Array = def.get("rules", [])
		assert_true(rules.size() >= 1)
		for r in rules:
			var rid: String = String(r.get("rule_id", ""))
			assert_false(rule_ids.has(rid))
			rule_ids[rid] = true
			assert_eq(String(r.get("item_id", "")), item_id)
			var match: Dictionary = r.get("match", {})
			assert_eq(String(match.get("kind", "")), "ITEM_TAG")
			assert_eq(String(match.get("item_id", "")), item_id)
			assert_false(String(match.get("tag", "")).is_empty())
			var mp: Dictionary = match.get("patterns", {})
			for lang2 in LANGS:
				assert_true(mp.has(lang2) and mp[lang2] is Array and mp[lang2].size() > 0,
					"rule 缺三语模式 %s/%s" % [rid, lang2])


func test_persona_rules_exist_and_unique() -> void:
	var seen := {}
	var tpl_count := 0
	for rule in TrashTalkRuleCatalog.persona_rules():
		var rid: String = String(rule.get("rule_id", ""))
		assert_false(rid.is_empty())
		assert_false(seen.has(rid))
		seen[rid] = true
		assert_true(["persona", "expression"].has(String(rule.get("component", ""))))
		var kind := String(rule.get("match", {}).get("kind", ""))
		if kind == "PERSONA_TEMPLATE":
			tpl_count += 1
			assert_true(TrashTalkRuleCatalog.has_rule_id(rid))
	# 12 角色 × 3 语 = 36 条真实 PERSONA_TEMPLATE
	assert_eq(tpl_count, 36, "必须存在可审阅的 PERSONA_TEMPLATE 生产规则")


func test_ai_line_ids_unique_globally() -> void:
	var seen := {}
	for cid in TrashTalkRuleCatalog.character_ids():
		var persona: Dictionary = TrashTalkRuleCatalog.character_persona(StringName(cid))
		var ai: Dictionary = persona.get("ai_templates", {})
		for lang in LANGS:
			for line in ai[lang]:
				var lid: String = String(line.get("line_id", ""))
				assert_false(seen.has(lid), "AI line_id 重复: %s" % lid)
				seen[lid] = true
