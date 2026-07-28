extends GutTest

# E2-05（#235）：整场结算面板 UI 与防重复点击。


func _make_view() -> Dictionary:
	return MatchSettlement.build_view([32000, 28000, 22000, 18000], &"EAST")


func test_panel_script_exists() -> void:
	assert_true(
		ResourceLoader.exists("res://ui/four_player_table/match_settlement_panel.gd"),
		"#235 应新增 MatchSettlementPanel"
	)


func test_panel_shows_title_ranks_and_buttons() -> void:
	var panel := MatchSettlementPanel.new()
	add_child_autofree(panel)
	await get_tree().process_frame
	panel.present(_make_view())
	await get_tree().process_frame

	var title := panel.find_child("TitleLabel", true, false) as Label
	assert_not_null(title)
	assert_eq(title.text, "对局结束")

	var rows_host := panel.find_child("RankRows", true, false)
	assert_not_null(rows_host)
	var row_labels: Array = []
	for child in rows_host.get_children():
		if child is Label:
			row_labels.append((child as Label).text)
	assert_eq(row_labels.size(), 4)
	assert_true(String(row_labels[0]).contains("第 1 名"))
	assert_true(String(row_labels[0]).contains("你"))
	assert_true(String(row_labels[0]).contains("32000"))
	assert_true(String(row_labels[1]).contains("AI 1"))
	assert_true(String(row_labels[3]).contains("AI 3"))

	var rematch_btn := panel.find_child("RematchButton", true, false) as Button
	var return_btn := panel.find_child("ReturnLobbyButton", true, false) as Button
	assert_not_null(rematch_btn)
	assert_not_null(return_btn)
	assert_eq(rematch_btn.text, "再来一局")
	assert_eq(return_btn.text, "返回大厅")
	assert_true(rematch_btn.clip_text)
	assert_true(return_btn.clip_text)
	assert_eq(rematch_btn.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS)
	assert_eq(return_btn.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS)
	assert_eq(rematch_btn.tooltip_text, rematch_btn.text)
	assert_eq(return_btn.tooltip_text, return_btn.text)
	assert_eq(rematch_btn.get_meta("dt_button_role"), DT.BtnRole.PRIMARY)
	assert_eq(return_btn.get_meta("dt_button_role"), DT.BtnRole.SECONDARY)
	var modal := panel.find_child("SettlementModal", true, false) as Panel
	assert_not_null(modal)
	if modal == null:
		return
	var modal_style := modal.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(modal_style)
	if modal_style == null:
		return
	assert_eq(modal_style.bg_color, Color("111217f5"))
	assert_eq(modal_style.border_width_left, 1)


func test_extreme_button_text_keeps_fixed_settlement_geometry() -> void:
	var panel := MatchSettlementPanel.new()
	add_child_autofree(panel)
	await get_tree().process_frame

	var modal := panel.find_child("SettlementModal", true, false) as Panel
	var rematch_btn := panel.find_child("RematchButton", true, false) as Button
	var return_btn := panel.find_child("ReturnLobbyButton", true, false) as Button
	var long_english := "ConfirmSupernaturalPowerWithoutOverflow"
	var long_chinese := "确认以超长异能结算说明返回大厅且绝不撑大固定按钮槽位"
	rematch_btn.text = long_english
	rematch_btn.tooltip_text = ""
	DT.apply_button_role(rematch_btn, DT.BtnRole.PRIMARY)
	return_btn.text = long_chinese
	return_btn.tooltip_text = ""
	DT.apply_button_role(return_btn, DT.BtnRole.SECONDARY)
	await get_tree().process_frame

	assert_eq(modal.custom_minimum_size, Vector2(520, 400))
	assert_eq(modal.size, Vector2(520, 400))
	assert_eq(rematch_btn.position, Vector2(70, 328))
	assert_eq(return_btn.position, Vector2(290, 328))
	assert_eq(rematch_btn.custom_minimum_size, Vector2(160, 44))
	assert_eq(return_btn.custom_minimum_size, Vector2(160, 44))
	assert_eq(rematch_btn.size, Vector2(160, 44))
	assert_eq(return_btn.size, Vector2(160, 44))
	assert_eq(rematch_btn.get_combined_minimum_size(), Vector2(160, 44))
	assert_eq(return_btn.get_combined_minimum_size(), Vector2(160, 44))
	assert_true(rematch_btn.clip_text)
	assert_true(return_btn.clip_text)
	assert_eq(rematch_btn.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS)
	assert_eq(return_btn.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS)
	assert_eq(rematch_btn.tooltip_text, long_english)
	assert_eq(return_btn.tooltip_text, long_chinese)


func test_buttons_emit_once_then_disable() -> void:
	var panel := MatchSettlementPanel.new()
	add_child_autofree(panel)
	await get_tree().process_frame
	panel.present(_make_view())
	await get_tree().process_frame
	watch_signals(panel)

	var rematch_btn := panel.find_child("RematchButton", true, false) as Button
	rematch_btn.pressed.emit()
	rematch_btn.pressed.emit()
	assert_signal_emit_count(panel, "rematch_requested", 1)
	assert_true(rematch_btn.disabled)

	# 新 present 后可再点返回
	panel.present(_make_view())
	await get_tree().process_frame
	var return_btn := panel.find_child("ReturnLobbyButton", true, false) as Button
	assert_false(return_btn.disabled)
	return_btn.pressed.emit()
	return_btn.pressed.emit()
	assert_signal_emit_count(panel, "return_lobby_requested", 1)
	assert_true(return_btn.disabled)


func test_settlement_focus_is_closed_loop_and_escape_never_chooses_action() -> void:
	var panel := MatchSettlementPanel.new()
	add_child_autofree(panel)
	await get_tree().process_frame
	panel.present(_make_view())
	await get_tree().process_frame
	watch_signals(panel)
	var rematch := panel.find_child("RematchButton", true, false) as Button
	var return_lobby := panel.find_child("ReturnLobbyButton", true, false) as Button
	assert_same(get_viewport().gui_get_focus_owner(), rematch)
	assert_eq(rematch.focus_mode, Control.FOCUS_ALL)
	assert_eq(return_lobby.focus_mode, Control.FOCUS_ALL)
	assert_same(rematch.get_node_or_null(rematch.focus_next), return_lobby)
	assert_same(return_lobby.get_node_or_null(return_lobby.focus_next), rematch)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape)
	await get_tree().process_frame
	assert_signal_not_emitted(panel, "rematch_requested")
	assert_signal_not_emitted(panel, "return_lobby_requested")
	assert_true(panel.is_visible_in_tree())
