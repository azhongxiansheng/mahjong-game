extends GutTest

# E5-01 / #249 P2-5：schema 深度校验 + 非自证真源断言。

const RULE_VERSION := "trash_talk_rules_v1"
const SCORE_ORDER := ["persona", "item_tag", "public_context", "expression"]
const LANGS := ["zh", "en", "ja"]
const ALLOWED_CTX := [
	"CTX_RIICHI_OPEN", "CTX_MELD_SEEN", "CTX_SEAT_LEADING",
	"CTX_SEAT_TRAILING", "CTX_WINDOW_LATE", "CTX_DORA_REVEALED",
	"CTX_IS_DEALER", "CTX_RON_WINNER", "CTX_TSUMO_WINNER", "CTX_DEAL_IN_LOSER",
]


func test_catalog_class_and_rule_version() -> void:
	assert_true(_catalog_script_loads())
	assert_eq(TrashTalkRuleCatalog.rule_version(), RULE_VERSION)
	assert_eq(TrashTalkRuleCatalog.score_component_order(), SCORE_ORDER)


func test_score_components_are_four_integer_fields() -> void:
	var order: Array = TrashTalkRuleCatalog.score_component_order()
	assert_eq(order.size(), 4)
	for component_name in order:
		assert_true(SCORE_ORDER.has(component_name))


func test_validate_schema_ok() -> void:
	var result: Dictionary = TrashTalkRuleCatalog.validate_schema()
	assert_true(result.get("ok", false), "schema 必须通过: %s" % str(result.get("errors", [])))
	assert_eq(result.get("errors", []).size(), 0)


func test_every_rule_has_stable_id_match_kind_and_once() -> void:
	var seen := {}
	for rule in TrashTalkRuleCatalog.all_rules():
		var rid: String = String(rule.get("rule_id", ""))
		assert_false(rid.is_empty())
		assert_false(seen.has(rid), "rule_id 重复 %s" % rid)
		seen[rid] = true
		assert_true(rule.get("once_per_window_seat", false))
		var component: String = String(rule.get("component", ""))
		assert_true(SCORE_ORDER.has(component))
		var points: int = int(rule.get("points", -1))
		var cap: int = int(rule.get("cap", -1))
		assert_true(points >= 0 and points <= 1000)
		assert_true(cap >= 0 and cap <= 1000 and points <= cap)
		var match: Dictionary = rule.get("match", {})
		var kind := String(match.get("kind", ""))
		assert_true(
			["PERSONA_KEYWORD", "PERSONA_TEMPLATE", "ITEM_TAG", "PUBLIC_CONTEXT", "EXPRESSION"].has(kind),
			"非法 kind %s @ %s" % [kind, rid]
		)
		if kind == "ITEM_TAG":
			assert_true(TrashTalkRuleCatalog.grantable_item_ids().has(String(match.get("item_id", ""))))
			var mp: Dictionary = match.get("patterns", {})
			for lang in LANGS:
				assert_true(mp.has(lang) and mp[lang].size() > 0)
		if kind == "PUBLIC_CONTEXT":
			assert_true(ALLOWED_CTX.has(String(match.get("context_tag", ""))))
		if kind in ["PERSONA_KEYWORD", "PERSONA_TEMPLATE", "EXPRESSION"]:
			assert_true(LANGS.has(String(match.get("language", ""))))
			assert_true(match.get("patterns") is Array and match["patterns"].size() > 0)


func test_persona_template_rules_present_in_catalog() -> void:
	var found := 0
	for rule in TrashTalkRuleCatalog.all_rules():
		if String(rule.get("match", {}).get("kind", "")) == "PERSONA_TEMPLATE":
			found += 1
			var rid := String(rule.get("rule_id", ""))
			assert_true(TrashTalkRuleCatalog.has_rule_id(rid))
			assert_true(rid.contains("_tpl_"))
	assert_true(found >= 36, "PERSONA_TEMPLATE 至少 12×3")


func test_accumulation_order_fixed_by_rule_version() -> void:
	var meta: Dictionary = TrashTalkRuleCatalog.version_meta()
	assert_eq(String(meta.get("rule_version", "")), RULE_VERSION)
	assert_eq(meta.get("score_component_order", []), SCORE_ORDER)
	assert_eq(int(meta.get("component_min", -1)), 0)
	assert_eq(int(meta.get("component_max", -1)), 1000)


func test_true_source_sets_independent_of_validate_schema() -> void:
	# 不调用 validate_schema，直接对照 CharacterPool / LobbyCodexCatalog / 枚举常量
	var pool: Array = []
	for c in CharacterPool.all():
		pool.append(String(c.id))
	pool.sort()
	var persona_ids: Array = []
	for cid in TrashTalkRuleCatalog.character_ids():
		persona_ids.append(cid)
		var p: Dictionary = TrashTalkRuleCatalog.character_persona(StringName(cid))
		assert_false(p.is_empty())
		assert_not_null(CharacterPool.find(StringName(cid)))
	persona_ids.sort()
	assert_eq(persona_ids, pool)

	var codex_ids: Array = []
	for row in LobbyCodexCatalog.new().items():
		codex_ids.append(String(row.get("id", "")))
	codex_ids.sort()
	var grant: Array = TrashTalkRuleCatalog.grantable_item_ids()
	var grant_sorted: Array = grant.duplicate()
	grant_sorted.sort()
	assert_eq(grant_sorted, codex_ids)
	assert_eq(grant_sorted.size(), 21)

	var catalog_ctx: Array = []
	for t in TrashTalkRuleCatalog.PUBLIC_CONTEXT_TAGS:
		catalog_ctx.append(String(t))
	catalog_ctx.sort()
	var expected_ctx: Array = ALLOWED_CTX.duplicate()
	expected_ctx.sort()
	assert_eq(catalog_ctx, expected_ctx)

	# 每角色每语言：通用 + 情境
	for cid in pool:
		var ai: Dictionary = TrashTalkRuleCatalog.character_persona(StringName(cid)).get("ai_templates", {})
		for lang in LANGS:
			var has_g := false
			var has_c := false
			for line in ai[lang]:
				if line.get("context_tags", []).is_empty():
					has_g = true
				else:
					has_c = true
			assert_true(has_g and has_c, "%s/%s 通用/情境" % [cid, lang])

	# 21 道具 priority/specificity/patterns 真源字段
	for item_id in grant_sorted:
		var def: Dictionary = TrashTalkRuleCatalog.item_def(StringName(item_id))
		assert_true(def.has("priority") and typeof(def["priority"]) == TYPE_INT)
		assert_true(def.has("specificity") and typeof(def["specificity"]) == TYPE_INT)
		var pats: Dictionary = def.get("patterns", {})
		for lang in LANGS:
			assert_true(pats.has(lang) and pats[lang].size() > 0)


func _catalog_script_loads() -> bool:
	var script_path := "res://meta/trash_talk_rule_catalog.gd"
	if not ResourceLoader.exists(script_path):
		return false
	return load(script_path) != null
