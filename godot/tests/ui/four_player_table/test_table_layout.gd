extends GutTest

# TableLayout 契约 + 满桌 1280 宽


func test_table_is_full_width_1280() -> void:
	assert_eq(TableLayout.TABLE_W, 1280.0)
	assert_eq(FourPlayerTable.TABLE_WIDTH, 1280.0)
	assert_eq(FourPlayerTable.ABILITY_PANEL_WIDTH, 0.0)


func test_seat_anchors_four_quadrants() -> void:
	var p0 := TableLayout.seat_anchor(0)
	var p1 := TableLayout.seat_anchor(1)
	var p2 := TableLayout.seat_anchor(2)
	var p3 := TableLayout.seat_anchor(3)
	assert_gt(p0.y, TableLayout.TABLE_H * 0.5, "下家在下半")
	assert_gt(p1.x, TableLayout.TABLE_W * 0.5, "右家在右半")
	assert_lt(p2.y, TableLayout.TABLE_H * 0.5, "上家在上半")
	assert_lt(p3.x, TableLayout.TABLE_W * 0.5, "左家在左半")


func test_action_bar_above_hand_band() -> void:
	# 操作条 y 应在手牌区之上（seat0 锚点 - 手牌高）
	var seat0_y: float = TableLayout.seat_anchor(0).y
	assert_lt(TableLayout.ACTION_BAR_Y, seat0_y + 48.0,
		"操作条应靠近手牌上方")


func test_four_player_table_min_size_no_ability_gutter() -> void:
	var t: FourPlayerTable = load("res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(t)
	await get_tree().process_frame
	assert_eq(t.custom_minimum_size.x, 1280.0)
	assert_false(t.ability_panel.visible, "右栏能力板应隐藏")


func test_table_stage_builds_under_table() -> void:
	var t: FourPlayerTable = load("res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(t)
	await get_tree().process_frame
	var stage := t.get_node_or_null("TableStage")
	assert_not_null(stage, "应有 TableStage 舞台根")
	assert_true(stage.get_child_count() > 0, "舞台应有子层")
	assert_not_null(stage.get_node_or_null("TableFelt"), "应有 TableFelt")
