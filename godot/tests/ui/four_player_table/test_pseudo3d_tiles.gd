extends GutTest

# 公开参考 CSS 的 2D 伪 3D 牌体契约。这里只验证可观测尺寸、边缘、阴影与位移，
# 不把参考站素材带进仓库。

const SEAT_PANEL_SCENE := preload("res://ui/four_player_table/seat_panel.tscn")


func _face_texture() -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


func _seat_with_tiles(seat_id: int, count: int) -> Seat:
	var seat := Seat.new(seat_id, TileId.E)
	for i in range(count):
		seat.hand.add(Tile.new(i % 34, false, Tile.NO_OWNER, seat_id * 100 + i))
	return seat


func _named_child(parent: Node, child_name: String) -> Node:
	for child in parent.get_children():
		if child.name == child_name:
			return child
	return null


func _assert_rect_almost_eq(actual: Rect2, expected: Rect2, tolerance: float,
		label: String) -> void:
	assert_almost_eq(actual.position.x, expected.position.x, tolerance, "%s x" % label)
	assert_almost_eq(actual.position.y, expected.position.y, tolerance, "%s y" % label)
	assert_almost_eq(actual.size.x, expected.size.x, tolerance, "%s w" % label)
	assert_almost_eq(actual.size.y, expected.size.y, tolerance, "%s h" % label)


func _assert_vector_almost_eq(actual: Vector2, expected: Vector2,
		tolerance: float, label: String) -> void:
	assert_almost_eq(actual.x, expected.x, tolerance, "%s x" % label)
	assert_almost_eq(actual.y, expected.y, tolerance, "%s y" % label)


func _assert_white_split_face(layer: Polygon2D, fill_from: Vector2,
		fill_to: Vector2, label: String) -> void:
	assert_not_null(layer, "%s 白面必须独立成几何面片" % label)
	if layer == null:
		return
	assert_true(layer.antialiased, "%s 圆弧边缘必须抗锯齿" % label)
	var raw_points: PackedVector2Array = layer.get_meta(
		SeatPanel.CUBE_RAW_POINTS_META, PackedVector2Array())
	assert_gt(raw_points.size(), 2, "%s 白面必须有闭合轮廓" % label)
	var axis := fill_to - fill_from
	var boundary_points := 0
	for point in raw_points:
		var gradient_t := (point - fill_from).dot(axis) / axis.length_squared()
		assert_gte(gradient_t, 0.499,
			"%s 禁止白面越过参考 50%% 分界" % label)
		if absf(gradient_t - 0.5) <= 0.001:
			boundary_points += 1
	assert_gte(boundary_points, 2, "%s 必须共享一条精确分界边" % label)


func _assert_no_duplicate_outline_points(layer: Polygon2D, label: String) -> void:
	var raw_points: PackedVector2Array = layer.get_meta(
		SeatPanel.CUBE_RAW_POINTS_META, PackedVector2Array())
	for index in range(raw_points.size()):
		var next_index := (index + 1) % raw_points.size()
		assert_gt(raw_points[index].distance_to(raw_points[next_index]), 0.001,
			"%s 禁止连续重复点制造退化三角形" % label)


func _assert_polygon_contains_point(layer: Polygon2D, expected: Vector2,
		label: String) -> void:
	var raw_points: PackedVector2Array = layer.get_meta(
		SeatPanel.CUBE_RAW_POINTS_META, PackedVector2Array())
	var found := false
	for point in raw_points:
		if point.distance_to(expected) <= 0.001:
			found = true
			break
	assert_true(found, "%s 必须包含参考圆弧采样点 %s" % [label, expected])


func _assert_svg_round_lines(cube: Control) -> void:
	for child in cube.get_children():
		if child is not Line2D:
			continue
		var line := child as Line2D
		assert_eq(line.begin_cap_mode, Line2D.LINE_CAP_ROUND,
			"%s 起点必须对齐 SVG round cap" % line.name)
		assert_eq(line.end_cap_mode, Line2D.LINE_CAP_ROUND,
			"%s 终点必须对齐 SVG round cap" % line.name)
		assert_eq(line.joint_mode, Line2D.LINE_JOINT_ROUND,
			"%s 折点必须对齐 SVG round join" % line.name)


func _rect_union(rects: Array[Rect2]) -> Rect2:
	assert_false(rects.is_empty())
	var result := rects[0]
	for rect in rects.slice(1):
		result = result.merge(rect)
	return result


func test_reference_tile_sizes_are_exact() -> void:
	assert_eq(Vector2(SeatPanel.PLAYER_HAND_TILE_W, SeatPanel.PLAYER_HAND_TILE_H),
		Vector2(66, 92), "自家 tile--xl")
	assert_eq(SeatPanel.opponent_hand_tile_size(2), Vector2(38, 55),
		"上家牌背实测尺寸")
	assert_eq(SeatPanel.opponent_hand_tile_size(1), Vector2(46.71, 66.63),
		"右家走 bundle q0/aw SVG 立方体 Q3 包围盒")
	assert_eq(SeatPanel.opponent_hand_tile_size(3), Vector2(46.71, 66.63),
		"左家只镜像同一 SVG 立方体")
	assert_eq(Vector2(DiscardRiver.TILE_W, DiscardRiver.TILE_H), Vector2(39, 52),
		"河牌覆盖参考 .river .tile--sm")
	assert_eq(Vector2(MeldArea.TILE_W, MeldArea.TILE_H), Vector2(40, 53),
		"副露覆盖参考 .melds .tile--sm")


func test_player_standing_edges_and_final_bbox_match_reference() -> void:
	var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
	panel.position = TableLayout.seat_anchor(0)
	panel.set_seat_id(0)
	add_child_autofree(panel)
	await get_tree().process_frame
	panel.bind_seat(_seat_with_tiles(0, 13))
	await get_tree().process_frame
	assert_eq(panel._hand_slots.size(), 13)
	var first: Control = panel._hand_slots[0]
	assert_eq(first.size, Vector2(66, 92))
	var green := first.get_node_or_null("EdgeBack") as Control
	var white := first.get_node_or_null("EdgeFace") as Control
	assert_not_null(green)
	assert_not_null(white)
	assert_true(green is Panel, "before 顶边需要 StyleBox 圆角")
	assert_true(white is Panel, "after 顶棱需要 StyleBox 圆角")
	assert_eq(green.position, Vector2(0, -10), "before 绿背顶边 top=-10")
	assert_eq(green.size, Vector2(66, 10), "before 绿背顶边 height=10")
	assert_eq(white.position, Vector2(0, -5), "after 灰白棱 top=-5")
	assert_eq(white.size, Vector2(66, 10), "after 必须伸入牌面 5px 托住透明圆角")
	if green is Panel and white is Panel:
		var green_style := (green as Panel).get_theme_stylebox("panel") as StyleBoxFlat
		var white_style := (white as Panel).get_theme_stylebox("panel") as StyleBoxFlat
		assert_not_null(green_style)
		assert_not_null(white_style)
		if green_style != null and white_style != null:
			assert_eq(green_style.corner_radius_top_left, 5)
			assert_eq(green_style.corner_radius_top_right, 5)
			assert_eq(white_style.corner_radius_top_left, 5)
			assert_eq(white_style.corner_radius_top_right, 5)
	var tile := first.get_node("Tile") as CardTileBack
	var tile_style := tile.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(tile_style)
	if tile_style != null:
		assert_eq(tile_style.border_width_left, 0,
			"完整牌壳 PNG 禁止再叠第二层边框制造角缺口")
		assert_eq(tile_style.border_color, Color(0, 0, 0, 0.4),
			"参考 #0006 禁止再露出纯黑三角")
		assert_eq(tile_style.corner_radius_top_left, 6,
			"80px 原始牌体缩放后对应参考 5px 顶圆角")
		assert_eq(tile_style.corner_radius_top_right, 6)
		assert_eq(tile_style.corner_radius_bottom_left, 8,
			"80px 原始牌体缩放后对应参考 6px 底圆角")
		assert_eq(tile_style.corner_radius_bottom_right, 8)
	var rects: Array[Rect2] = panel.get_deal_target_rects()
	assert_eq(rects.size(), 13)
	assert_almost_eq(rects[0].position.y, 778.0, 0.01)
	assert_almost_eq(rects[0].end.y, 870.0, 0.01,
		"自家手牌底边距 1600x900 舞台底部 30px")


func test_deal_target_rects_use_real_slots_and_survive_hidden_row() -> void:
	var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
	panel.position = Vector2(120, 80)
	panel.set_seat_id(2)
	add_child_autofree(panel)
	await get_tree().process_frame
	panel.bind_seat(_seat_with_tiles(2, 12))
	assert_true(panel.get_deal_target_rects().is_empty(), "不足 13 张不提供静态猜测坐标")
	panel.bind_seat(_seat_with_tiles(2, 13))
	await get_tree().process_frame
	var visible_rects: Array[Rect2] = panel.get_deal_target_rects()
	assert_eq(visible_rects.size(), 13)
	panel.set_hand_row_visible(false)
	var hidden_rects: Array[Rect2] = panel.get_deal_target_rects()
	assert_eq(hidden_rects, visible_rects, "隐藏只改 visible，真实 slot 几何仍可测")
	assert_almost_eq(hidden_rects[0].size.x, 38.0, 0.01)
	assert_almost_eq(hidden_rects[0].size.y, 55.0, 0.01)


func test_deal_target_rects_cover_four_real_hand_directions() -> void:
	var expected_sizes := [Vector2(66, 92), Vector2(46.71, 66.63),
		Vector2(38, 55), Vector2(46.71, 66.63)]
	for seat_id in range(4):
		var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
		panel.position = TableLayout.seat_anchor(seat_id)
		panel.set_seat_id(seat_id)
		add_child_autofree(panel)
		await get_tree().process_frame
		panel.bind_seat(_seat_with_tiles(seat_id, 13))
		await get_tree().process_frame
		var rects: Array[Rect2] = panel.get_deal_target_rects()
		assert_eq(rects.size(), 13, "seat %d 必须来自 13 个真实 slot" % seat_id)
		for i in range(13):
			var slot: Control = panel._deal_slots[i]
			var actual_center := slot.get_global_transform() * (slot.size * 0.5)
			assert_almost_eq(rects[i].get_center().x, actual_center.x, 0.01)
			assert_almost_eq(rects[i].get_center().y, actual_center.y, 0.01)
		assert_almost_eq(rects[0].size.x, expected_sizes[seat_id].x, 0.01)
		assert_almost_eq(rects[0].size.y, expected_sizes[seat_id].y, 0.01)


func test_reference_hand_slots_apply_real_screen_geometry() -> void:
	var expected_first := {
		1: Rect2(1261.194, 251.394, 47.074, 54.072),
		2: Rect2(1010.583, 24.341, 31.137, 45.067),
		3: Rect2(297.752, 208.710, 46.437, 52.808),
	}
	var expected_last := {
		1: Rect2(1303.480, 586.663, 52.143, 64.530),
		2: Rect2(607.443, 24.341, 31.137, 45.067),
		3: Rect2(251.563, 535.848, 51.366, 62.885),
	}
	for seat_id in [1, 2, 3]:
		var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
		panel.position = TableLayout.seat_anchor(seat_id)
		panel.set_seat_id(seat_id)
		add_child_autofree(panel)
		await get_tree().process_frame
		panel.bind_seat(_seat_with_tiles(seat_id, 13))
		panel.apply_reference_hand_layout()
		await get_tree().process_frame
		var rects: Array[Rect2] = panel.get_deal_target_rects()
		_assert_rect_almost_eq(rects[0], expected_first[seat_id], 0.02,
			"seat %d first slot" % seat_id)
		_assert_rect_almost_eq(rects[12], expected_last[seat_id], 0.02,
			"seat %d last slot" % seat_id)


func test_side_hand_hosts_leave_avatar_info_clear() -> void:
	for seat_id in [1, 3]:
		var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
		panel.position = TableLayout.seat_anchor(seat_id)
		panel.set_seat_id(seat_id)
		add_child_autofree(panel)
		await get_tree().process_frame
		panel.bind_seat(_seat_with_tiles(seat_id, 13))
		for meld_extent in [0.0, 137.0]:
			panel.apply_reference_hand_layout(meld_extent)
			await get_tree().process_frame
			var hand_rect := panel.get_reference_hand_host_rect().grow(4.0)
			for info_name in ["Score"]:
				var info := panel.get_node(info_name) as Control
				var info_rect := SeatPanel._control_global_aabb(info)
				assert_false(hand_rect.intersects(info_rect),
					"seat %d meld %.0f 手牌不得遮挡 %s" % [
						seat_id, meld_extent, info_name])


func test_side_seat_labels_face_table_inward_like_reference() -> void:
	var expected_name_rects := {
		1: Rect2(1354.0, 406.0, 58.0, 34.0),
		3: Rect2(188.0, 406.0, 58.0, 34.0),
	}
	for seat_id in [1, 3]:
		var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
		panel.position = TableLayout.seat_anchor(seat_id)
		panel.set_seat_id(seat_id)
		add_child_autofree(panel)
		await get_tree().process_frame
		var avatar_rect := TableLayout.avatar_rect(seat_id)
		var name_column := panel.get_node("VBox") as Control
		var name_rect := SeatPanel._control_global_aabb(name_column)
		_assert_rect_almost_eq(name_rect, expected_name_rects[seat_id], 0.02,
			"seat %d inward name column" % seat_id)
		assert_eq(panel._label_seat_info.text, "AI %d" % seat_id,
			"左右家沿用参考短名字，不再向侧边塞入风位与打法长串")
		if seat_id == 1:
			assert_almost_eq(name_rect.end.x, avatar_rect.position.x - 5.0, 0.02,
				"右家名字须在头像左侧留 5px")
		else:
			assert_almost_eq(name_rect.position.x, avatar_rect.end.x + 5.0, 0.02,
				"左家名字须在头像右侧留 5px")
		var score := panel._label_score as Control
		assert_eq(score.get_parent(), panel,
			"左右家分数属于 avatar-col，不和名字一起挤向屏幕边缘")
		_assert_rect_almost_eq(SeatPanel._control_global_aabb(score),
			Rect2(avatar_rect.position + Vector2(0.0, 81.0), Vector2(78.0, 21.0)),
			0.02, "seat %d score below avatar" % seat_id)
		assert_null(panel.get_node_or_null("InfoChip"),
			"参考左右家名字没有自创长胶囊")


func test_top_seat_label_matches_reference_short_name_layout() -> void:
	var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
	panel.position = TableLayout.seat_anchor(2)
	panel.set_seat_id(2)
	add_child_autofree(panel)
	await get_tree().process_frame
	panel.set_ai_persona("金老", "防守",
		"res://tests/_fixtures/portrait_fixture.png")
	await get_tree().process_frame
	assert_eq(panel.cluster_anchor(), Vector2(1110.0, 85.0),
		"对家头像锚点保持参考坐标")
	var portrait := panel._portrait_rect as TextureRect
	assert_not_null(portrait)
	if portrait == null:
		return
	var avatar_rect := SeatPanel._control_global_aabb(portrait)
	_assert_rect_almost_eq(avatar_rect, Rect2(1110.0, 85.0, 78.0, 78.0),
		0.02, "top avatar")
	var name_column := panel.get_node("VBox") as Control
	var name_rect := SeatPanel._control_global_aabb(name_column)
	_assert_rect_almost_eq(name_rect, Rect2(1193.0, 120.5, 58.0, 31.0),
		0.02, "top short name column")
	assert_almost_eq(name_rect.position.x, avatar_rect.end.x + 5.0, 0.02,
		"对家短名字位于头像右侧 5px")
	assert_eq(panel._label_seat_info.text, "金老",
		"对家只显示短名字，不拼接风位、庄家状态或打法")
	var score := panel._label_score as Control
	assert_eq(score.get_parent(), panel,
		"对家分数独立属于 avatar-col")
	_assert_rect_almost_eq(SeatPanel._control_global_aabb(score),
		Rect2(1110.0, 166.0, 78.0, 21.0), 0.02,
		"top score below avatar")
	assert_null(panel.get_node_or_null("InfoChip"),
		"参考对家名字没有自创长胶囊")


func test_bottom_seat_label_matches_reference_structure_and_clearance() -> void:
	var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
	panel.position = TableLayout.seat_anchor(0)
	panel.set_seat_id(0)
	add_child_autofree(panel)
	await get_tree().process_frame
	panel.set_ai_persona("林夜彻", "",
		"res://tests/_fixtures/portrait_fixture.png")
	panel.set_active(true)
	panel.bind_seat(_seat_with_tiles(0, 13))
	panel.apply_reference_hand_layout()
	await get_tree().process_frame
	assert_eq(panel.cluster_anchor(), TableLayout.avatar_rect(0).position,
		"修信息遮挡不能挪动参考头像锚点")
	var portrait := panel._portrait_rect as TextureRect
	assert_not_null(portrait)
	if portrait == null:
		return
	var portrait_rect := SeatPanel._control_global_aabb(portrait)
	_assert_rect_almost_eq(portrait_rect, TableLayout.avatar_rect(0), 0.02,
		"bottom avatar")
	assert_null(panel.get_node_or_null("InfoChip"),
		"参考 bottom seat-label 没有自创胶囊底条")
	assert_null(panel.get_node_or_null("ActiveGlow"),
		"当前态只增强 78x78 头像自身边框")
	var border := panel.get_node_or_null("PortraitBorder") as Panel
	assert_not_null(border)
	if border != null:
		_assert_rect_almost_eq(SeatPanel._control_global_aabb(border),
			portrait_rect, 0.02, "active portrait border")
		var border_style := border.get_theme_stylebox("panel") as StyleBoxFlat
		assert_eq(border_style.border_color, Color("ffd97a"),
			"active 只把头像自身边框变为参考金色")
	var score := panel._label_score as Control
	assert_eq(score.get_parent(), panel,
		"分数属于 avatar-col，不再和名字堆进同一个 VBox")
	assert_eq(panel._label_score.text, "25000 分",
		"参考 seat-label 分数保留分值单位")
	var score_rect := SeatPanel._control_global_aabb(score)
	assert_almost_eq(score_rect.position.y, portrait_rect.end.y + 3.0, 0.02,
		"分数位于头像下方 3px")
	assert_almost_eq(score_rect.get_center().x, portrait_rect.get_center().x,
		0.02, "分数与头像水平居中")
	var name_column := panel.get_node("VBox") as Control
	var name_rect := SeatPanel._control_global_aabb(name_column)
	assert_almost_eq(name_rect.position.x, portrait_rect.end.x + 5.0, 0.02,
		"名字主列位于头像右侧 5px")
	assert_almost_eq(name_rect.position.y, 678.0, 0.02,
		"名字主列沿用参考 seat-label 垂直居中坐标")
	panel.set_furiten(true)
	panel.set_tenpai(true)
	panel.set_ippatsu(true)
	await get_tree().process_frame
	for badge in [panel._badge_furiten, panel._badge_tenpai,
			panel._badge_ippatsu]:
		assert_not_null(badge)
		if badge == null:
			continue
		var badge_rect := SeatPanel._control_global_aabb(badge as Control)
		assert_false(badge_rect.intersects(name_rect),
			"bottom 状态徽章不得覆盖名字主列")
		assert_gte(badge_rect.position.x, name_rect.end.x + 5.0,
			"bottom 状态徽章接在 name-row 右侧")
		assert_almost_eq(badge_rect.get_center().y, name_rect.get_center().y,
			0.02, "bottom 状态徽章与 name-row 垂直居中")
	var hand_host := panel.get_reference_hand_host_rect()
	_assert_rect_almost_eq(hand_host, Rect2(302, 778, 996, 92), 0.02,
		"bottom hand host")
	var standing_edge_y := hand_host.position.y - 10.0
	assert_gte(standing_edge_y - score_rect.end.y, 20.0,
		"分数与牌顶棱至少保留参考 20px 净空")
	panel.set_score(26000)
	var score_delta: Label = null
	for child in panel.get_children():
		if child is Label and (child as Label).text == "+1000":
			score_delta = child as Label
			break
	assert_not_null(score_delta)
	if score_delta != null:
		var delta_rect := SeatPanel._control_global_aabb(score_delta)
		assert_almost_eq(delta_rect.get_center().x, score_rect.get_center().x,
			0.02, "分数飘字与 avatar-col 水平居中")
	await wait_seconds(1.6)


func test_top_hand_back_stays_upright_after_seat_rotation() -> void:
	var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
	panel.position = TableLayout.seat_anchor(2)
	panel.set_seat_id(2)
	add_child_autofree(panel)
	await get_tree().process_frame
	panel.bind_seat(_seat_with_tiles(2, 13))
	panel.apply_reference_hand_layout()
	await get_tree().process_frame
	var back := panel._deal_slots[0].get_node("Back") as TextureRect
	assert_almost_eq(back.rotation_degrees, -180.0, 0.001,
		"顶家牌背须抵消 SeatPanel 的 180°，白棱才能留在屏幕顶部")
	var top_mid := back.get_global_transform() * Vector2(back.size.x * 0.5, 0.0)
	var bottom_mid := back.get_global_transform() * Vector2(
		back.size.x * 0.5, back.size.y)
	assert_lt(top_mid.y, bottom_mid.y, "顶家贴图 local top 必须仍是屏幕 top")


func test_side_hand_cube_vertices_follow_table_plane_projection() -> void:
	for seat_id in [1, 3]:
		var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
		panel.position = TableLayout.seat_anchor(seat_id)
		panel.set_seat_id(seat_id)
		add_child_autofree(panel)
		await get_tree().process_frame
		panel.bind_seat(_seat_with_tiles(seat_id, 13))
		panel.apply_reference_hand_layout()
		await get_tree().process_frame
		for slot_index in [0, 6, 12]:
			var cube := panel._deal_slots[slot_index].get_node("CubeVisual") as Control
			var cube_top := cube.get_node("CubeTop") as Polygon2D
			var raw_origin := TableLayout.side_hand_slot_raw_origin_for_state(
				seat_id, slot_index, 13)
			var raw_points: PackedVector2Array = cube_top.get_meta(
				SeatPanel.CUBE_RAW_POINTS_META)
			assert_eq(cube_top.polygon.size(), raw_points.size())
			for point_index in range(raw_points.size()):
				var raw_point := raw_points[point_index]
				if seat_id == 3:
					raw_point.x = TableLayout.SIDE_HAND_RAW_SIZE.x - raw_point.x
				var actual := cube_top.get_global_transform() \
					* cube_top.polygon[point_index]
				var expected := TableLayout.project_table_point(
					raw_origin + raw_point)
				_assert_vector_almost_eq(actual, expected, 0.05,
					"seat %d slot %d CubeTop point %d" % [
						seat_id, slot_index, point_index])


func test_player_drawn_hand_and_pon_reflow_match_reference() -> void:
	var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
	panel.position = TableLayout.seat_anchor(0)
	panel.set_seat_id(0)
	add_child_autofree(panel)
	await get_tree().process_frame
	var seat := _seat_with_tiles(0, 14)
	seat.last_drawn_instance_id = seat.hand._tiles[-1].instance_id
	panel.bind_seat(seat)
	panel.apply_reference_hand_layout()
	await wait_seconds(0.22)
	var rects: Array[Rect2] = []
	for slot in panel._hand_slots:
		rects.append(SeatPanel._control_global_aabb(slot as Control))
	var union := rects[0]
	for rect in rects.slice(1):
		union = union.merge(rect)
	_assert_rect_almost_eq(union, Rect2(302, 778, 996, 92), 0.02,
		"bottom 13 + drawn")
	panel.apply_reference_hand_layout(135.0)
	await get_tree().process_frame
	rects.clear()
	for slot in panel._hand_slots:
		rects.append(SeatPanel._control_global_aabb(slot as Control))
	union = rects[0]
	for rect in rects.slice(1):
		union = union.merge(rect)
	_assert_rect_almost_eq(union, Rect2(218.5, 778, 996, 92), 0.02,
		"bottom hand shifts with pon")


func test_opponent_drawn_visual_slots_fill_reserved_hand_hosts() -> void:
	for seat_id in [1, 2, 3]:
		var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
		panel.position = TableLayout.seat_anchor(seat_id)
		panel.set_seat_id(seat_id)
		add_child_autofree(panel)
		await get_tree().process_frame
		var seat := _seat_with_tiles(seat_id, 14)
		seat.last_drawn_instance_id = seat.hand._tiles[-1].instance_id
		panel.bind_seat(seat)
		panel.apply_reference_hand_layout()
		await get_tree().process_frame
		var visual_rects: Array[Rect2] = panel.get_visual_hand_rects()
		assert_eq(visual_rects.size(), 14, "seat %d 必须保留14个视觉槽" % seat_id)
		_assert_rect_almost_eq(_rect_union(visual_rects),
			TableLayout.HAND_HOST_RECTS[seat_id], 0.02,
			"seat %d 13+drawn host" % seat_id)
		assert_eq(panel.get_deal_target_rects().size(), 13,
			"seat %d 发牌 target 仍只能是基础13槽" % seat_id)
		if seat_id == 1 or seat_id == 3:
			var drawn_slot: Control = panel._visual_hand_slots[
				0 if seat_id == 1 else 13]
			assert_true(bool(drawn_slot.get_meta("is_drawn")),
				"side drawn slot 必须显式标记")
			assert_ne(drawn_slot.scale, Vector2.ONE,
				"side drawn slot 禁止停留旧 rigid scale")
			_assert_rect_almost_eq(
				SeatPanel._control_global_aabb(drawn_slot),
				TableLayout.controlled_side_hand_drawn_slot_rect(seat_id), 0.02,
				"seat %d projected drawn slot" % seat_id)


func test_opponent_hand_screen_gaps_match_reference_flex_layout() -> void:
	var expected_step := {1: 32.0, 2: 41.0, 3: 32.0}
	for seat_id in [1, 2, 3]:
		var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
		panel.position = TableLayout.seat_anchor(seat_id)
		panel.set_seat_id(seat_id)
		add_child_autofree(panel)
		await get_tree().process_frame
		panel.bind_seat(_seat_with_tiles(seat_id, 13))
		await get_tree().process_frame
		var rects: Array[Rect2] = panel.get_deal_target_rects()
		var delta := rects[1].get_center() - rects[0].get_center()
		var observed_step := absf(delta.x) + absf(delta.y)
		assert_almost_eq(observed_step, expected_step[seat_id], 0.01,
			"上家 38+3；左右 SVG axisA 30 + gap 2")


func test_side_hand_uses_reference_cube_faces_and_left_mirror() -> void:
	for seat_id in [1, 3]:
		var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
		panel.set_seat_id(seat_id)
		add_child_autofree(panel)
		await get_tree().process_frame
		panel.bind_seat(_seat_with_tiles(seat_id, 13))
		var cube := panel._deal_slots[0].get_node_or_null("CubeVisual") as Control
		assert_not_null(cube, "正常左右家必须走 q0/aw 等价立方体，不走 28×42 CSS fallback")
		if cube == null:
			continue
		for face_name in ["CubeBack", "CubeTop", "CubeSide", "CubeSideShadow"]:
			assert_not_null(cube.get_node_or_null(face_name), "缺 bundle 面: %s" % face_name)
		assert_eq(cube.scale.x, -1.0 if seat_id == 3 else 1.0,
			"左家只做 scaleX(-1) 镜像")


func test_side_cube_translates_svg_layers_and_top_bottom_branches() -> void:
	var top := SeatPanel.make_reference_side_cube(false, true, false)
	var middle := SeatPanel.make_reference_side_cube(false, false, false)
	var bottom := SeatPanel.make_reference_side_cube(false, false, true)
	add_child_autofree(top)
	add_child_autofree(middle)
	add_child_autofree(bottom)
	for cube in [top, middle, bottom]:
		for layer_name in ["ContactLeft", "CubeTop", "CubeTopWhite", "CubeBack",
				"CubeSide", "CubeSideWhite", "CubeSideShadow", "CubeOutline", "BevelA"]:
			assert_not_null(cube.get_node_or_null(layer_name),
				"aw() 绘制层缺失: %s" % layer_name)
		var top_green := cube.get_node("CubeTop") as Polygon2D
		assert_null(top_green.texture,
			"硬分色不能再依赖透视后会变形的 UV 渐变")
		assert_eq(top_green.color, Color("2c5e3f"))
		for face_name in ["CubeTop", "CubeBack", "CubeSide"]:
			_assert_no_duplicate_outline_points(cube.get_node(face_name) as Polygon2D,
				face_name)
		assert_true((cube.get_node("CubeSideShadow") as Polygon2D).texture is GradientTexture2D,
			"侧面暗化必须沿 O→C 渐变，不能退化成纯色蒙版")
		_assert_white_split_face(cube.get_node_or_null("CubeTopWhite") as Polygon2D,
			Vector2(17.21, 32.0), Vector2(44.71, 32.0), "CubeTopWhite")
		_assert_white_split_face(cube.get_node_or_null("CubeSideWhite") as Polygon2D,
			Vector2(17.21, 32.0), Vector2(39.801309, 42.530610),
			"CubeSideWhite")
		_assert_svg_round_lines(cube)
	assert_null(top.get_node_or_null("StackSeam"), "isTop 不画与上一张之间的暗面")
	assert_null(top.get_node_or_null("SeamShadow"), "isTop 不画牌缝影")
	for cube in [top, middle]:
		assert_lt(cube.get_node("EdgeMV0").get_index(),
			cube.get_node("BevelA").get_index(),
			"参考 SVG 先画暗边，再叠 round-cap 高光")
	assert_not_null(middle.get_node_or_null("StackSeam"))
	assert_not_null(middle.get_node_or_null("SeamShadow"))
	assert_null(middle.get_node_or_null("ContactBottom"), "非 isBottom 不画底接触影")
	assert_not_null(bottom.get_node_or_null("ContactBottom"), "isBottom 画 6px 底接触影")
	assert_not_null(bottom.get_node_or_null("EdgeAB"))
	assert_not_null(bottom.get_node_or_null("EdgeBC"))
	assert_not_null(bottom.get_node_or_null("EdgeCA"))
	assert_not_null(bottom.get_node_or_null("BevelB"))
	assert_not_null(bottom.get_node_or_null("BevelC"))
	assert_lt(bottom.get_node("EdgeCA").get_index(),
		bottom.get_node("BevelA").get_index(),
		"底张三条暗边必须先于高光绘制")
	assert_lt(bottom.get_node("BevelA").get_index(),
		bottom.get_node("BevelB").get_index())
	assert_lt(bottom.get_node("BevelB").get_index(),
		bottom.get_node("BevelC").get_index())
	assert_gt((bottom.get_node("CubeBack") as Polygon2D).polygon.size(), 4,
		"isBottom 的 C 角必须按 6px quadratic round 采样，不能仍是尖角四边形")
	var bottom_white := bottom.get_node_or_null("CubeSideWhite") as Polygon2D
	assert_not_null(bottom_white)
	if bottom_white != null:
		_assert_polygon_contains_point(bottom_white,
			Vector2(32.034940, 59.191795), "底张白面 BC start")
		_assert_polygon_contains_point(bottom_white,
			Vector2(28.633735, 63.270449), "底张白面 BC quadratic midpoint")
		_assert_polygon_contains_point(bottom_white,
			Vector2(23.5, 64.63), "底张白面 BC end")


func test_side_hand_slots_follow_q0_reserved_drawn_slot_formula() -> void:
	var expected_x := {
		1: [-44.0, -428.0], # parent -90° 后对应 host y=44...428
		3: [0.0, 384.0],    # 左家基础槽 y=0...384，末尾预留摸牌槽
	}
	for seat_id in [1, 3]:
		var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
		panel.set_seat_id(seat_id)
		add_child_autofree(panel)
		await get_tree().process_frame
		panel.bind_seat(_seat_with_tiles(seat_id, 13))
		assert_eq(panel._deal_slots.size(), 13)
		assert_almost_eq(panel._deal_slots[0].position.x, expected_x[seat_id][0], 0.001)
		assert_almost_eq(panel._deal_slots[12].position.x, expected_x[seat_id][1], 0.001)
		assert_eq(panel._hand_tile_row.get_meta("r3d_host_size"),
			Vector2(46.71, 494.63), "count=13 时 q0 host 尺寸固定")


func test_side_hand_drawn_tile_uses_reference_reserved_end_slot() -> void:
	for seat_id in [1, 3]:
		var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
		panel.set_seat_id(seat_id)
		add_child_autofree(panel)
		await get_tree().process_frame
		var seat := _seat_with_tiles(seat_id, 14)
		seat.last_drawn_instance_id = seat.hand._tiles[-1].instance_id
		panel.bind_seat(seat)
		assert_eq(panel._hand_tile_row.get_child_count(), 14,
			"有摸牌时 q0 仍是固定 14 槽且全部可见")
		var drawn_slot: Control = panel._hand_tile_row.get_child(0 if seat_id == 1 else 13)
		assert_eq(drawn_slot.position.x, 0.0 if seat_id == 1 else 428.0,
			"右家摸牌占 index 0；左家摸牌占 index 13 + 12px")
		var drawn_cube := drawn_slot.get_node("CubeVisual") as Control
		assert_true(bool(drawn_cube.get_meta("is_top")))
		assert_true(bool(drawn_cube.get_meta("is_bottom")))


func test_hover_and_lifted_offsets_follow_reference_state_machine() -> void:
	var tile := CardTileBack.new()
	tile.position = Vector2(20, 100)
	add_child_autofree(tile)
	tile.set_clickable(true)
	tile._on_mouse_enter()
	await wait_seconds(0.20)
	assert_almost_eq(tile.position.y, 93.0, 0.05, "hover translateY(-7px)")
	tile._on_mouse_exit()
	await wait_seconds(0.20)
	tile.set_lifted(true)
	await wait_seconds(0.20)
	assert_almost_eq(tile.position.y, 86.0, 0.05, "选中 translateY(-14px)")
	tile._on_mouse_enter()
	await wait_seconds(0.20)
	assert_almost_eq(tile.position.y, 78.0, 0.05,
		"参考 lifted + clickable:hover 的最终 translateY(-22px)")
	tile._on_mouse_exit()
	await wait_seconds(0.20)
	assert_almost_eq(tile.position.y, 86.0, 0.05)
	tile.set_lifted(false)
	await wait_seconds(0.20)
	assert_almost_eq(tile.position.y, 100.0, 0.05)


func test_card_base_uses_reference_double_shadow() -> void:
	var tile := CardTileBack.new()
	add_child_autofree(tile)
	await get_tree().process_frame
	var sharp := tile.get_theme_stylebox("panel") as StyleBoxFlat
	var soft := tile.get_node_or_null("SoftShadow") as Panel
	assert_not_null(sharp)
	assert_not_null(soft)
	assert_eq(sharp.shadow_offset, Vector2(0, 2))
	assert_eq(sharp.shadow_size, 3)
	var soft_style := soft.get_theme_stylebox("panel") as StyleBoxFlat
	assert_eq(soft_style.shadow_offset, Vector2(0, 4))
	assert_eq(soft_style.shadow_size, 6)


func test_river_depth_layers_follow_all_four_seat_directions() -> void:
	var expected := {
		0: {"green_pos": Vector2(0, 52), "green_size": Vector2(39, 6),
			"white_pos": Vector2(0, 49), "white_size": Vector2(39, 7),
			"sharp": Vector2(0, 7), "soft": Vector2(0, 9)},
		1: {"green_pos": Vector2(-6, 0), "green_size": Vector2(6, 52),
			"white_pos": Vector2(-4, 0), "white_size": Vector2(7, 52),
			"sharp": Vector2(-7, 0), "soft": Vector2(-9, 0)},
		2: {"green_pos": Vector2(0, -6), "green_size": Vector2(39, 6),
			"white_pos": Vector2(0, -4), "white_size": Vector2(39, 7),
			"sharp": Vector2(0, -7), "soft": Vector2(0, -9)},
		3: {"green_pos": Vector2(39, 0), "green_size": Vector2(6, 52),
			"white_pos": Vector2(36, 0), "white_size": Vector2(7, 52),
			"sharp": Vector2(7, 0), "soft": Vector2(9, 0)},
	}
	for seat_id in range(4):
		var river := DiscardRiver.new()
		add_child_autofree(river)
		river.set_seat_id(seat_id)
		river._spawn_tile(_face_texture(), 0, 0, false, false, false, false, TileId.W1)
		var green := _named_child(river, "GreenSide") as ColorRect
		var white := _named_child(river, "WhiteSide") as ColorRect
		var sharp := _named_child(river, "TileShadowSharp") as Panel
		var soft := _named_child(river, "TileShadowSoft") as Panel
		assert_not_null(green)
		assert_not_null(white)
		assert_eq(green.position, expected[seat_id]["green_pos"])
		assert_eq(green.size, expected[seat_id]["green_size"])
		assert_eq(white.position, expected[seat_id]["white_pos"])
		assert_eq(white.size, expected[seat_id]["white_size"])
		assert_eq((sharp.get_theme_stylebox("panel") as StyleBoxFlat).shadow_offset,
			expected[seat_id]["sharp"])
		assert_eq((soft.get_theme_stylebox("panel") as StyleBoxFlat).shadow_offset,
			expected[seat_id]["soft"])


func test_meld_tiles_get_reference_depth_layers() -> void:
	var area := MeldArea.new()
	add_child_autofree(area)
	area.set_seat_id(0)
	var extractor := get_tree().root.get_node_or_null("TextureExtractor")
	assert_not_null(extractor, "使用仓库真实 TextureExtractor 路径")
	area._spawn_tile({
		"face_down": false,
		"tile_id": TileId.W1,
		"is_red_dora": false,
		"rotated": false,
	}, 0, 0, extractor)
	var green := _named_child(area, "GreenSide") as ColorRect
	var white := _named_child(area, "WhiteSide") as ColorRect
	assert_not_null(green)
	assert_not_null(white)
	assert_eq(green.size, Vector2(40, 6))
	assert_eq(white.size, Vector2(40, 7))


func test_four_player_table_propagates_seat_to_depth_renderers() -> void:
	var table: FourPlayerTable = load(
		"res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(table)
	await get_tree().process_frame
	assert_eq(table.discard_rivers.size(), 4)
	assert_eq(table.meld_areas.size(), 4)
	for seat_id in range(4):
		assert_eq((table.discard_rivers[seat_id] as DiscardRiver)._seat_id, seat_id)
		assert_eq((table.meld_areas[seat_id] as MeldArea)._seat_id, seat_id)
