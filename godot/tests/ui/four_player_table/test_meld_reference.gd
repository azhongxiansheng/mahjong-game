extends GutTest

# 公开 bundle nV/rV 与 .meld/.melds CSS 的等价契约。
# Meld.called_tile 已保存真实河牌，这里直接验证 bundle 可证明路径。


func _slot(rotated: bool, stacked: bool = false) -> Dictionary:
	return {
		"tile_id": TileId.W1,
		"rotated": rotated,
		"face_down": false,
		"stacked_above": stacked,
		"is_red_dora": false,
	}


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


func _legal_post_draw_state_with_melds(seat_id: int,
		meld_count: int) -> BattleState:
	var state := BattleState.for_east_round(20260720 + seat_id, 0, 1, 0, 0)
	var seat: Seat = state.seats[seat_id]
	var base_count := 13 - meld_count * 3
	var drawn_instance_id: int = seat.hand.tiles()[base_count].instance_id
	var hand_tiles: Array[Tile] = seat.hand.tiles()
	hand_tiles.resize(base_count)
	var drawn := Tile.new(
		TileId.T1 + meld_count, false, Tile.NO_OWNER, drawn_instance_id)
	hand_tiles.append(drawn)
	assert_true(seat.hand.restore_tiles(hand_tiles))
	seat.last_drawn_instance_id = drawn.instance_id
	for meld_index in range(meld_count):
		var tile_id := TileId.W1 + meld_index
		var base_iid: int = 4000 + seat_id * 100 + meld_index * 10
		var called := Tile.new(tile_id, false, Tile.NO_OWNER, base_iid)
		seat.melds.add_existing(Meld.make_pon([
			called,
			Tile.new(tile_id, false, Tile.NO_OWNER, base_iid + 1),
			Tile.new(tile_id, false, Tile.NO_OWNER, base_iid + 2),
		], (seat_id + 1) % 4, meld_index * 4 + seat_id, called))
	return state


func test_owner_specific_css_gaps() -> void:
	for owner_seat in [0, 2]:
		assert_eq(MeldArea._intra_meld_gap(owner_seat), 1.0,
			"owner %d 的 .meld gap=1px" % owner_seat)
		assert_eq(MeldArea._between_meld_gap(owner_seat), 6.0,
			"owner %d 的 .melds gap=6px" % owner_seat)
	for owner_seat in [1, 3]:
		assert_eq(MeldArea._intra_meld_gap(owner_seat), 2.0,
			"owner %d 的 .meld gap=2px" % owner_seat)
		assert_eq(MeldArea._between_meld_gap(owner_seat), 9.0,
			"owner %d 的 .melds gap=9px" % owner_seat)


func test_owner0_group_flow_is_row_reverse_and_right_aligned() -> void:
	var origins := MeldArea._meld_origins([120.0, 160.0], 0)
	assert_eq(origins, [-120.0, -286.0],
		"首组贴右，后续组依次向左，组间 6px")


func test_other_owner_group_flows_match_css_and_keep_right_edge_alignment() -> void:
	assert_eq(MeldArea._meld_origins([120.0, 160.0], 1), [-289.0, -160.0],
		"owner1 column-reverse：首组在下，后续向上，组间 9px")
	assert_eq(MeldArea._meld_origins([120.0, 160.0], 2), [-286.0, -160.0],
		"owner2 row-reverse：首组在右，后续向左，组间 6px")
	assert_eq(MeldArea._meld_origins([120.0, 160.0], 3), [-289.0, -160.0],
		"owner3 column：首组在上，后续向下，组间 9px")


func test_slot_flow_and_owner_cross_axis_alignment() -> void:
	var slots := [_slot(false), _slot(true), _slot(false)]
	var owner0 := MeldArea._slot_layout(slots, 0)
	assert_eq(owner0["positions"], [Vector2(0, 0), Vector2(41, 13), Vector2(95, 0)])
	assert_eq(owner0["width"], 135.0)
	var owner1 := MeldArea._slot_layout(slots, 1)
	assert_eq(owner1["positions"], [Vector2(0, 0), Vector2(42, 13), Vector2(97, 0)])
	assert_eq(owner1["width"], 137.0)
	var owner2 := MeldArea._slot_layout(slots, 2)
	assert_eq(owner2["positions"], [Vector2(0, 0), Vector2(41, 0), Vector2(95, 0)],
		"180 度根旋转后，本地顶边对齐等价于屏幕底边对齐")
	var owner3 := MeldArea._slot_layout(slots, 3)
	assert_eq(owner3["positions"], [Vector2(0, 0), Vector2(42, 13), Vector2(97, 0)])


func test_added_kan_stack_direction_and_one_pixel_margin_are_owner_specific() -> void:
	var slots := [_slot(true), _slot(false), _slot(false), _slot(true, true)]
	for owner_seat in [0, 1, 3]:
		var positions: Array = MeldArea._slot_layout(slots, owner_seat)["positions"]
		assert_eq(positions[3] - positions[0], Vector2(0, -41),
			"owner %d：额外牌沿 CSS 方向叠放并留 1px" % owner_seat)
	var owner2_positions: Array = MeldArea._slot_layout(slots, 2)["positions"]
	assert_eq(owner2_positions[3] - owner2_positions[0], Vector2(0, 41),
		"owner2 根节点旋转 180 度，须反向本地偏移才仍向屏幕上方叠")


func test_called_and_back_face_final_directions_match_owner_css() -> void:
	assert_eq([
		MeldArea._called_local_rotation(0), MeldArea._called_local_rotation(1),
		MeldArea._called_local_rotation(2), MeldArea._called_local_rotation(3),
	], [-90.0, 90.0, -90.0, -90.0],
		"叠加根旋转后等价 owner0 horiz-90 / owner1 normal0 / owner2 horiz90 / owner3 normal0")
	assert_eq([
		MeldArea._back_local_rotation(0), MeldArea._back_local_rotation(1),
		MeldArea._back_local_rotation(2), MeldArea._back_local_rotation(3),
	], [0.0, 0.0, 180.0, 180.0],
		"tile--back 不吃 owner2/3 的正面牌旋转覆盖")


func test_side_owner_uses_css_polygon_not_rectangular_depth_blocks() -> void:
	for owner_seat in [1, 3]:
		var area := MeldArea.new()
		add_child_autofree(area)
		area.set_seat_id(owner_seat)
		var extractor := get_tree().root.get_node_or_null("TextureExtractor")
		assert_not_null(extractor, "使用仓库真实 TextureExtractor")
		area._spawn_tile(_slot(false), 0.0, 0.0, extractor)
		assert_null(area.get_node_or_null("GreenSide"), "左右家禁止矩形 ColorRect 侧面")
		assert_null(area.get_node_or_null("WhiteSide"), "左右家禁止矩形 ColorRect 侧面")
		var outer := area.get_node_or_null("TileSideOuter") as Polygon2D
		var inner := area.get_node_or_null("TileSideInner") as Polygon2D
		assert_not_null(outer)
		assert_not_null(inner)
		assert_true(outer.polygon.size() >= 5, "CSS clip-path 必须翻成多边形")
		assert_true(outer.texture is GradientTexture2D, "135/225 度绿侧渐变")
		assert_true(inner.texture is GradientTexture2D, "135/225 度白棱渐变")
		assert_eq((outer.texture as GradientTexture2D).gradient.interpolation_color_space,
			Gradient.GRADIENT_COLOR_SPACE_SRGB, "CSS 渐变必须用 sRGB 插值")
		assert_eq((inner.texture as GradientTexture2D).gradient.interpolation_color_space,
			Gradient.GRADIENT_COLOR_SPACE_SRGB, "CSS 内棱渐变必须用 sRGB 插值")
		assert_eq(float(outer.get_meta("css_top")), 3.0)
		assert_eq(float(outer.get_meta("css_bottom")), -9.0)
		assert_eq(float(outer.get_meta("css_inline_overhang")), -4.5)


func test_top_and_bottom_depth_always_extrude_toward_screen_bottom() -> void:
	var bottom := MeldArea._depth_geometry(0, Vector2.ZERO, Vector2(40, 53))
	var top := MeldArea._depth_geometry(2, Vector2.ZERO, Vector2(40, 53))
	assert_eq(bottom["green_pos"], Vector2(0, 53))
	assert_eq(bottom["sharp"], Vector2(0, 7))
	assert_eq(top["green_pos"], Vector2(0, -6),
		"owner2 根旋转 180 度，本地向上才是屏幕向下")
	assert_eq(top["sharp"], Vector2(0, -7))


func test_owner1_uses_reference_nested_z_order() -> void:
	var area := MeldArea.new()
	add_child_autofree(area)
	area.set_seat_id(1)
	var called_a := Tile.new(TileId.W5, false, Tile.NO_OWNER, 4100)
	var called_b := Tile.new(TileId.T5, false, Tile.NO_OWNER, 4110)
	var meld_a := Meld.make_pon([
		called_a,
		Tile.new(TileId.W5, false, Tile.NO_OWNER, 4101),
		Tile.new(TileId.W5, false, Tile.NO_OWNER, 4102),
	], 0, 0, called_a)
	var meld_b := Meld.make_pon([
		called_b,
		Tile.new(TileId.T5, false, Tile.NO_OWNER, 4111),
		Tile.new(TileId.T5, false, Tile.NO_OWNER, 4112),
	], 0, 0, called_b)
	area.set_melds([meld_a, meld_b], 1)
	assert_eq(area._tile_nodes.size(), 6)
	if area._tile_nodes.size() != 6:
		return
	var z: Array[int] = []
	for entry in area._tile_nodes:
		z.append((entry.get("node") as TextureRect).z_index)
	assert_true(z[0] > z[1] and z[1] > z[2],
		"owner1 每组首牌到末牌必须按 4/3/2/1 递减")
	assert_true(z[2] > z[3],
		"owner1 第一组整体 z-index 必须高于第二组")
	assert_true(z[3] > z[4] and z[4] > z[5],
		"owner1 第二组内部也必须递减")


func test_single_pon_layout_bounds_follow_hand_flex_reflow() -> void:
	var expected := [
		Rect2(1246.5, 797.5, 135.0, 53.0),
		Rect2(1289.893, 151.433, 59.806, 106.771),
		Rect2(494.917, 27.162, 110.950, 37.759),
		Rect2(180.129, 590.599, 69.488, 135.268),
	]
	for seat_id in range(4):
		var area := MeldArea.new()
		area.set_seat_id(seat_id)
		area.rotation_degrees = SeatPanel.SEAT_ROTATION_DEGREES[seat_id]
		add_child_autofree(area)
		var called := Tile.new(TileId.W5, false, Tile.NO_OWNER, 4200 + seat_id * 3)
		var meld := Meld.make_pon([
			called,
			Tile.new(TileId.W5, false, Tile.NO_OWNER, 4201 + seat_id * 3),
			Tile.new(TileId.W5, false, Tile.NO_OWNER, 4202 + seat_id * 3),
		], (seat_id + 1) % 4, 0, called)
		area.set_melds([meld], seat_id)
		area.apply_reference_layout()
		await get_tree().process_frame
		var actual: Rect2 = area.get_screen_layout_bounds()
		_assert_rect_almost_eq(actual, expected[seat_id], 0.02,
			"seat %d single pon bbox" % seat_id)


func test_real_bind_uses_legal_concealed_count_for_one_and_two_pon() -> void:
	assert_eq(TableLayout.HAND_MELD_GAP, 32.0, "公开 bundle hand/meld gap")
	for meld_count in [1, 2]:
		var expected_base: int = 13 - int(meld_count) * 3
		var expected_visual: int = expected_base + 1
		for seat_id in range(4):
			var table: FourPlayerTable = load(
				"res://ui/four_player_table/four_player_table.tscn").instantiate()
			add_child_autofree(table)
			await get_tree().process_frame
			table.bind_battle_state(
				_legal_post_draw_state_with_melds(seat_id, meld_count), 0, 4)
			await get_tree().process_frame
			var panel := table.seat_panels[seat_id] as SeatPanel
			var area := table.meld_areas[seat_id] as MeldArea
			var metrics: Dictionary = panel.get_reference_hand_metrics()
			assert_eq(int(metrics["base_count"]), expected_base,
				"seat %d/%d pon 暗手基数" % [seat_id, meld_count])
			assert_true(bool(metrics["has_drawn"]))
			assert_eq(panel.get_visual_hand_rects().size(), expected_visual,
				"seat %d/%d pon 视觉槽数" % [seat_id, meld_count])
			var expected_hand_extent: float = TableLayout.hand_main_extent(
				seat_id, expected_base)
			assert_almost_eq(float(metrics["main_extent"]),
				expected_hand_extent, 0.001)
			var meld_extent := area.get_layout_bounds().size.x
			var meld_outer_extent := meld_extent \
				+ (TableLayout.SIDE_MELD_MAIN_OVERHANG
					if seat_id == 1 or seat_id == 3 else 0.0)
			var flex: Dictionary = TableLayout.hand_meld_flex_layout(
				seat_id, expected_hand_extent, meld_outer_extent)
			assert_almost_eq(float(flex["combined_center"]),
				800.0 if seat_id == 0 or seat_id == 2 \
					else TableLayout.SIDE_FLEX_CENTER_RAW_Y, 0.001)
			assert_almost_eq(float(flex["gap"]), 32.0, 0.001)
			_assert_rect_almost_eq(panel.get_reference_hand_host_rect(),
				TableLayout.hand_host_rect_for_state(
					seat_id, expected_base, meld_extent), 0.02,
				"seat %d/%d pon dynamic hand host" % [seat_id, meld_count])
			if meld_count == 1:
				_assert_rect_almost_eq(panel.get_reference_hand_host_rect(),
					TableLayout.LEGAL_ONE_PON_POST_DRAW_HAND_RECTS[seat_id], 0.03,
					"seat %d legal one-pon post-draw hand" % seat_id)
				_assert_rect_almost_eq(area.get_screen_layout_bounds(),
					TableLayout.LEGAL_ONE_PON_POST_DRAW_MELD_RECTS[seat_id], 0.03,
					"seat %d legal one-pon post-draw meld" % seat_id)
			# 每个碰减少3张暗手：bottom/top 不得残留198/123px，side不得残留96px。
			assert_lt(expected_hand_extent,
				TableLayout.hand_main_extent(seat_id, 13))


func test_live_left_one_pon_post_discard_matches_browser_bbox() -> void:
	var state := _legal_post_draw_state_with_melds(3, 1)
	var hand_tiles: Array[Tile] = state.seats[3].hand.tiles()
	hand_tiles.pop_back()
	assert_true(state.seats[3].hand.restore_tiles(hand_tiles))
	state.seats[3].last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
	var table: FourPlayerTable = load(
		"res://ui/four_player_table/four_player_table.tscn").instantiate()
	add_child_autofree(table)
	await get_tree().process_frame
	table.bind_battle_state(state, 0, 4)
	await get_tree().process_frame
	var panel := table.seat_panels[3] as SeatPanel
	var rects := panel.get_visual_hand_rects()
	assert_eq(rects.size(), 10)
	_assert_rect_almost_eq(panel.get_reference_hand_host_rect(),
		TableLayout.LEGAL_LEFT_ONE_PON_POST_DISCARD_HAND_RECT, 0.03,
		"live left hand host")
	_assert_rect_almost_eq(rects[0],
		Rect2(299.509705, 177.346008, 46.009247, 51.889145), 0.03,
		"live left first slot")
	_assert_rect_almost_eq(rects[9],
		Rect2(266.081543, 412.987640, 49.544128, 58.995819), 0.03,
		"live left last slot")
	_assert_rect_almost_eq(
		(table.meld_areas[3] as MeldArea).get_screen_layout_bounds(),
		TableLayout.LEGAL_LEFT_ONE_PON_POST_DISCARD_MELD_RECT, 0.03,
		"live left meld")
