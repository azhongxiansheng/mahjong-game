extends GutTest

# #324：共享 Theme、真实大厅按钮与牌桌行动按钮必须消费同一轻量契约。

const LOBBY_STAGE := preload("res://ui/lobby/lobby_stage.tscn")
const ACTION_PANEL := preload("res://ui/four_player_table/player_action_panel.tscn")
const EXPECTED_GHOST := Color("7f8797")


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


func test_real_action_buttons_use_shared_roles_without_changing_bar_geometry() -> void:
	var panel: PlayerActionPanel = ACTION_PANEL.instantiate()
	add_child_autofree(panel)
	await get_tree().process_frame
	assert_eq(panel.custom_minimum_size, Vector2(720, 78),
		"#304 行动栏父几何必须保持不变")
	assert_eq(panel._btn_ron.custom_minimum_size, Vector2(108, 52))
	assert_eq(panel._btn_skip.custom_minimum_size, Vector2(108, 52))
	assert_true(panel._btn_ron.clip_text)
	assert_eq(panel._btn_ron.tooltip_text, "荣和")
	assert_eq((panel._btn_ron.get_theme_stylebox("normal") as StyleBoxFlat).border_color,
		DT.TEXT_TITLE, "荣和是允许使用金色的高价值动作")
	assert_eq((panel._btn_skip.get_theme_stylebox("normal") as StyleBoxFlat).border_color,
		EXPECTED_GHOST, "跳过应退居 GHOST 语义")
	assert_eq(panel._btn_ron.get_theme_font_size("font_size"), 22,
		"行动按钮既有可读字号应保留")
