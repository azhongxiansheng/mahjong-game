extends GutTest

const PLAYABLE_TABLE := preload("res://ui/four_player_table/playable_table.tscn")


func _make_table(use_3d: bool = false) -> PlayableTable:
	var table: PlayableTable = PLAYABLE_TABLE.instantiate()
	table._use_3d = use_3d
	add_child_autofree(table)
	return table


func test_default_uses_complete_2d_table_path() -> void:
	var table: PlayableTable = PLAYABLE_TABLE.instantiate()
	add_child_autofree(table)

	assert_true(table._table is FourPlayerTable,
		"生产默认应实例化现有 FourPlayerTable 2D 路径")
	assert_false(table._table is MahjongTable3D,
		"生产默认不应实例化实验性 MahjongTable3D")
	assert_eq(table._table.seat_panels.size(), 4, "2D 桌应提供完整四家 seat")


func test_default_player_seat_exposes_playable_api() -> void:
	var table: PlayableTable = PLAYABLE_TABLE.instantiate()
	add_child_autofree(table)
	var player_seat = table._table.seat_panels[0]

	assert_true(player_seat is SeatPanel, "玩家 seat 应走完整 SeatPanel 实现")
	if not player_seat is SeatPanel:
		return
	assert_true(player_seat.has_signal("player_card_clicked"))
	assert_true(player_seat.has_signal("hand_tile_hover"))
	for method_name in [
		"set_hand_clickable",
		"dim_hand_except",
		"clear_hand_dim",
		"get_hand_slot_global_center",
	]:
		assert_true(player_seat.has_method(method_name),
			"玩家 seat 缺少 PlayableTable 所需 API: %s" % method_name)
	assert_true(player_seat._hand_slots is Array,
		"玩家 seat 应保留弃牌飞行动画读取的真实手牌槽")


func test_action_panel_is_topmost_playable_child() -> void:
	var table := _make_table()

	assert_same(table.get_child(table.get_child_count() - 1), table._action_panel,
		"操作条必须保持在牌桌及 HUD 之上")


func test_top_bar_container_does_not_cover_reference_top_hand() -> void:
	var table := _make_table()
	var bar := table.get_node("TopBar") as Panel
	assert_not_null(bar)
	var style := bar.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(style)
	assert_eq(style.bg_color.a, 0.0,
		"参考 stage-header 容器透明，禁止压暗 y=24..48 的顶家牌")
	assert_eq(style.border_width_bottom, 0,
		"参考 header 没有横切顶家牌身的全宽底边")
	assert_eq(style.shadow_size, 0,
		"参考 header 不投全宽阴影；Logo 与按钮保留各自样式")


func test_top_bar_utility_buttons_use_table_reference_style() -> void:
	var table := _make_table()
	for node_name in ["RulesButton", "SettingsButton"]:
		var button := table.get_node_or_null(node_name) as Button
		assert_not_null(button, "%s 必须提供稳定生产节点名" % node_name)
		if button == null:
			continue
		assert_true(bool(button.get_meta("table_utility_button", false)))
		var normal := button.get_theme_stylebox("normal") as StyleBoxFlat
		assert_not_null(normal)
		if normal != null:
			assert_eq(normal.bg_color, Color("111827e8"))
			assert_eq(normal.border_color, Color("d9b65bcc"))


func test_3d_table_remains_explicit_opt_in() -> void:
	var table := _make_table(true)

	assert_true(table._table is MahjongTable3D,
		"显式开启实验开关时仍应保留 MahjongTable3D 路径")
