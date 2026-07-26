extends GutTest

const MODE_BANNER := preload("res://ui/lobby/lobby_mode_banner.tscn")
const OMAMORI_BUTTON := preload("res://ui/lobby/lobby_omamori_button.tscn")


func test_mode_banner_keeps_native_button_signal_and_inner_nodes_ignore_input() -> void:
	var button := MODE_BANNER.instantiate() as Button
	add_child_autofree(button)
	await get_tree().process_frame
	assert_true(button is Button)
	assert_eq(button.focus_mode, Control.FOCUS_ALL)
	for child in button.find_children("*", "Control", true, false):
		assert_eq((child as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE)
	watch_signals(button)
	button.pressed.emit()
	assert_signal_emitted(button, "pressed", "视觉反馈不得延迟或替换业务信号")


func test_mode_banner_hover_transition_is_cancellable_and_reaches_stable_state() -> void:
	var button := MODE_BANNER.instantiate() as Button
	add_child_autofree(button)
	await get_tree().process_frame
	button.mouse_entered.emit()
	button.finish_visual_transition()
	assert_eq(button.get_visual_state(), &"hovered")
	assert_eq(button.scale, Vector2.ONE, "局部异能反馈不得采用整牌匾放大方案")
	var accent := button.get_node("EnergyAccent") as ColorRect
	var art := button.get_node("BannerArt") as TextureRect
	assert_true(accent.visible, "hover 必须显示局部紫色异能笔触")
	assert_gt(accent.color.b, accent.color.r, "hover 异能反馈应以紫色为主")
	assert_gt(accent.z_index, art.z_index, "局部异能笔触必须绘制在不透明牌匾图层之上")
	assert_lte(accent.size.x, 10.0, "异能反馈必须保持为局部窄条，不得覆盖整张牌匾")
	button.mouse_exited.emit()
	button.finish_visual_transition()
	assert_eq(button.get_visual_state(), &"idle")
	assert_eq(button.scale, Vector2.ONE, "反向过渡应取消旧 tween 并稳定复位")
	assert_false(accent.visible)


func test_mode_banner_focus_and_pressed_use_distinct_local_feedback() -> void:
	var button := MODE_BANNER.instantiate() as Button
	add_child_autofree(button)
	await get_tree().process_frame
	var accent := button.get_node("EnergyAccent") as ColorRect
	button.focus_entered.emit()
	button.finish_visual_transition()
	assert_eq(button.get_visual_state(), &"focused")
	assert_true(accent.visible)
	assert_gt(accent.color.b, accent.color.r, "键盘焦点必须使用紫色局部反馈")
	button.button_down.emit()
	button.finish_visual_transition()
	assert_eq(button.get_visual_state(), &"pressed")
	assert_gt(accent.color.r, accent.color.b, "按压必须切换为朱红印章语义")


func test_mode_banner_native_disabled_property_reaches_stable_visual_state() -> void:
	var button := MODE_BANNER.instantiate() as Button
	add_child_autofree(button)
	await get_tree().process_frame
	button.disabled = true
	await get_tree().process_frame
	button.finish_visual_transition()
	assert_eq(button.get_visual_state(), &"disabled")
	assert_lt((button.get_node("BannerArt") as TextureRect).modulate.a, 0.8)
	var hint := button.get_node("DisabledHint") as Label
	assert_true(hint.visible, "禁用态不得只依赖颜色，必须提供文字提示")
	assert_ne(hint.text, "")


func test_omamori_root_is_accessible_button_with_real_atlas_icon() -> void:
	var button := OMAMORI_BUTTON.instantiate() as Button
	add_child_autofree(button)
	await get_tree().process_frame
	assert_true(button is Button)
	assert_ne(button.text, "")
	assert_eq(button.focus_mode, Control.FOCUS_ALL)
	var icon := button.get_node("Icon") as TextureRect
	assert_eq(icon.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_true(icon.texture is AtlasTexture)
	var normal := button.get_theme_stylebox("normal") as StyleBoxFlat
	var hover := button.get_theme_stylebox("hover") as StyleBoxFlat
	var focus := button.get_theme_stylebox("focus") as StyleBoxFlat
	var pressed := button.get_theme_stylebox("pressed") as StyleBoxFlat
	assert_lt(normal.bg_color.a, 0.55, "御守正常态应退居边缘，不得形成厚重黑墙")
	assert_gt(hover.border_color.b, hover.border_color.r, "御守 hover 使用紫色异能反馈")
	assert_gt(focus.border_color.b, focus.border_color.r, "御守 focus 使用紫色异能反馈")
	assert_gt(pressed.border_color.r, pressed.border_color.b, "御守 pressed 保持朱红按压语义")
