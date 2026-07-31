extends GutTest

# Issue #326：真实 catalog 图标、生产 HUD、多实例与全局几何合同。

const TableScr := preload("res://ui/four_player_table/four_player_table.gd")
const ProjScr := preload("res://ui/four_player_table/reward_feedback_projector.gd")
const ResolverScr := preload("res://ui/four_player_table/table_icon_resolver.gd")

const ITEM_ROOT := "res://assets/ui/table_hud/items/"
const ABILITY_ROOT := "res://assets/ui/table_hud/abilities/"
const CHROME_ROOT := "res://assets/ui/table_hud/chrome/"
const DRAWER_RECT := Rect2(1384.0, 480.0, 200.0, 288.0)
const PRIZE_ICON_RECTS := [
	Rect2(24.0, 132.0, 52.0, 52.0),
	Rect2(24.0, 192.0, 52.0, 52.0),
	Rect2(1524.0, 132.0, 52.0, 52.0),
	Rect2(1524.0, 192.0, 52.0, 52.0),
]
const PRIZE_GROUP_RECTS := [
	Rect2(16.0, 124.0, 208.0, 152.0),
	Rect2(1376.0, 124.0, 208.0, 152.0),
]
const ABILITY_SEAL_RECT := Rect2(1288.0, 8.0, 48.0, 48.0)
const INVENTORY_SEAL_RECT := Rect2(1344.0, 8.0, 48.0, 48.0)


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


func test_prize_pool_keeps_icon_first_with_visible_name_and_affinity() -> void:
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
	var name_label := hud.find_child("ItemName0", true, false) as Label
	var tags_label := hud.find_child("ItemTags0", true, false) as Label
	var focus_button := hud.find_child("ItemFocus0", true, false) as Button
	assert_not_null(name_label)
	assert_not_null(tags_label)
	assert_not_null(focus_button)
	if name_label != null:
		assert_true(name_label.visible)
		assert_eq(name_label.text, "铁壁")
	if tags_label != null:
		assert_true(tags_label.visible)
		assert_true(tags_label.text.contains("冷静"))
	if focus_button != null:
		assert_eq(focus_button.focus_mode, Control.FOCUS_ALL)
		focus_button.grab_focus()
		await get_tree().process_frame
	if tags_label != null:
		assert_true(tags_label.text.contains("抵消下一次失分"),
			"键盘 focus 必须提供与 hover 相同的效果详情")
	assert_eq(hud.prize_icon_rects(), PRIZE_ICON_RECTS)
	assert_eq(hud.pool_group_rects(), PRIZE_GROUP_RECTS)


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


func test_inventory_is_single_column_instance_rows_with_visible_summary_and_action() -> void:
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
	assert_lte(drawer_panel.size.y, 144.0,
		"单排库存只占内容高度，不得保留整块 288px 空黑底")
	var list := drawer.find_child("InstanceList", true, false) as VBoxContainer
	assert_not_null(list)
	var cell: Control = drawer.find_child("Row_ii_grid_a", true, false) as Control
	assert_not_null(cell)
	var item_button: Button = cell.find_child("ItemButton", true, false) as Button
	assert_not_null(item_button)
	assert_eq(item_button.focus_mode, Control.FOCUS_ALL)
	assert_true(item_button.tooltip_text.contains("铁壁"))
	assert_true(item_button.tooltip_text.contains("抵消下一次失分"))
	assert_true(item_button.tooltip_text.contains("ii_grid_a"))
	var name_label := cell.find_child("ItemName", true, false) as Label
	var effect_label := cell.find_child("EffectSummary", true, false) as Label
	var state_label := cell.find_child("StateLabel", true, false) as Label
	var affinity_label := cell.find_child("AffinityLabel", true, false) as Label
	var armed_label := cell.find_child("ArmedLabel", true, false) as Label
	assert_not_null(name_label)
	assert_not_null(effect_label)
	assert_not_null(state_label)
	assert_not_null(affinity_label)
	assert_not_null(armed_label)
	if name_label != null:
		assert_eq(name_label.text, "铁壁")
	if effect_label != null:
		assert_eq(effect_label.text, "抵消下一次失分")
	if state_label != null:
		assert_true(state_label.text.contains("可用"))
	if affinity_label != null:
		assert_true(affinity_label.text.contains("属性"))
	if armed_label != null:
		assert_eq(armed_label.text, "未武装")
	assert_null(cell.find_child("InstanceIdLabel", true, false), "内部 ID 不得常驻可见")
	var use_button := cell.find_child("UseButton", true, false) as Button
	assert_not_null(use_button)
	if use_button != null:
		assert_false(use_button.disabled)
		assert_eq(use_button.focus_mode, Control.FOCUS_ALL)
		use_button.pressed.emit()
	assert_eq(emitted, ["ii_grid_a"], "实例行动作必须发送精确 instance ID")


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
		assert_not_null(panel.find_child("AffinityLabel", true, false), "affinity 必须常态可见")
		assert_not_null(panel.find_child("ArmedLabel", true, false), "armed 必须常态可见")
	var use_a := drawer.find_child("Row_ii_same_a", true, false).find_child(
		"UseButton", true, false) as Button
	var use_b := drawer.find_child("Row_ii_same_b", true, false).find_child(
		"UseButton", true, false) as Button
	assert_not_null(use_a)
	assert_not_null(use_b)
	if use_a != null:
		assert_false(use_a.disabled)
	if use_b != null:
		assert_true(use_b.disabled, "armed 实例不得提供可用动作")
	var armed_b := drawer.find_child("Row_ii_same_b", true, false).find_child(
		"ArmedLabel", true, false) as Label
	assert_not_null(armed_b)
	if armed_b != null:
		assert_eq(armed_b.text, "已武装")


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
	assert_eq(hud.pool_group_rects(), PRIZE_GROUP_RECTS)

	# #304 生产关键区域：四向手牌、牌河/副露、中央与底部操作/宣告带。
	var critical: Array = []
	critical.append_array(TableLayout.HAND_HOST_WITH_MELD_RECTS)
	critical.append_array(TableLayout.crowded_state_rects())
	critical.append(TableLayout.center_plate()["screen_aabb"])
	critical.append(TableLayout.ACTION_BAR_RECT)
	for hud_rect in PRIZE_GROUP_RECTS + [DRAWER_RECT]:
		for region in critical:
			assert_false(hud_rect.intersects(region),
				"HUD %s 不得遮挡关键区 %s" % [hud_rect, region])
	for seat_hud in TableLayout.SEAT_HUD_RECTS:
		assert_false(DRAWER_RECT.intersects(seat_hud),
			"库存轨不得遮挡真实席位状态印 %s" % seat_hud)


func test_inventory_keyboard_open_close_restores_focus() -> void:
	var table = TableScr.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var inventory_button := table.get_node("InventoryButton") as Button
	assert_eq(inventory_button.focus_mode, Control.FOCUS_ALL)
	inventory_button.grab_focus()
	inventory_button.pressed.emit()
	await get_tree().process_frame
	assert_true(table.is_inventory_drawer_open())
	var close_button := table.find_child("CloseButton", true, false) as Button
	assert_not_null(close_button)
	assert_eq(close_button.focus_mode, Control.FOCUS_ALL)
	close_button.pressed.emit()
	await get_tree().process_frame
	assert_false(table.is_inventory_drawer_open())
	assert_eq(get_viewport().gui_get_focus_owner(), inventory_button,
		"关闭抽屉后焦点必须回到库存入口")


func test_issue_326_capture_uses_real_battle_state() -> void:
	var capture_script := load("res://tools/capture_table_icon_hud_326.gd") as Script
	assert_not_null(capture_script)
	assert_true(bool(capture_script.get_script_constant_map().get(
		"USES_REAL_BATTLE_STATE", false)),
		"#326 验收图必须绑定真实四席手牌，不能再用空 FourPlayerTable 误导选稿")
