extends GutTest

# #324：全局轻量按钮继续服务大厅；牌桌行动按钮使用独立旗标但保留原生语义。

const LOBBY_STAGE := preload("res://ui/lobby/lobby_stage.tscn")
const ACTION_PANEL := preload("res://ui/four_player_table/player_action_panel.tscn")
const TABLE_ACTION_SCRIPT := "res://ui/four_player_table/table_action_button.gd"
const ACTION_FONT_PATH := "res://assets/fonts/ZCOOLKuaiLe-Regular.ttf"


func test_project_theme_default_button_no_longer_uses_texture_frame() -> void:
	var theme := load("res://ui/run_theme.tres") as Theme
	assert_not_null(theme)
	for state in ["normal", "hover", "focus", "pressed", "disabled"]:
		assert_true(theme.get_stylebox(state, "Button") is StyleBoxFlat,
			"全局 Button.%s 必须脱离旧厚框 PNG" % state)
	assert_ne(theme.get_stylebox("hover", "Button"), theme.get_stylebox("focus", "Button"),
		"hover 与 focus 不得复用同一 StyleBox")


func test_real_lobby_fixed_slot_keeps_geometry_and_gets_ellipsis_contract() -> void:
	var stage := LOBBY_STAGE.instantiate()
	add_child_autofree(stage)
	await get_tree().process_frame
	var button := stage.get_node("BottomNav/NavRow/CharacterNavButton") as Button
	assert_eq(button.custom_minimum_size, Vector2(118, 48),
		"#303 父页面固定槽位不得被按钮文字反向撑大")
	assert_true(button.clip_text)
	assert_eq(button.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS)
	assert_eq(button.tooltip_text, "雀士名录")
	assert_true(button.get_theme_stylebox("normal") is StyleBoxFlat)


func test_real_action_buttons_use_table_flags_without_changing_bar_geometry() -> void:
	var panel: PlayerActionPanel = ACTION_PANEL.instantiate()
	add_child_autofree(panel)
	await get_tree().process_frame
	assert_eq(panel.custom_minimum_size, Vector2(720, 78),
		"#304 行动栏父几何必须保持不变")
	assert_eq(panel._btn_ron.custom_minimum_size, Vector2(108, 52))
	assert_eq(panel._btn_skip.custom_minimum_size, Vector2(108, 52))
	var ron_script: Script = panel._btn_ron.get_script() as Script
	var skip_script: Script = panel._btn_skip.get_script() as Script
	assert_not_null(ron_script, "和按钮必须使用牌桌旗标组件")
	assert_not_null(skip_script, "跳过按钮必须使用牌桌旗标组件")
	if ron_script == null or skip_script == null:
		return
	assert_eq(ron_script.resource_path, TABLE_ACTION_SCRIPT)
	assert_eq(skip_script.resource_path, TABLE_ACTION_SCRIPT)
	assert_eq(panel._btn_ron.text, "和")
	assert_eq(panel._btn_ron.tooltip_text, "和")
	assert_eq(panel._btn_ron.get("action_kind"), &"win")
	assert_eq(panel._btn_chi.get("action_kind"), &"chi")
	assert_eq(panel._btn_pon.get("action_kind"), &"pon")
	assert_eq(panel._btn_minkan.get("action_kind"), &"kan")
	assert_eq(panel._btn_skip.get("action_kind"), &"skip")
	assert_eq(panel._btn_ron.get("label_font_size"), 31)
	assert_eq(panel._btn_skip.get("label_font_size"), 24)
	assert_eq(panel._btn_kyuusyu.get("label_font_size"), 17)
	assert_not_null(panel._btn_ron.get_node_or_null("RearRibbon"))
	assert_not_null(panel._btn_ron.get_node_or_null("ShadowLabel"))
	assert_not_null(panel._btn_ron.get_node_or_null("FrontLabel"))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		assert_true(panel._btn_ron.get_theme_stylebox(state) is StyleBoxEmpty,
			"旗标按钮不应重新露出矩形 Theme：%s" % state)
	var ribbon := panel._btn_ron.get_node("MainRibbon") as Polygon2D
	var original_polygon := ribbon.polygon.duplicate()
	panel._btn_ron.button_down.emit()
	assert_eq(ribbon.polygon, original_polygon, "按下态不得改变旗标几何")
	panel._btn_ron.button_up.emit()
	panel._btn_ron.mouse_entered.emit()
	assert_eq(ribbon.polygon, original_polygon, "悬停态不得改变旗标几何")
	panel.enter_waiting_claim(true, true, true, true, 1)
	await get_tree().process_frame
	var rear := panel._btn_ron.get_node("RearRibbon") as Polygon2D
	var rear_bottom := 0.0
	for point in rear.polygon:
		rear_bottom = maxf(rear_bottom, point.y)
	var visual_bottom := rear.to_global(Vector2(0, rear_bottom)).y
	var countdown_top := panel._countdown_bar.global_position.y
	assert_gte(countdown_top - visual_bottom, 6.0,
		"可见旗标与倒计时必须保留至少 6px 净空")


func test_table_action_font_covers_every_display_label() -> void:
	assert_true(ResourceLoader.exists(ACTION_FONT_PATH), "动作按钮字体必须进入生产资源路径")
	if not ResourceLoader.exists(ACTION_FONT_PATH):
		return
	var font := load(ACTION_FONT_PATH) as Font
	assert_not_null(font)
	if font == null:
		return
	for label in ["和", "吃", "碰", "杠", "跳过", "立直", "自摸", "九种九牌", "暗杠", "加杠", "道具"]:
		for character in label:
			assert_true(font.has_char(character.unicode_at(0)),
				"站酷快乐体必须覆盖动作文案：%s" % label)


func test_win_and_kyuusyu_labels_keep_existing_action_protocols() -> void:
	var panel: PlayerActionPanel = ACTION_PANEL.instantiate()
	add_child_autofree(panel)
	await get_tree().process_frame
	var choices: Array[Dictionary] = []
	panel.player_action_chosen.connect(
		func(choice: Dictionary) -> void: choices.append(choice))
	panel.enter_waiting_claim(true, false, false, false, 2)
	panel._btn_ron.pressed.emit()
	assert_eq(choices, [{"action": "ron", "discarder_seat": 2}])
	assert_eq(panel._btn_ron.text, "和")

	choices.clear()
	panel.enter_waiting_kyuusyu()
	panel._btn_kyuusyu.pressed.emit()
	assert_eq(choices, [{"action": "kyuusyu_yes"}])
	assert_eq(panel._btn_kyuusyu.text, "九种九牌")
