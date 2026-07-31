extends GutTest

# 1600×900 参考桌布舞台的生产布局契约。
# 只验证可读性、边界、真实节点和用户自有资产。

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
	assert_null(stage.get_node_or_null("BarrierField"),
		"参考桌布已有中心纹样，不再叠加青色结界")
	assert_not_null(stage.get_node_or_null("TableRails"),
		"参考牌桌只保留左右深色木沿")
	assert_eq(table.seat_panels.size(), 4)
	for seat_id in range(4):
		assert_not_null(table.seat_panels[seat_id].get_node_or_null("SeatHUD"))


func test_table_stage_uses_reference_felt_and_tapered_side_rails() -> void:
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
		assert_eq(felt.texture.get_width(), 1600,
			"生产桌布必须直接匹配 1600×900，禁止再拉伸旧 4:3 背景")
		assert_eq(felt.texture.get_height(), 900)
	assert_null(stage.get_node_or_null("BarrierField"),
		"龙纹桌布不得再被青色结界线抢占视觉中心")
	var raw_top: float = TableLayout.TABLE_PLANE_RECT.position.y
	var raw_bottom: float = TableLayout.TABLE_PLANE_RECT.end.y
	var masks := stage.get_node_or_null("TableClipMasks") as Node2D
	assert_not_null(masks, "桌布投影外侧必须恢复参考图的黑色留空与内缝")
	if masks != null:
		var left_mask := masks.get_node_or_null("LeftOutsideMask") as Polygon2D
		var right_mask := masks.get_node_or_null("RightOutsideMask") as Polygon2D
		assert_not_null(left_mask)
		assert_not_null(right_mask)
		if left_mask != null:
			var left_top := TableLayout.project_table_point(Vector2(0, raw_top))
			assert_eq(left_mask.polygon, PackedVector2Array([
				Vector2(0, left_top.y),
				left_top,
				TableLayout.project_table_point(Vector2(0, raw_bottom)),
			]))
		if right_mask != null:
			var right_top := TableLayout.project_table_point(Vector2(1600, raw_top))
			assert_eq(right_mask.polygon, PackedVector2Array([
				Vector2(1600, right_top.y),
				right_top,
				TableLayout.project_table_point(Vector2(1600, raw_bottom)),
			]))
	var rails := stage.get_node_or_null("TableRails") as Node2D
	assert_not_null(rails)
	if rails == null:
		return
	assert_eq(rails.z_index, 0,
		"木沿必须留在舞台背景层，不得盖住后创建的玩家 HUD")
	assert_eq(rails.get_child_count(), 2, "只绘制参考项目的左右两条木沿")
	var expected_bodies := {
		"LeftRail": PackedVector2Array([
			TableLayout.project_table_point(Vector2(-130, raw_top)),
			TableLayout.project_table_point(Vector2(-10, raw_top)),
			TableLayout.project_table_point(Vector2(-10, raw_bottom)),
			TableLayout.project_table_point(Vector2(-130, raw_bottom)),
		]),
		"RightRail": PackedVector2Array([
			TableLayout.project_table_point(Vector2(1610, raw_top)),
			TableLayout.project_table_point(Vector2(1730, raw_top)),
			TableLayout.project_table_point(Vector2(1730, raw_bottom)),
			TableLayout.project_table_point(Vector2(1610, raw_bottom)),
		]),
	}
	for rail_name in expected_bodies:
		var rail := rails.get_node_or_null(rail_name) as Node2D
		assert_not_null(rail, "%s 存在" % rail_name)
		if rail == null:
			continue
		var body := rail.get_node_or_null("Body") as Polygon2D
		assert_not_null(body, "%s 有深色木质主体" % rail_name)
		if body != null:
			assert_eq(body.polygon, expected_bodies[rail_name],
				"%s 必须由原始 120px 木条经过统一桌面投影" % rail_name)
			assert_eq(body.uv.size(), 4)
			assert_true(body.material is ShaderMaterial,
				"%s 木体必须有可缩放的实时木纹材质" % rail_name)
		assert_true(rail.get_node_or_null("SoftShadow") is Line2D,
			"%s 必须向桌布投下宽软阴影" % rail_name)
		assert_true(rail.get_node_or_null("InnerBevel") is Polygon2D,
			"%s 有内侧深色倒角" % rail_name)
		var glow := rail.get_node_or_null("HighlightGlow") as Line2D
		var highlight := rail.get_node_or_null("Highlight") as Line2D
		assert_not_null(glow, "%s 有宽柔光" % rail_name)
		assert_not_null(highlight, "%s 有 2px 纵向高光" % rail_name)
		if glow != null:
			assert_eq(glow.width, 8.0)
			assert_not_null(glow.gradient)
			assert_eq(glow.points.size(), 9,
				"柔光必须在渐变色标处细分，避免两端透明使整条线不可见")
		if highlight != null:
			assert_eq(highlight.width, 2.0)
			assert_not_null(highlight.gradient)
			assert_eq(highlight.points.size(), 9,
				"主高光必须在渐变色标处细分，确保中段采到不透明颜色")
		if glow != null and highlight != null:
			assert_eq(highlight.points, glow.points)


func test_single_table_frame_and_board_lines_are_structural() -> void:
	var host := Control.new()
	add_child_autofree(host)
	var stage := TableStage.build(host, 1600.0, 900.0)
	var rails := stage.get_node_or_null("TableRails") as Node2D
	assert_not_null(rails, "背景不再烘焙桌框，左右木沿必须由舞台节点提供")
	if rails != null:
		assert_eq(rails.get_child_count(), 2, "不得恢复上下木框")
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
		var river := table.discard_rivers[seat_id] as DiscardRiverView
		var tiles: Array = []
		for index in range(12):
			tiles.append(Tile.new((seat_id * 7 + index) % 34))
		river.set_tiles(tiles)
		assert_eq(river._tile_roots.size(), 12)
		for root in river._tile_roots:
			var quad := (root as Node2D).get_meta(
				"projected_quad") as PackedVector2Array
			for point in quad:
				assert_true(crowded[seat_id].has_point(point),
					"seat %d 真实牌河必须留在最拥挤公开信息区" % seat_id)


func test_center_plate_and_felt_remain_visible() -> void:
	var table: FourPlayerTable = load(
		"res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(table)
	await get_tree().process_frame
	var center := table.center_info
	var plate := center.get_node_or_null("CenterPlate") as Polygon2D
	assert_not_null(plate)
	if plate != null:
		assert_eq(plate.polygon.size(), 4)
		var top_width := plate.polygon[0].distance_to(plate.polygon[1])
		var bottom_width := plate.polygon[3].distance_to(plate.polygon[2])
		assert_lt(top_width, bottom_width,
			"中央盘顶边必须随桌面透视收窄，不能继续是正对屏幕的矩形")
		var expected := TableLayout.center_plate()["screen_aabb"] as Rect2
		var points := PackedVector2Array()
		for point in plate.polygon:
			points.append(center.to_global(point))
		var minimum := points[0]
		var maximum := points[0]
		for point in points:
			minimum = minimum.min(point)
			maximum = maximum.max(point)
		assert_true(expected.is_equal_approx(Rect2(minimum, maximum - minimum)),
			"中央盘四角必须落在 TableLayout 的真实桌面投影上")
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
