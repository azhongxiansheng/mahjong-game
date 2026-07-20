extends GutTest

# 参考站 1600×900 固定 stage 的分辨率与牌桌布局契约。

const REFERENCE_CENTER_BBOX := Rect2(696.310, 299.125, 207.380, 197.824)
const REFERENCE_RIVER_BBOXES := [
	Rect2(658.987, 505.712, 282.025, 136.336),
	Rect2(905.858, 270.134, 139.087, 259.511),
	Rect2(671.209, 177.202, 257.581, 114.060),
	Rect2(555.055, 270.134, 139.087, 259.511),
]
const REFERENCE_RIVER_TRANSFORMS := [
	{
		"position": Vector2(658.987, 505.712),
		"rotation_degrees": 0.0,
		"scale": Vector2(0.940084, 0.946778),
	},
	{
		"position": Vector2(905.858, 529.645),
		"rotation_degrees": -90.0,
		"scale": Vector2(0.865037, 0.965882),
	},
	{
		"position": Vector2(928.791, 291.262),
		"rotation_degrees": 180.0,
		"scale": Vector2(0.858605, 0.792084),
	},
	{
		"position": Vector2(694.142, 270.134),
		"rotation_degrees": 90.0,
		"scale": Vector2(0.865037, 0.965881),
	},
]
const REFERENCE_HAND_HOST_BBOXES := [
	Rect2(302.0, 778.0, 996.0, 92.0),
	Rect2(1256.798, 216.539, 98.825, 434.654),
	Rect2(558.280, 24.341, 483.441, 45.067),
	Rect2(245.722, 208.710, 98.468, 432.665),
]
const CONTROLLED_FULL_HAND_WITH_PON_BBOXES := [
	Rect2(218.5, 778.0, 996.0, 92.0),
	Rect2(1265.727, 287.331, 102.096, 452.879),
	Rect2(626.699, 24.341, 483.441, 45.067),
	Rect2(257.346, 140.869, 95.406, 415.644),
]
const REFERENCE_PON_BBOXES := [
	Rect2(1246.5, 797.5, 135.0, 53.0),
	Rect2(1289.893, 151.433, 59.806, 106.771),
	Rect2(494.917, 27.162, 110.950, 37.759),
	Rect2(180.129, 590.599, 69.488, 135.268),
]
const REFERENCE_AVATAR_RECTS := [
	Rect2(322.0, 644.0, 78.0, 78.0),
	Rect2(1417.0, 370.0, 78.0, 78.0),
	Rect2(1110.0, 85.0, 78.0, 78.0),
	Rect2(105.0, 370.0, 78.0, 78.0),
]


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


func _assert_rect_almost_eq(actual: Rect2, expected: Rect2, tolerance: float,
		label: String) -> void:
	assert_almost_eq(actual.position.x, expected.position.x, tolerance,
		"%s x" % label)
	assert_almost_eq(actual.position.y, expected.position.y, tolerance,
		"%s y" % label)
	assert_almost_eq(actual.size.x, expected.size.x, tolerance,
		"%s width" % label)
	assert_almost_eq(actual.size.y, expected.size.y, tolerance,
		"%s height" % label)


func test_design_resolution_is_reference_1600_by_900() -> void:
	assert_eq(DT.VIEW_W, 1600)
	assert_eq(DT.VIEW_H, 900)
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 1600)
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 900)
	assert_eq(ProjectSettings.get_setting("display/window/size/window_width_override"), 1600)
	assert_eq(ProjectSettings.get_setting("display/window/size/window_height_override"), 900)


func test_table_is_full_reference_stage() -> void:
	assert_eq(TableLayout.VIEW_W, 1600.0)
	assert_eq(TableLayout.VIEW_H, 900.0)
	assert_eq(TableLayout.TABLE_W, 1600.0)
	assert_eq(TableLayout.TABLE_H, 900.0)
	assert_almost_eq(TableLayout.center().x, 800.0, 0.001)
	assert_almost_eq(TableLayout.center().y, 398.037, 0.001)
	assert_eq(FourPlayerTable.TABLE_WIDTH, 1600.0)
	assert_eq(FourPlayerTable.TABLE_HEIGHT, 900.0)
	assert_eq(FourPlayerTable.ABILITY_PANEL_WIDTH, 0.0)


func test_seat_anchors_match_reference_stage() -> void:
	assert_eq(TableLayout.seat_anchor(0), Vector2(800.0, 700.0))
	assert_eq(TableLayout.seat_anchor(1), Vector2(1495.0, 370.0))
	assert_eq(TableLayout.seat_anchor(2), Vector2(800.0, 85.0))
	assert_eq(TableLayout.seat_anchor(3), Vector2(105.0, 370.0))


func test_controlled_full_hand_meld_and_avatar_bboxes_match_public_bundle() -> void:
	for seat_id in range(4):
		_assert_rect_almost_eq(TableLayout.hand_host_rect(seat_id, false),
			REFERENCE_HAND_HOST_BBOXES[seat_id], 0.001,
			"seat %d no-meld hand host" % seat_id)
		_assert_rect_almost_eq(TableLayout.hand_host_rect(seat_id, true),
			CONTROLLED_FULL_HAND_WITH_PON_BBOXES[seat_id], 0.001,
			"seat %d controlled full-hand pon host" % seat_id)
		_assert_rect_almost_eq(TableLayout.single_pon_rect(seat_id),
			REFERENCE_PON_BBOXES[seat_id], 0.001,
			"seat %d single pon" % seat_id)
		_assert_rect_almost_eq(TableLayout.avatar_rect(seat_id),
			REFERENCE_AVATAR_RECTS[seat_id], 0.001,
			"seat %d avatar" % seat_id)


func test_ai_avatar_controls_land_on_reference_rects() -> void:
	var table: FourPlayerTable = load(
		"res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(table)
	await get_tree().process_frame
	for seat_id in [1, 2, 3]:
		var portrait := table.seat_panels[seat_id]._portrait_rect as TextureRect
		assert_not_null(portrait, "seat %d portrait" % seat_id)
		if portrait == null:
			continue
		assert_null(table.seat_panels[seat_id].get_node_or_null("PortraitCard"),
			"参考 seat-avatar 没有自创 86×86 外卡")
		assert_eq(portrait.stretch_mode,
			TextureRect.STRETCH_KEEP_ASPECT_COVERED,
			"seat-avatar 必须等价 object-fit: cover")
		assert_true(portrait.clip_contents)
		var border := table.seat_panels[seat_id].get_node_or_null(
			"PortraitBorder") as Panel
		assert_not_null(border, "78×78 头像自身需要参考金软边")
		if border != null:
			assert_eq(border.size, Vector2(78, 78))
			var style := border.get_theme_stylebox("panel") as StyleBoxFlat
			assert_eq(style.border_color, Color("d9b65b66"))
			assert_eq(style.border_width_left, 2)
			assert_eq(style.corner_radius_top_left, 6)
		_assert_rect_almost_eq(_global_aabb(portrait,
			Rect2(Vector2.ZERO, portrait.size)), REFERENCE_AVATAR_RECTS[seat_id],
			0.02, "seat %d live avatar" % seat_id)


func test_side_hand_slots_are_projected_one_by_one() -> void:
	var right_first: Rect2 = TableLayout.controlled_side_hand_slot_rect(1, 0)
	var right_last: Rect2 = TableLayout.controlled_side_hand_slot_rect(1, 12)
	var left_first: Rect2 = TableLayout.controlled_side_hand_slot_rect(3, 0)
	var left_last: Rect2 = TableLayout.controlled_side_hand_slot_rect(3, 12)
	_assert_rect_almost_eq(right_first,
		Rect2(1261.194, 251.394, 47.074, 54.072), 0.01, "right first")
	_assert_rect_almost_eq(right_last,
		Rect2(1303.480, 586.663, 52.143, 64.530), 0.01, "right last")
	_assert_rect_almost_eq(left_first,
		Rect2(297.752, 208.710, 46.437, 52.808), 0.01, "left first")
	_assert_rect_almost_eq(left_last,
		Rect2(251.563, 535.848, 51.366, 62.885), 0.01, "left last")
	assert_gt(right_last.size.x, right_first.size.x,
		"perspective 使靠近镜头的末槽更宽，禁止 rigid stack")
	assert_gt(left_last.size.y, left_first.size.y,
		"左右家每槽必须分别投影")


func test_action_bar_matches_reference_action_slot() -> void:
	assert_eq(TableLayout.ACTION_BAR_Y, 700.0)
	assert_eq(TableLayout.ACTION_BAR_H, 72.0)
	assert_eq(TableLayout.ACTION_BAR_Y, TableLayout.seat_anchor(0).y)


func test_four_player_table_min_size_no_ability_gutter() -> void:
	var t: FourPlayerTable = load("res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(t)
	await get_tree().process_frame
	assert_eq(t.custom_minimum_size, Vector2(1600.0, 900.0))
	assert_false(t.ability_panel.visible, "右栏能力板应隐藏")


func test_playable_table_scene_uses_reference_stage_size() -> void:
	var table := load("res://ui/four_player_table/playable_table.tscn").instantiate() as Control
	assert_eq(table.custom_minimum_size, Vector2(1600.0, 900.0),
		"场景资源本身不得残留旧 1280×800 最小尺寸")
	add_child_autofree(table)


func test_run_hud_spans_reference_stage_width() -> void:
	var hud := load("res://ui/run/run_hud.tscn").instantiate() as Control
	add_child_autofree(hud)
	assert_eq(hud.custom_minimum_size, Vector2(1600.0, 56.0))
	var row := hud.get_node("HBox") as Control
	assert_eq(row.offset_left, 16.0)
	assert_eq(row.offset_right, 1584.0)


func test_capture_tool_uses_reference_resolution() -> void:
	var capture_script := load("res://tools/capture_screens.gd") as Script
	assert_not_null(capture_script)
	var constants := capture_script.get_script_constant_map()
	assert_eq(constants.get("CAPTURE_SIZE"), Vector2i(1600, 900))


func test_table_stage_builds_under_table() -> void:
	var t: FourPlayerTable = load("res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(t)
	await get_tree().process_frame
	var stage := t.get_node_or_null("TableStage")
	assert_not_null(stage, "应有 TableStage 舞台根")
	assert_true(stage.get_child_count() > 0, "舞台应有子层")
	assert_not_null(stage.get_node_or_null("TableFelt"), "应有 TableFelt")


func test_table_felt_is_not_covered_by_opaque_fallback() -> void:
	var t: FourPlayerTable = load("res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(t)
	await get_tree().process_frame
	var stage := t.get_node_or_null("TableStage") as Control
	assert_not_null(stage)
	var fallback := t.get_node_or_null("TableBg") as ColorRect
	assert_true(fallback == null
		or fallback.get_index() < stage.get_index()
		or fallback.color.a <= 0.01,
		"不透明 TableBg 不得排在 TableStage 上方遮掉绿毡与木框")


func test_projection_uses_public_bundle_stage_plane() -> void:
	assert_eq(TableLayout.PERSPECTIVE_DISTANCE, 1200.0)
	assert_eq(TableLayout.PERSPECTIVE_ORIGIN, Vector2(800.0, 288.0))
	assert_eq(TableLayout.TABLE_PLANE_RECT, Rect2(0.0, -140.0, 1600.0, 1040.0))
	assert_eq(TableLayout.TABLE_PLANE_ORIGIN, Vector2(800.0, 900.0))
	assert_eq(TableLayout.TABLE_PLANE_ROTATION_X_DEGREES, 18.0)
	assert_eq(TableLayout.BOARD_SIZE, Vector2(596.0, 596.0))
	assert_eq(TableLayout.BOARD_TRACKS, Vector3(144.0, 300.0, 144.0))
	assert_eq(TableLayout.BOARD_GAP, 4.0)
	assert_eq(TableLayout.RIVER_SIZE, Vector2(300.0, 144.0))
	assert_eq(TableLayout.CENTER_PLATE_SIZE, Vector2(220.0, 220.0))
	assert_eq(TableLayout.CENTER_CSS_SCALE, 1.04)
	assert_eq(TableLayout.project_table_point(Vector2(800.0, 900.0)),
		Vector2(800.0, 900.0), "平面变换原点保持不动")


func test_four_rivers_apply_projected_reference_transforms_and_global_aabbs() -> void:
	var table: FourPlayerTable = load(
		"res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(table)
	await get_tree().process_frame
	assert_eq(table.discard_rivers.size(), 4)
	for seat_id in range(4):
		var river := table.discard_rivers[seat_id] as DiscardRiver
		assert_not_null(river, "seat %d river" % seat_id)
		if river == null:
			continue
		var expected: Dictionary = REFERENCE_RIVER_TRANSFORMS[seat_id]
		assert_almost_eq(river.position.x, expected.position.x, 0.02,
			"seat %d 实例 position x" % seat_id)
		assert_almost_eq(river.position.y, expected.position.y, 0.02,
			"seat %d 实例 position y" % seat_id)
		assert_almost_eq(river.rotation_degrees,
			float(expected.rotation_degrees), 0.001,
			"seat %d 实例应用参考旋转" % seat_id)
		assert_almost_eq(river.scale.x, expected.scale.x, 0.00002,
			"seat %d 实例 scale x" % seat_id)
		assert_almost_eq(river.scale.y, expected.scale.y, 0.00002,
			"seat %d 实例 scale y" % seat_id)
		var container := river.get_node_or_null("RiverContainer") as Control
		assert_not_null(container, "seat %d 使用真实 300×144 容器" % seat_id)
		if container == null:
			continue
		var actual := _global_aabb(container,
			Rect2(Vector2.ZERO, container.size))
		_assert_rect_almost_eq(actual, REFERENCE_RIVER_BBOXES[seat_id], 0.02,
			"seat %d river bbox" % seat_id)


func test_center_keeps_220_base_plate_then_applies_projected_layout() -> void:
	assert_eq(CenterInfoPanel.PLATE_HALF, 110.0, "中心盘基础尺寸必须恢复 220×220")
	var table: FourPlayerTable = load(
		"res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(table)
	await get_tree().process_frame
	var center := table.center_info
	assert_not_null(center)
	if center == null:
		return
	var plate := center.get_node_or_null("CenterPlate") as Panel
	assert_not_null(plate)
	if plate == null:
		return
	assert_eq(plate.position, Vector2(-110.0, -110.0))
	assert_eq(plate.size, Vector2(220.0, 220.0))
	assert_almost_eq(center.position.x, REFERENCE_CENTER_BBOX.get_center().x, 0.02,
		"中心节点应用投影后 bbox 中心 x")
	assert_almost_eq(center.position.y, REFERENCE_CENTER_BBOX.get_center().y, 0.02,
		"中心节点应用投影后 bbox 中心 y")
	assert_almost_eq(center.scale.x,
		REFERENCE_CENTER_BBOX.size.x / 220.0, 0.00002,
		"中心节点应用 220 基础盘到投影 bbox 的 x 缩放")
	assert_almost_eq(center.scale.y,
		REFERENCE_CENTER_BBOX.size.y / 220.0, 0.00002,
		"中心节点应用 220 基础盘到投影 bbox 的 y 缩放")
	_assert_rect_almost_eq(_global_aabb(plate, Rect2(Vector2.ZERO, plate.size)),
		REFERENCE_CENTER_BBOX, 0.02, "center bbox")
