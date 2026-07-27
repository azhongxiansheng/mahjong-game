extends GutTest

# Issue #326：真实 catalog 图标、生产 HUD、多实例与全局几何合同。

const TableScr := preload("res://ui/four_player_table/four_player_table.gd")
const ProjScr := preload("res://ui/four_player_table/reward_feedback_projector.gd")
const ResolverScr := preload("res://ui/four_player_table/table_icon_resolver.gd")

const ITEM_ROOT := "res://assets/ui/table_hud/items/"
const ABILITY_ROOT := "res://assets/ui/table_hud/abilities/"
const CHROME_ROOT := "res://assets/ui/table_hud/chrome/"
const DRAWER_RECT := Rect2(1384.0, 456.0, 200.0, 312.0)
const PRIZE_ICON_RECTS := [
	Rect2(24.0, 132.0, 52.0, 52.0),
	Rect2(24.0, 192.0, 52.0, 52.0),
	Rect2(1524.0, 132.0, 52.0, 52.0),
	Rect2(1524.0, 192.0, 52.0, 52.0),
]
const ABILITY_SEAL_RECT := Rect2(1480.0, 8.0, 48.0, 48.0)
const INVENTORY_SEAL_RECT := Rect2(1536.0, 8.0, 48.0, 48.0)


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


func test_prize_pool_is_icon_only_and_tooltip_has_name_and_effect() -> void:
	var hud = load("res://ui/four_player_table/reward_pool_hud.gd").new()
	add_child_autofree(hud)
	await get_tree().process_frame
	hud.set_prize_pool_rows([{
		"display_name": "铁壁",
		"effect_summary": "抵消下一次失分",
		"tag_labels": ["冷静", "防御"],
		"icon_path": _item_icon_path("iron_shield_v1"),
	}])
	var icon: TextureRect = hud.find_child("ItemIcon0", true, false) as TextureRect
	assert_not_null(icon)
	assert_true(icon.tooltip_text.contains("铁壁"))
	assert_true(icon.tooltip_text.contains("抵消下一次失分"))
	assert_null(hud.find_child("ItemName", true, false), "奖品常态不得显示名称")
	assert_null(hud.find_child("ItemTags", true, false), "奖品常态不得显示标签")
	assert_eq(hud.prize_icon_rects(), PRIZE_ICON_RECTS)


func test_ability_and_inventory_are_compact_equipment_seals() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var ability: Control = table.get_node("AbilityBadge") as Control
	var inventory: Button = table.get_node("InventoryButton") as Button
	assert_eq(Rect2(ability.position, ability.size), ABILITY_SEAL_RECT)
	assert_eq(Rect2(inventory.position, inventory.size), INVENTORY_SEAL_RECT)
	assert_null(ability.find_child("AbilityName", true, false), "技能印常态只显示图标与状态角标")
	assert_not_null(ability.find_child("AbilityStateMark", true, false))


func test_seat_identity_has_no_persistent_empty_panel_and_keeps_gameplay_rects() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	for seat_id in range(4):
		var seat: SeatPanel = table.seat_panels[seat_id]
		var hud: Control = seat.get_node_or_null("SeatHUD") as Control
		assert_not_null(hud)
		assert_false(hud is Panel, "身份 HUD 不得再铺常驻黑色面板")
		assert_false(hud.visible, "无状态时不得保留空 HUD")
		var portrait: TextureRect = seat._portrait_rect
		if seat_id > 0:
			assert_not_null(portrait)
		if portrait != null:
			assert_eq(portrait.size, Vector2(56.0, 56.0))
	table.seat_panels[0].set_riichi(true)
	var player_hud: Control = table.seat_panels[0].get_node("SeatHUD") as Control
	assert_true(player_hud.visible, "真实宣告出现时才显示状态印")
	assert_not_null(player_hud.find_child("RiichiBadge", true, false))
	assert_eq(TableLayout.ACTION_BAR_RECT, Rect2(440.0, 680.0, 720.0, 78.0))
	assert_eq(TableLayout.HAND_HOST_RECTS[0], Rect2(302.0, 778.0, 996.0, 92.0))
	assert_eq(TableLayout.crowded_state_rects()[2], Rect2(555.0, 142.0, 490.0, 154.0))


func test_inventory_is_icon_grid_with_detail_tooltip_and_single_selected_action() -> void:
	var drawer = load("res://ui/four_player_table/item_inventory_drawer.gd").new()
	add_child_autofree(drawer)
	await get_tree().process_frame
	var emitted: Array = []
	drawer.use_item_requested.connect(func(iid: String) -> void: emitted.append(iid))
	drawer.set_instances([{
		"item_instance_id": "ii_grid_a",
		"item_id": "iron_shield_v1",
		"display_name": "铁壁",
		"effect_summary": "抵消下一次失分",
		"status": "held",
		"icon_path": _item_icon_path("iron_shield_v1"),
	}])
	var drawer_panel: PanelContainer = drawer.find_child(
		"DrawerPanel", true, false) as PanelContainer
	assert_not_null(drawer_panel)
	assert_lte(drawer_panel.size.y, 128.0,
		"单排库存只占内容高度，不得保留整块 312px 空黑底")
	var grid: GridContainer = drawer.find_child("InstanceGrid", true, false) as GridContainer
	assert_not_null(grid)
	assert_eq(grid.columns, 3)
	var cell: Control = drawer.find_child("Row_ii_grid_a", true, false) as Control
	assert_not_null(cell)
	var item_button: Button = cell.find_child("ItemButton", true, false) as Button
	assert_not_null(item_button)
	assert_true(item_button.tooltip_text.contains("铁壁"))
	assert_true(item_button.tooltip_text.contains("抵消下一次失分"))
	assert_true(item_button.tooltip_text.contains("ii_grid_a"))
	assert_null(cell.find_child("InstanceIdLabel", true, false), "内部 ID 不得常驻可见")
	var use_selected: Button = drawer.find_child("UseSelectedButton", true, false) as Button
	assert_not_null(use_selected)
	assert_false(use_selected.visible, "未选择道具时不显示动作")
	item_button.pressed.emit()
	assert_true(use_selected.visible)
	await get_tree().process_frame
	assert_lte(drawer_panel.size.y, 176.0,
		"共享动作出现后仍保持紧凑，不扩成固定高浮窗")
	use_selected.pressed.emit()
	assert_eq(emitted, ["ii_grid_a"], "共享动作仍须发送精确 instance ID")


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
		assert_not_null(panel.find_child("ItemButton", true, false))
		assert_not_null(panel.find_child("StateLabel", true, false), "状态不能只靠颜色")
	var use_selected: Button = drawer.find_child("UseSelectedButton", true, false) as Button
	drawer.select_instance("ii_same_a")
	assert_true(use_selected.visible)
	assert_false(use_selected.disabled)
	drawer.select_instance("ii_same_b")
	assert_false(use_selected.visible, "armed 实例不得出现使用动作")


func test_inventory_many_instances_scroll_inside_approved_rail() -> void:
	var drawer = load("res://ui/four_player_table/item_inventory_drawer.gd").new()
	add_child_autofree(drawer)
	await get_tree().process_frame
	var rows: Array = []
	for index in range(15):
		rows.append({
			"item_instance_id": "ii_many_%02d" % index,
			"item_id": "iron_shield_v1",
			"display_name": "铁壁",
			"status": "held",
			"icon_path": _item_icon_path("iron_shield_v1"),
		})
	drawer.set_instances(rows)
	drawer.select_instance("ii_many_00")
	await get_tree().process_frame
	var drawer_panel := drawer.find_child("DrawerPanel", true, false) as PanelContainer
	assert_not_null(drawer_panel)
	assert_lte(drawer_panel.size.y, DRAWER_RECT.size.y,
		"大量实例必须在批准轨道内滚动，不得把可见面板向下撑出安全区")


func test_approved_rects_and_critical_regions_do_not_overlap() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var drawer: Control = table.get_node("ItemInventoryDrawer") as Control
	assert_eq(drawer.drawer_rect(), DRAWER_RECT)
	var hud: Control = table.get_node("RewardPoolHud") as Control
	assert_eq(hud.prize_icon_rects(), PRIZE_ICON_RECTS)

	# #304 生产关键区域：四向手牌、牌河/副露、中央与底部操作/宣告带。
	var critical: Array = []
	critical.append_array(TableLayout.HAND_HOST_WITH_MELD_RECTS)
	critical.append_array(TableLayout.crowded_state_rects())
	critical.append(TableLayout.center_plate()["screen_aabb"])
	critical.append(TableLayout.ACTION_BAR_RECT)
	for hud_rect in PRIZE_ICON_RECTS + [DRAWER_RECT]:
		for region in critical:
			assert_false(hud_rect.intersects(region),
				"HUD %s 不得遮挡关键区 %s" % [hud_rect, region])
