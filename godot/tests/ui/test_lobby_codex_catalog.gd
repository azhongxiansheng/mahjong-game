extends GutTest

# E1-05（#229）：资料馆只消费生产白名单，不得把 Run 字段重新暴露给大厅。

const CATALOG_SCRIPT_PATH := "res://ui/lobby/lobby_codex_catalog.gd"
const CHARACTER_KEYS := [
	"ability_description",
	"ability_name",
	"affinity_labels",
	"description",
	"display_name",
	"id",
	"portrait_path",
]
const ITEM_KEYS := [
	"category",
	"description",
	"display_name",
	"icon_path",
	"id",
	"rarity_label",
]
const RULE_KEYS := ["body", "id", "title"]
const YAKU_KEYS := [
	"category", "closed_han", "condition", "description", "display_name",
	"example", "id", "is_yakuman", "open_han", "yakuman_multiplier",
]
const FORBIDDEN_COPY := [
	"run", "章节", "boss", "hp", "金币", "gold", "商店", "抽卡", "营地", "战令",
	"旅途", "保底", "gacha", "语音音量", "座位静音", "举报", "自动禁言", "e6",
]


func _catalog() -> RefCounted:
	if not ResourceLoader.exists(CATALOG_SCRIPT_PATH):
		assert_true(false, "E1-05 必须提供大厅资料馆白名单数据源")
		return null
	var script := load(CATALOG_SCRIPT_PATH) as GDScript
	assert_not_null(script, "资料馆数据源必须可加载")
	if script == null:
		return null
	var catalog := script.new() as RefCounted
	assert_not_null(catalog)
	return catalog


func _sorted_keys(row: Dictionary) -> Array:
	var keys: Array = row.keys()
	keys.sort()
	return keys


func _sorted_strings(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(String(value))
	result.sort()
	return result


func _ability_by_id() -> Dictionary:
	var result := {}
	for ability in CardPool.all_abilities():
		result[ability.id] = ability
	return result


func _affinity_label(affinity: StringName) -> String:
	var enum_value: Variant = Momentum.Attribute.get(String(affinity))
	return String(Momentum.ATTRIBUTE_NAMES.get(enum_value, ""))


func test_character_catalog_covers_all_12_characters_with_whitelisted_fields() -> void:
	var catalog := _catalog()
	if catalog == null:
		return
	assert_true(catalog.has_method("characters"), "数据源须提供 characters()")
	if not catalog.has_method("characters"):
		return
	var rows: Array = catalog.call("characters")
	var characters: Array = CharacterPool.all()
	assert_eq(rows.size(), 12, "资料馆首发必须覆盖 12 名原创角色")
	assert_eq(rows.size(), characters.size(), "资料馆角色集合必须与 CharacterPool.all() 一致")

	var actual_ids: Array = []
	var expected_ids: Array = []
	var source_by_id := {}
	for character in characters:
		expected_ids.append(character.id)
		source_by_id[String(character.id)] = character
	for row in rows:
		assert_true(row is Dictionary, "角色 ViewModel 必须是白名单 Dictionary")
		if not (row is Dictionary):
			continue
		assert_eq(_sorted_keys(row), CHARACTER_KEYS, "角色 ViewModel 不得携带 Run-only 字段")
		actual_ids.append(row.get("id", ""))
		var character: Character = source_by_id.get(String(row.get("id", ""))) as Character
		assert_not_null(character, "资料馆角色必须来自 CharacterPool.all()")
		if character == null:
			continue
		assert_eq(String(row.get("display_name", "")), character.display_name)
		assert_eq(String(row.get("description", "")), character.description)
		assert_eq(String(row.get("portrait_path", "")), character.portrait_path)
		assert_true(ResourceLoader.exists(character.portrait_path), "角色立绘必须走真实生产资产")
		assert_true(load(character.portrait_path) is Texture2D, "角色立绘必须可加载为 Texture2D")
		var labels: Array = row.get("affinity_labels", [])
		assert_eq(labels, [
			_affinity_label(character.affinity_primary),
			_affinity_label(character.affinity_secondary),
		], "双倾向必须解析为 Momentum 的中文显示名")
	assert_eq(_sorted_strings(actual_ids), _sorted_strings(expected_ids))


func test_character_catalog_resolves_real_ability_copy_without_exposing_internal_id() -> void:
	var catalog := _catalog()
	if catalog == null or not catalog.has_method("characters"):
		return
	var abilities := _ability_by_id()
	for row in catalog.call("characters"):
		var character := CharacterPool.find(StringName(row.get("id", "")))
		assert_not_null(character)
		if character == null:
			continue
		var ability: AbilityCard = abilities.get(character.ability_id) as AbilityCard
		assert_not_null(ability, "每名角色的 ability_id 必须能解析到真实 AbilityCard")
		if ability == null:
			continue
		assert_eq(String(row.get("ability_name", "")), ability.display_name)
		assert_eq(String(row.get("ability_description", "")), ability.description)
		assert_ne(String(row.get("ability_name", "")), String(character.ability_id),
			"玩家界面不得显示冻结的内部 ability_id")


func test_item_catalog_contains_only_battle_consumables_and_safe_persistent_items() -> void:
	var catalog := _catalog()
	if catalog == null:
		return
	assert_true(catalog.has_method("items"), "数据源须提供 items()")
	if not catalog.has_method("items"):
		return
	var rows: Array = catalog.call("items")
	var expected := {}
	for consumable in CardPool.consumables_by_kind(ConsumableItem.Kind.BATTLE):
		expected[String(consumable.id)] = {
			"item": consumable,
			"category": "一次性道具",
		}
	for relic in CardPool.all_relics():
		if relic.id != &"relic_pity_breaker_v1":
			expected[String(relic.id)] = {
				"item": relic,
				"category": "常驻道具",
			}

	assert_eq(rows.size(), 21, "应展示 10 件牌局消耗品和 11 件非抽卡常驻道具")
	assert_eq(rows.size(), expected.size())
	var actual_ids: Array = []
	for row in rows:
		assert_true(row is Dictionary)
		if not (row is Dictionary):
			continue
		assert_eq(_sorted_keys(row), ITEM_KEYS, "道具 ViewModel 只能包含玩家可见白名单字段")
		var item_id := String(row.get("id", ""))
		actual_ids.append(item_id)
		assert_true(expected.has(item_id), "资料馆不得混入 Run-only 或抽卡道具: %s" % item_id)
		if not expected.has(item_id):
			continue
		var expected_row: Dictionary = expected[item_id]
		var item: Variant = expected_row.item
		assert_eq(String(row.get("display_name", "")), item.display_name)
		assert_eq(String(row.get("description", "")), item.description)
		assert_eq(String(row.get("rarity_label", "")), Rarity.display_name(item.rarity))
		assert_eq(String(row.get("category", "")), expected_row.category)
		var icon_path := String(row.get("icon_path", ""))
		assert_false(icon_path.is_empty(), "资料馆道具必须有真实图标: %s" % item_id)
		assert_true(ResourceLoader.exists(icon_path), "道具图标必须走真实生产资产: %s" % item_id)
		assert_true(load(icon_path) is Texture2D)
	assert_eq(_sorted_strings(actual_ids), _sorted_strings(expected.keys()))
	for forbidden_id in ["hp_potion_v1", "gold_doubler_v1", "relic_pity_breaker_v1"]:
		assert_false(actual_ids.has(forbidden_id), "必须过滤肉鸽道具 %s" % forbidden_id)


func test_catalog_visible_copy_has_no_run_or_e6_content() -> void:
	var catalog := _catalog()
	if catalog == null or not catalog.has_method("characters") or not catalog.has_method("items"):
		return
	var visible_copy := ""
	for row in catalog.call("characters"):
		visible_copy += " %s %s %s %s" % [
			row.get("display_name", ""), row.get("description", ""),
			row.get("ability_name", ""), row.get("ability_description", ""),
		]
	for row in catalog.call("items"):
		visible_copy += " %s %s %s" % [
			row.get("display_name", ""), row.get("description", ""), row.get("category", ""),
		]
	var normalized := visible_copy.to_lower()
	for forbidden in FORBIDDEN_COPY:
		assert_false(normalized.contains(forbidden), "资料馆可见文案不得包含：%s" % forbidden)


func test_rule_catalog_covers_modes_and_basic_riichi_without_e6() -> void:
	var catalog := _catalog()
	if catalog == null:
		return
	assert_true(catalog.has_method("rules"), "数据源须提供 rules()")
	if not catalog.has_method("rules"):
		return
	var rows: Array = catalog.call("rules")
	assert_gt(rows.size(), 0)
	var copy := ""
	for row in rows:
		assert_true(row is Dictionary)
		if not (row is Dictionary):
			continue
		assert_eq(_sorted_keys(row), RULE_KEYS)
		copy += " %s %s" % [row.get("title", ""), row.get("body", "")]
	for required in ["东风战", "半庄战", "标准场", "嘴强欢乐场", "立直", "鸣牌", "振听", "无役不能和"]:
		assert_true(copy.contains(required), "规则说明必须覆盖：%s" % required)
	var normalized := copy.to_lower()
	for forbidden in FORBIDDEN_COPY:
		assert_false(normalized.contains(forbidden), "规则说明不得包含：%s" % forbidden)


func test_mode_rules_use_correct_round_terms_and_state_feature_boundaries() -> void:
	var catalog := _catalog()
	if catalog == null or not catalog.has_method("rules"):
		return
	var by_id := {}
	for row in catalog.call("rules"):
		by_id[String(row.get("id", ""))] = String(row.get("body", ""))
	for required_id in ["mode_east", "mode_hanchan", "mode_standard", "mode_trash_talk"]:
		assert_true(by_id.has(required_id), "规则页必须提供稳定模式条目：%s" % required_id)
	if not by_id.has("mode_east") or not by_id.has("mode_hanchan"):
		return
	assert_true(by_id.mode_east.contains("东一") and by_id.mode_east.contains("东四"),
		"东风战应说明东一至东四四局")
	assert_false(by_id.mode_east.contains("四巡"), "四局不能误写成四巡")
	assert_true(by_id.mode_hanchan.contains("东一") and by_id.mode_hanchan.contains("南四"),
		"半庄战应说明东一至南四八局")
	assert_false(by_id.mode_hanchan.contains("八巡"), "八局不能误写成八巡")

	var standard: String = by_id.get("mode_standard", "")
	for required in ["关闭", "角色能力", "道具", "PTT", "奖励窗口"]:
		assert_true(standard.contains(required), "标准场必须明确%s边界" % required)
	var trash_talk: String = by_id.get("mode_trash_talk", "")
	for required in [
		"启用", "角色能力", "道具", "PTT", "窗口开始公开", "24 次", "四件", "一对一", "和牌",
		"取消", "不评分", "不发奖", "终场非和牌", "只展示", "重复持有", "下一窗口",
	]:
		assert_true(trash_talk.contains(required), "嘴强欢乐场必须明确%s边界" % required)


func test_yaku_catalog_covers_engine_registry_with_teaching_metadata() -> void:
	var catalog := _catalog()
	assert_true(catalog.has_method("yakus"), "资料馆必须提供独立役种图鉴数据")
	if not catalog.has_method("yakus"):
		return
	var rows: Array = catalog.call("yakus")
	assert_eq(rows.size(), YakuId.ALL.size() + YakuId.ALL_VARIANTS.size(),
		"役种图鉴必须从引擎注册表覆盖全部基础役与上位变体")
	var ids := {}
	for row in rows:
		assert_eq(_sorted_keys(row), YAKU_KEYS)
		ids[int(row.get("id", -1))] = true
		assert_false(String(row.get("display_name", "")).is_empty())
		assert_false(String(row.get("category", "")).is_empty())
		assert_false(String(row.get("condition", "")).is_empty())
		assert_false(String(row.get("description", "")).is_empty())
		assert_false(String(row.get("example", "")).is_empty())
	for yaku_id in YakuId.ALL + YakuId.ALL_VARIANTS:
		assert_true(ids.has(yaku_id), "图鉴遗漏引擎役种 %s" % yaku_id)
