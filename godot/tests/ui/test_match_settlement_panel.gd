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
