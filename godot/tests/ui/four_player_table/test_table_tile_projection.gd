extends GutTest


func _polygon_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in range(points.size()):
		var next := (i + 1) % points.size()
		area += points[i].x * points[next].y - points[next].x * points[i].y
	return absf(area) * 0.5


func test_four_seats_project_each_tile_corner_on_the_table_plane() -> void:
	for seat_id in range(4):
		var host := TableLayout.river_raw_rect(seat_id)
		var quad := TableLayout.project_seat_local_rect(
			seat_id, host, Rect2(Vector2(40, 49), Vector2(34, 45)))
		assert_eq(quad.size(), 4)
		assert_gt(_polygon_area(quad), 0.0)
		assert_false(is_equal_approx(quad[0].x, quad[3].x),
			"seat %d 的牌侧边应随桌面透视倾斜" % seat_id)


func test_far_table_tile_is_smaller_than_near_table_tile() -> void:
	var near_quad := TableLayout.project_seat_local_rect(
		0, TableLayout.river_raw_rect(0), Rect2(Vector2(40, 98), Vector2(34, 45)))
	var far_quad := TableLayout.project_seat_local_rect(
		2, TableLayout.river_raw_rect(2), Rect2(Vector2(226, 0), Vector2(34, 45)))
	assert_lt(_polygon_area(far_quad), _polygon_area(near_quad),
		"桌面远端的公开牌应比近端更小")


func test_river_tile_quads_share_the_board_projection() -> void:
	var host := TableLayout.river_raw_rect(0)
	var left := TableLayout.project_seat_local_rect(
		0, host, Rect2(Vector2(40, 49), Vector2(34, 45)))
	var right := TableLayout.project_seat_local_rect(
		0, host, Rect2(Vector2(77, 49), Vector2(34, 45)))
	assert_almost_eq(left[1].y, right[0].y, 0.001,
		"同排相邻牌必须共用同一条桌面边线")
	assert_almost_eq(left[2].y, right[3].y, 0.001,
		"同排相邻牌必须共用同一条桌面边线")


func test_table_projection_can_round_trip_layout_anchors() -> void:
	for raw_point in [Vector2(300, 180), Vector2(800, 450), Vector2(1320, 720)]:
		var restored := TableLayout.unproject_table_point(
			TableLayout.project_table_point(raw_point))
		assert_almost_eq(restored.x, raw_point.x, 0.001)
		assert_almost_eq(restored.y, raw_point.y, 0.001)
