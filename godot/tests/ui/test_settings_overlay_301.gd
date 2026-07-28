extends GutTest

const LOBBY_SCENE := preload("res://ui/lobby/lobby_shell.tscn")
const DESIGN_SIZE := Vector2(1600, 900)


func _spawn_lobby() -> LobbyShell:
	var host := Control.new()
	host.size = DESIGN_SIZE
	add_child_autofree(host)
	var shell := LOBBY_SCENE.instantiate() as LobbyShell
	host.add_child(shell)
	return shell


func _left_click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func test_real_lobby_settings_button_opens_one_overlay_and_restores_focus() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	var source := shell.get_node("%SettingsButton") as Button
	assert_not_null(source)
	source.grab_focus()
	source.pressed.emit()
	await get_tree().process_frame
	var overlay := get_tree().root.get_node_or_null("_settings_overlay_root") as SettingsOverlay
	assert_not_null(overlay, "大厅真实 SettingsButton 必须复用生产 SettingsOverlay")
	if overlay == null:
		return
	source.pressed.emit()
	await get_tree().process_frame
	assert_same(get_tree().root.get_node_or_null("_settings_overlay_root"), overlay,
		"重复打开不得叠加第二个设置层")
	var close_button := overlay.get_node_or_null("%SettingsCloseButton") as Button
	assert_not_null(close_button)
	if close_button == null:
		return
	close_button.pressed.emit()
	await get_tree().process_frame
	assert_null(get_tree().root.get_node_or_null("_settings_overlay_root"))
	assert_same(get_viewport().gui_get_focus_owner(), source, "关闭后必须恢复真实大厅来源焦点")


func test_real_lobby_settings_escape_releases_overlay_and_restores_source_focus() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	var source := shell.get_node("%SettingsButton") as Button
	assert_not_null(source)
	if source == null:
		return
	source.grab_focus()
	source.pressed.emit()
	await get_tree().process_frame
	var overlay := get_tree().root.get_node_or_null("_settings_overlay_root") as SettingsOverlay
	assert_not_null(overlay, "必须从真实大厅设置入口打开生产 SettingsOverlay")
	if overlay == null:
		return
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape)
	await get_tree().process_frame
	assert_null(get_tree().root.get_node_or_null("_settings_overlay_root"),
		"Esc 必须释放生产设置层")
	assert_same(get_viewport().gui_get_focus_owner(), source,
		"Esc 关闭后必须恢复真实大厅 SettingsButton 焦点")


func test_settings_has_fixed_header_scroll_body_footer_and_mask_close() -> void:
	var overlay := SettingsOverlay.new()
	add_child_autofree(overlay)
	await get_tree().process_frame
	var header := overlay.get_node_or_null("%SettingsHeader") as Control
	var scroll := overlay.get_node_or_null("%SettingsContentScroll") as ScrollContainer
	var footer := overlay.get_node_or_null("%SettingsFooter") as Control
	var backdrop := overlay.get_node_or_null("%SettingsBackdrop") as Control
	assert_not_null(header)
	assert_not_null(scroll)
	assert_not_null(footer)
	assert_not_null(backdrop)
	if header == null or scroll == null or footer == null or backdrop == null:
		return
	assert_lt(header.get_global_rect().end.y, scroll.get_global_rect().end.y)
	assert_lt(scroll.get_global_rect().position.y, footer.get_global_rect().position.y)
	watch_signals(overlay)
	backdrop.gui_input.emit(_left_click())
	assert_signal_emitted(overlay, "closed", "设置背幕左键必须走同一关闭信号")


func test_settings_focus_starts_inside_and_tabs_are_closed_loop() -> void:
	var overlay := SettingsOverlay.new()
	add_child_autofree(overlay)
	await get_tree().process_frame
	var close_button := overlay.get_node_or_null("%SettingsCloseButton") as Button
	var sfx_slider := overlay.get_node_or_null("%SettingsSfxSlider") as HSlider
	assert_not_null(close_button)
	assert_not_null(sfx_slider)
	if close_button == null or sfx_slider == null:
		return
	assert_eq(close_button.focus_mode, Control.FOCUS_ALL)
	assert_eq(sfx_slider.focus_mode, Control.FOCUS_ALL)
	var initial_focus := get_viewport().gui_get_focus_owner()
	assert_not_null(initial_focus)
	if initial_focus == null:
		return
	assert_true(overlay == initial_focus or overlay.is_ancestor_of(initial_focus),
		"设置打开后焦点必须进入顶层")
	for _step in range(10):
		var next := InputEventAction.new()
		next.action = &"ui_focus_next"
		next.pressed = true
		get_viewport().push_input(next)
		await get_tree().process_frame
		var focus := get_viewport().gui_get_focus_owner()
		assert_not_null(focus)
		if focus != null:
			assert_true(overlay == focus or overlay.is_ancestor_of(focus),
				"设置 Tab 焦点不得泄漏到底层")


func test_peripheral_capture_matrix_declares_both_supported_sizes_and_states() -> void:
	var path := "res://tools/capture_peripheral_ui_301.gd"
	assert_true(ResourceLoader.exists(path))
	var script := load(path) as GDScript
	assert_not_null(script)
	if script == null:
		return
	var source := script.source_code
	for required in [
		"Vector2i(1600, 900)", "Vector2i(1280, 720)",
		"drawer", "codex_characters", "codex_items", "codex_rules", "settings",
		"joining", "waiting", "reconnecting", "terminal_error",
		"hand_settlement", "match_settlement",
	]:
		assert_true(source.contains(required), "截图矩阵缺少：%s" % required)
