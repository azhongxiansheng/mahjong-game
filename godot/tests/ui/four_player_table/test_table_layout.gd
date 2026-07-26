extends GutTest

# 1600×900 原创结界舞台的生产布局契约。
# 只验证可读性、边界、真实节点和资产，不锁定第三方像素坐标。

const VIEW_RECT := Rect2(Vector2.ZERO, Vector2(1600, 900))


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


func test_design_resolution_is_1600_by_900() -> void:
	assert_eq(DT.VIEW_W, 1600)
	assert_eq(DT.VIEW_H, 900)
	assert_eq(ProjectSettings.get_setting(
		"display/window/size/viewport_width"), 1600)
	assert_eq(ProjectSettings.get_setting(
		"display/window/size/viewport_height"), 900)
	assert_eq(ProjectSettings.get_setting(
		"display/window/size/window_width_override"), 1600)
	assert_eq(ProjectSettings.get_setting(
		"display/window/size/window_height_override"), 900)


func test_table_and_playable_scene_fill_the_production_stage() -> void:
	assert_eq(TableLayout.VIEW_W, 1600.0)
	assert_eq(TableLayout.VIEW_H, 900.0)
	assert_eq(FourPlayerTable.TABLE_WIDTH, 1600.0)
	assert_eq(FourPlayerTable.TABLE_HEIGHT, 900.0)
	assert_eq(FourPlayerTable.ABILITY_PANEL_WIDTH, 0.0)
	var table := load(
		"res://ui/four_player_table/playable_table.tscn").instantiate() as Control
	assert_eq(table.custom_minimum_size, Vector2(1600.0, 900.0))
	add_child_autofree(table)


func test_declared_hand_meld_and_avatar_zones_stay_in_view() -> void:
	for seat_id in range(4):
		for rect in [
			TableLayout.hand_host_rect(seat_id, false),
			TableLayout.hand_host_rect(seat_id, true),
			TableLayout.single_pon_rect(seat_id),
			TableLayout.avatar_rect(seat_id),
		]:
			assert_true(VIEW_RECT.encloses(rect),
				"seat %d 手牌/副露/头像区必须留在视口" % seat_id)
	assert_false(TableLayout.hand_host_rect(0, false).intersects(
		TableLayout.ACTION_BAR_RECT, false))
	assert_false(TableLayout.hand_host_rect(0, true).intersects(
		TableLayout.ACTION_BAR_RECT, false))


func test_side_hand_slots_keep_depth_and_individual_projection() -> void:
	for seat_id in [1, 3]:
		var first: Rect2 = TableLayout.controlled_side_hand_slot_rect(seat_id, 0)
		var last: Rect2 = TableLayout.controlled_side_hand_slot_rect(seat_id, 12)
		assert_true(VIEW_RECT.encloses(first))
		assert_true(VIEW_RECT.encloses(last))
		assert_ne(first.position, last.position)
		assert_gt(last.size.length(), first.size.length(),
			"侧家每个牌槽须独立投影并保留景深")


func test_action_bar_matches_approved_fixed_ritual_band() -> void:
	assert_eq(TableLayout.ACTION_BAR_RECT, Rect2(440, 680, 720, 78))
	assert_lte(TableLayout.ACTION_BAR_RECT.end.y,
		TableLayout.HAND_SAFE_RECT.position.y)


func test_four_player_table_uses_original_stage_and_four_huds() -> void:
	var table: FourPlayerTable = load(
		"res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(table)
	await get_tree().process_frame
	assert_eq(table.custom_minimum_size, Vector2(1600.0, 900.0))
	assert_false(table.ability_panel.visible, "右栏能力板应隐藏")
	var stage := table.get_node_or_null("TableStage")
	assert_not_null(stage)
	assert_not_null(stage.get_node_or_null("TableFelt"))
	assert_not_null(stage.get_node_or_null("BarrierField"))
	assert_eq(table.seat_panels.size(), 4)
	for seat_id in range(4):
		assert_not_null(table.seat_panels[seat_id].get_node_or_null("SeatHUD"))


func test_table_stage_uses_repo_felt_and_layered_barrier() -> void:
	assert_eq(TableStage.FELT_PATH, "res://assets/table_felt.png")
	assert_eq(TableStage.FELT_FALLBACK, "res://assets/mahjong_table_bg.png")
	var expected_path: String = TableStage.FELT_PATH \
		if ResourceLoader.exists(TableStage.FELT_PATH) \
		else TableStage.FELT_FALLBACK
	assert_true(ResourceLoader.exists(expected_path))
	var host := Control.new()
	add_child_autofree(host)
	var stage := TableStage.build(host, 1600.0, 900.0)
	var felt := stage.get_node_or_null("TableFelt") as TextureRect
	assert_not_null(felt)
	if felt != null:
		assert_eq(felt.texture.resource_path, expected_path)
		assert_eq(felt.get_rect(), VIEW_RECT)
	var barrier := stage.get_node_or_null("BarrierField") as Node2D
	assert_not_null(barrier)
	if barrier != null:
		assert_not_null(barrier.get_node_or_null("SealDiamond"))
		assert_eq(barrier.get_child_count(), 5,
			"中心菱形与四席方向线组成原创结界")
	assert_not_null(stage.get_node_or_null("TableRails"))


func test_table_rails_and_board_frame_are_structural_not_interactive() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var stage := TableStage.build(host, 1600.0, 900.0)
	var rails := stage.get_node_or_null("TableRails") as Node2D
	assert_not_null(rails)
	if rails != null:
		for side_name in ["Left", "Right"]:
			var base := rails.get_node_or_null("Rail%s" % side_name) as Polygon2D
			var highlight := rails.get_node_or_null(
				"Highlight%s" % side_name) as Polygon2D
			assert_not_null(base)
			assert_not_null(highlight)
			if base != null:
				assert_eq(base.polygon.size(), 4)
			if highlight != null:
				assert_eq(highlight.polygon.size(), 4)
	var table: FourPlayerTable = load(
		"res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(table)
	await get_tree().process_frame
	var frame := table.get_node_or_null("Table/BoardFrame") as Node2D
	assert_not_null(frame)
	if frame != null:
		assert_eq(frame.get_child_count(), 5,
			"舞台结构线由外框与四条席位分隔线组成")
		for child in frame.get_children():
			assert_true(child is Line2D)


func test_live_rivers_stay_inside_crowded_public_zones() -> void:
	var table: FourPlayerTable = load(
		"res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(table)
	await get_tree().process_frame
	assert_eq(table.discard_rivers.size(), 4)
	var crowded := TableLayout.crowded_state_rects()
	for seat_id in range(4):
		var river := table.discard_rivers[seat_id] as DiscardRiver
		var container := river.get_node_or_null("RiverContainer") as Control
		assert_not_null(container)
		if container == null:
			continue
		var actual := _global_aabb(container,
			Rect2(Vector2.ZERO, container.size))
		assert_true(crowded[seat_id].encloses(actual),
			"seat %d 真实牌河必须留在最拥挤公开信息区" % seat_id)


func test_center_plate_and_felt_remain_visible() -> void:
	var table: FourPlayerTable = load(
		"res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(table)
	await get_tree().process_frame
	var center := table.center_info
	var plate := center.get_node_or_null("CenterPlate") as Panel
	assert_not_null(plate)
	if plate != null:
		assert_eq(plate.size, Vector2(220.0, 220.0))
		assert_true(VIEW_RECT.encloses(_global_aabb(
			plate, Rect2(Vector2.ZERO, plate.size))))
	var stage := table.get_node_or_null("TableStage") as Control
	var fallback := table.get_node_or_null("TableBg") as ColorRect
	assert_true(fallback == null or fallback.get_index() < stage.get_index()
		or fallback.color.a <= 0.01,
		"不透明背景不得遮挡毛毡与结界线")


func test_capture_tool_uses_production_resolution() -> void:
	var capture_script := load("res://tools/capture_screens.gd") as Script
	assert_not_null(capture_script)
	assert_eq(capture_script.get_script_constant_map().get("CAPTURE_SIZE"),
		Vector2i(1600, 900))
