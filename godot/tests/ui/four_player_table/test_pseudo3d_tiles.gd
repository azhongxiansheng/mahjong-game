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
		seat.hand.add(Tile.new(i % 34))
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
	var green := first.get_node_or_null("EdgeBack") as ColorRect
	var white := first.get_node_or_null("EdgeFace") as ColorRect
	assert_not_null(green)
	assert_not_null(white)
	assert_eq(green.position, Vector2(0, -10), "before 绿背顶边 top=-10")
	assert_eq(green.size, Vector2(66, 10), "before 绿背顶边 height=10")
	assert_eq(white.position, Vector2(0, -5), "after 灰白棱 top=-5")
	assert_eq(white.size, Vector2(66, 5), "可见灰白棱 5px")
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


func test_player_drawn_hand_and_pon_reflow_match_reference() -> void:
	var panel: SeatPanel = SEAT_PANEL_SCENE.instantiate()
	panel.position = TableLayout.seat_anchor(0)
	panel.set_seat_id(0)
	add_child_autofree(panel)
	await get_tree().process_frame
	var seat := _seat_with_tiles(0, 14)
	seat.last_drawn_tile_id = seat.hand._tiles[-1].id
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
		seat.last_drawn_tile_id = seat.hand._tiles[-1].id
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
		for layer_name in ["ContactLeft", "CubeTop", "CubeBack", "CubeSide",
				"CubeSideShadow", "CubeOutline", "BevelA"]:
			assert_not_null(cube.get_node_or_null(layer_name),
				"aw() 绘制层缺失: %s" % layer_name)
		assert_true((cube.get_node("CubeTop") as Polygon2D).texture is GradientTexture2D,
			"顶面 49.9/50.1 split 必须用参考渐变")
		assert_true((cube.get_node("CubeSideShadow") as Polygon2D).texture is GradientTexture2D,
			"侧面暗化必须沿 O→C 渐变，不能退化成纯色蒙版")
	assert_null(top.get_node_or_null("StackSeam"), "isTop 不画与上一张之间的暗面")
	assert_null(top.get_node_or_null("SeamShadow"), "isTop 不画牌缝影")
	assert_not_null(middle.get_node_or_null("StackSeam"))
	assert_not_null(middle.get_node_or_null("SeamShadow"))
	assert_null(middle.get_node_or_null("ContactBottom"), "非 isBottom 不画底接触影")
	assert_not_null(bottom.get_node_or_null("ContactBottom"), "isBottom 画 6px 底接触影")
	assert_not_null(bottom.get_node_or_null("EdgeAB"))
	assert_not_null(bottom.get_node_or_null("EdgeBC"))
	assert_not_null(bottom.get_node_or_null("EdgeCA"))
	assert_not_null(bottom.get_node_or_null("BevelB"))
	assert_not_null(bottom.get_node_or_null("BevelC"))
	assert_gt((bottom.get_node("CubeBack") as Polygon2D).polygon.size(), 4,
		"isBottom 的 C 角必须按 6px quadratic round 采样，不能仍是尖角四边形")


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
		seat.last_drawn_tile_id = seat.hand._tiles[-1].id
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
