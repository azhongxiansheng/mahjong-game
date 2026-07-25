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
	assert_gt(button.scale.x, 1.0)
	button.mouse_exited.emit()
	button.finish_visual_transition()
	assert_eq(button.get_visual_state(), &"idle")
	assert_eq(button.scale, Vector2.ONE, "反向过渡应取消旧 tween 并稳定复位")


func test_mode_banner_native_disabled_property_reaches_stable_visual_state() -> void:
	var button := MODE_BANNER.instantiate() as Button
	add_child_autofree(button)
	await get_tree().process_frame
	button.disabled = true
	await get_tree().process_frame
	button.finish_visual_transition()
	assert_eq(button.get_visual_state(), &"disabled")
	assert_lt((button.get_node("BannerArt") as TextureRect).modulate.a, 0.8)


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
