extends GutTest

# Issue #326：真实 catalog 图标、生产 HUD、多实例与全局几何合同。

const TableScr := preload("res://ui/four_player_table/four_player_table.gd")
const ProjScr := preload("res://ui/four_player_table/reward_feedback_projector.gd")
const ResolverScr := preload("res://ui/four_player_table/table_icon_resolver.gd")

const ITEM_ROOT := "res://assets/ui/table_hud/items/"
const ABILITY_ROOT := "res://assets/ui/table_hud/abilities/"
const CHROME_ROOT := "res://assets/ui/table_hud/chrome/"
const DRAWER_RECT := Rect2(1384.0, 456.0, 200.0, 312.0)
const POOL_LEFT_RECT := Rect2(16.0, 124.0, 208.0, 152.0)
const POOL_RIGHT_RECT := Rect2(1376.0, 124.0, 208.0, 152.0)


func _item_icon_path(item_id: String) -> String:
	return ITEM_ROOT + "item_%s.png" % item_id.trim_suffix("_v1")


func _ability_icon_path(ability_id: String) -> String:
	return ABILITY_ROOT + "ability_%s.png" % ability_id.trim_suffix("_v1")


func test_all_production_catalog_icons_are_real_textures() -> void:
	var catalog := LobbyCodexCatalog.new()
	var item_ids: Dictionary = {}
	for row_v in catalog.items():
		var row: Dictionary = row_v
		item_ids[String(row["id"])] = true
	for item_id_v in TrashTalkRuleCatalog.grantable_item_ids():
		item_ids[String(item_id_v)] = true
	assert_eq(item_ids.size(), 21, "生产 catalog 应覆盖 21 个独立道具")
	for item_id in item_ids:
		var path: String = _item_icon_path(String(item_id))
		assert_true(ResourceLoader.exists(path), "%s 必须存在" % path)
		assert_true(load(path) is Texture2D, "%s 必须可加载为 Texture2D" % path)
		assert_false(path.contains("assets/roguelike"))
		assert_eq(ResolverScr.item_icon_path(String(item_id)), path)

	var abilities: Dictionary = {}
	for character in CharacterPool.all():
		abilities[String(character.ability_id)] = true
	assert_eq(abilities.size(), 12, "12 名角色各自使用独立技能图标")
	for ability_id in abilities:
		var path: String = _ability_icon_path(String(ability_id))
		assert_true(ResourceLoader.exists(path), "%s 必须存在" % path)
		assert_true(load(path) is Texture2D, "%s 必须可加载为 Texture2D" % path)
		assert_eq(ResolverScr.ability_icon_path(String(ability_id)), path)

	for chrome in [
		"icon_unknown_seal.png", "icon_inventory_omamori.png",
		"icon_affinity_calm.png", "icon_affinity_cunning.png",
		"icon_affinity_domination.png", "icon_affinity_mystic.png",
		"icon_affinity_passion.png",
	]:
		var chrome_path: String = CHROME_ROOT + String(chrome)
		assert_true(ResourceLoader.exists(chrome_path))
		assert_true(load(chrome_path) is Texture2D)


func test_projector_rows_expose_stable_icon_paths_and_unknown_fallback() -> void:
	var projector = ProjScr.new()
	projector.apply_reward_window_view({
		"prize_pool": ["iron_shield_v1", "not_in_catalog_v1"],
		"character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
	})
	var rows: Array = projector.prize_pool_display_rows()
	assert_eq(String(rows[0].get("icon_path", "")),
		_item_icon_path("iron_shield_v1"))
	assert_eq(String(rows[1].get("icon_path", "")),
		CHROME_ROOT + "icon_unknown_seal.png")
	var ability: Dictionary = projector.local_ability_view()
	assert_eq(String(ability.get("ability_id", "")), "char_akagi_passive_v1")
	assert_eq(String(ability.get("icon_path", "")),
		_ability_icon_path("char_akagi_passive_v1"))
	assert_eq((ability.get("affinity_icon_paths", []) as Array).size(), 2)


func test_production_hud_is_icon_first_and_hidden_ability_panel_stays_hidden() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var hud: Control = table.get_node_or_null("RewardPoolHud") as Control
	assert_not_null(hud)
	for i in range(4):
		assert_not_null(hud.find_child("ItemIcon%d" % i, true, false),
			"奖池槽 %d 必须有图标" % i)
	var inventory_button: Button = table.get_node_or_null("InventoryButton") as Button
	assert_not_null(inventory_button)
	assert_not_null(inventory_button.icon, "库存入口必须使用御守图标")
	assert_not_null(table.get_node_or_null("AbilityBadge"), "必须是真实生产技能徽章")
	assert_not_null(table.find_child("AffinityIcon0", true, false), "技能须展示属性小印")
	assert_false(table.ability_panel.visible, "不得复活隐藏 AbilityPanel")


func test_inventory_preserves_duplicate_instances_and_non_color_state_labels() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var rows := [
		{
			"item_instance_id": "ii_same_a", "item_id": "iron_shield_v1",
			"display_name": "铁壁", "status": "held", "icon_path": _item_icon_path("iron_shield_v1"),
		},
		{
			"item_instance_id": "ii_same_b", "item_id": "iron_shield_v1",
			"display_name": "铁壁", "status": "armed", "armed_for_window_id": "w2",
			"icon_path": _item_icon_path("iron_shield_v1"),
		},
	]
	var drawer: Control = table.get_node("ItemInventoryDrawer") as Control
	drawer.set_instances(rows)
	assert_eq(drawer.row_ids(), ["ii_same_a", "ii_same_b"])
	for iid in drawer.row_ids():
		var panel: Control = drawer.find_child("Row_%s" % iid, true, false) as Control
		assert_not_null(panel)
		assert_not_null(panel.find_child("ItemIcon", true, false))
		assert_not_null(panel.find_child("StateLabel", true, false), "状态不能只靠颜色")
	var held_button: Button = drawer.find_child("Row_ii_same_a", true, false).find_child("UseButton", true, false)
	var armed_button: Button = drawer.find_child("Row_ii_same_b", true, false).find_child("UseButton", true, false)
	assert_false(held_button.disabled)
	assert_true(armed_button.disabled)


func test_approved_rects_and_critical_regions_do_not_overlap() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var drawer: Control = table.get_node("ItemInventoryDrawer") as Control
	assert_eq(drawer.drawer_rect(), DRAWER_RECT)
	var hud: Control = table.get_node("RewardPoolHud") as Control
	assert_eq(hud.pool_group_rects(), [POOL_LEFT_RECT, POOL_RIGHT_RECT])

	# #304 生产关键区域：四向手牌、牌河/副露、中央与底部操作/宣告带。
	var critical: Array = []
	critical.append_array(TableLayout.HAND_HOST_WITH_MELD_RECTS)
	critical.append_array(TableLayout.crowded_state_rects())
	critical.append(TableLayout.center_plate()["screen_aabb"])
	critical.append(TableLayout.ACTION_BAR_RECT)
	for hud_rect in [POOL_LEFT_RECT, POOL_RIGHT_RECT, DRAWER_RECT]:
		for region in critical:
			assert_false(hud_rect.intersects(region),
				"HUD %s 不得遮挡关键区 %s" % [hud_rect, region])
