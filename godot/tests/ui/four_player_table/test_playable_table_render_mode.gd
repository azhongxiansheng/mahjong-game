extends GutTest

const PLAYABLE_TABLE := preload("res://ui/four_player_table/playable_table.tscn")


func _make_table(use_3d: bool = false) -> PlayableTable:
	var table: PlayableTable = PLAYABLE_TABLE.instantiate()
	table._use_3d = use_3d
	add_child_autofree(table)
	return table


func _global_aabb(item: CanvasItem, local_rect: Rect2) -> Rect2:
	var transform := item.get_global_transform()
	var points := [
		transform * local_rect.position,
		transform * Vector2(local_rect.end.x, local_rect.position.y),
		transform * local_rect.end,
		transform * Vector2(local_rect.position.x, local_rect.end.y),
	]
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point: Vector2 in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)


func _assert_rect_almost_eq(actual: Rect2, expected: Rect2,
		tolerance: float, label: String) -> void:
	assert_almost_eq(actual.position.x, expected.position.x, tolerance,
		"%s x" % label)
	assert_almost_eq(actual.position.y, expected.position.y, tolerance,
		"%s y" % label)
	assert_almost_eq(actual.size.x, expected.size.x, tolerance,
		"%s width" % label)
	assert_almost_eq(actual.size.y, expected.size.y, tolerance,
		"%s height" % label)


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


func test_3d_table_remains_explicit_opt_in() -> void:
	var table := _make_table(true)

	assert_true(table._table is MahjongTable3D,
		"显式开启实验开关时仍应保留 MahjongTable3D 路径")


func test_run_selected_character_populates_live_player_avatar() -> void:
	var table := _make_table()
	var flow := RunFlow.new()
	flow._run_state = RunState.new(20260720)
	flow._run_state.selected_character_id = &"akagi"
	assert_true(flow.has_method("_apply_player_persona_to_table"),
		"RunFlow 必须把已选角色接到生产牌桌，而不只传能力")
	if not flow.has_method("_apply_player_persona_to_table"):
		flow.free()
		return
	flow.call("_apply_player_persona_to_table", table)
	await get_tree().process_frame
	var player := table._table.seat_panels[0] as SeatPanel
	assert_eq(player._persona_name, "赤木")
	assert_not_null(player._portrait_rect,
		"已有原创 portrait 的已选角色必须显示 seat0 头像")
	if player._portrait_rect != null:
		_assert_rect_almost_eq(_global_aabb(player._portrait_rect,
			Rect2(Vector2.ZERO, player._portrait_rect.size)),
			TableLayout.avatar_rect(0), 0.02, "seat0 live avatar")
	flow.free()
