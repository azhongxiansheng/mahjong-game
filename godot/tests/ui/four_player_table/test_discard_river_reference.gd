extends GutTest

# 公开 bundle `tV` + `.river` 的等价契约：固定容器/四行、按可见索引排位、
# 整牌根节点 spring 入场、一次性 latest glow，以及四向伪 3D 侧面渐变。

var _river: DiscardRiverView


func before_each() -> void:
	_river = DiscardRiverView.new()
	add_child_autofree(_river)


func _tiles(count: int) -> Array:
	var out: Array = []
	for i in range(count):
		out.append(Tile.new(i % 34))
	return out


func _constants() -> Dictionary:
	return (_river.get_script() as Script).get_script_constant_map()


func _tile_roots() -> Array:
	var roots: Array = _river.find_children("TileRoot_*", "", true, false)
	roots.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get_meta("original_index", -1)) < int(b.get_meta("original_index", -1)))
	return roots


func _root_at_original(index: int) -> Node:
	for root in _tile_roots():
		if int(root.get_meta("original_index", -1)) == index:
			return root
	return null


func _polygon_center(polygon: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in polygon:
		center += point
	return center / float(polygon.size())


func _gradient_texture(root: Node, side_name: String) -> GradientTexture2D:
	var side := root.find_child(side_name, true, false) as ColorRect
	assert_not_null(side, "%s 存在" % side_name)
	if side == null:
		return null
	var layer := side.get_node_or_null("SideGradient") as TextureRect
	assert_not_null(layer, "%s 使用真实 GradientTexture2D" % side_name)
	if layer == null:
		return null
	return layer.texture as GradientTexture2D


func _assert_gradient(texture: GradientTexture2D, expected_from: Vector2,
		expected_to: Vector2, offsets: PackedFloat32Array,
		colors: PackedColorArray, label: String) -> void:
	assert_not_null(texture, label)
	if texture == null:
		return
	assert_eq(texture.fill_from, expected_from, "%s direction from" % label)
	assert_eq(texture.fill_to, expected_to, "%s direction to" % label)
	assert_eq(texture.gradient.offsets, offsets, "%s stops" % label)
	assert_eq(texture.gradient.colors, colors, "%s colors" % label)
	assert_eq(texture.gradient.interpolation_mode,
		Gradient.GRADIENT_INTERPOLATE_LINEAR, "%s linear" % label)
	assert_eq(texture.gradient.interpolation_color_space,
		Gradient.GRADIENT_COLOR_SPACE_SRGB, "%s CSS sRGB" % label)


func test_compact_river_keeps_300_by_144_container_with_four_45px_rows() -> void:
	var constants := _constants()
	assert_eq(constants.get("RIVER_W"), 300)
	assert_eq(constants.get("RIVER_H"), 144)
	assert_eq(constants.get("ROW_COUNT"), 4)
	assert_eq(constants.get("ROW_H"), 45)
	var container := _river.get_node_or_null("RiverContainer") as Control
	assert_not_null(container)
	if container != null:
		assert_eq(container.size, Vector2(300, 144))
	assert_eq(_river.find_children("RiverRow_*", "Control", true, false).size(), 4,
		"即使为空也固定渲染四行")


func test_top_and_bottom_use_reference_row_gap_to_expose_tile_depth() -> void:
	_river.set_seat_id(0)
	_river.set_tiles(_tiles(25))
	var roots := _tile_roots()
	assert_eq(roots.size(), 25)
	if roots.size() != 25:
		return
	assert_eq(roots[0].get_meta("river_position"), Vector2(40.5, 0))
	assert_eq(roots[5].get_meta("river_position"), Vector2(225.5, 0),
		"普通牌横向步进 34+3")
	assert_eq(roots[6].get_meta("river_position"), Vector2(40.5, 52),
		"上下家行步进 45+7，密集牌河内部仍需露出实体侧面")
	assert_eq(roots[18].get_meta("river_position"), Vector2(40.5, 156))
	assert_eq(roots[24].get_meta("river_position"), Vector2(262.5, 156),
		"第 4 行吸收第 25 张，不再新开第 5 行")
	assert_eq(int(roots[24].get_meta("row")), 3)
	assert_eq(int(roots[24].get_meta("column")), 6)


func test_left_right_use_the_same_grid_before_table_rotation() -> void:
	_river.set_seat_id(1)
	_river.set_tiles(_tiles(19))
	var roots := _tile_roots()
	assert_eq(roots.size(), 19)
	if roots.size() != 19:
		return
	assert_eq(roots[0].get_meta("river_position"), Vector2(40.5, 0))
	assert_eq(roots[5].get_meta("river_position"), Vector2(225.5, 0))
	assert_eq(roots[6].get_meta("river_position"), Vector2(40.5, 49))
	assert_eq(roots[18].get_meta("river_position"), Vector2(40.5, 147))


func test_horizontal_riichi_tile_is_centered_in_45px_row() -> void:
	_river.set_tiles(_tiles(2), 1)
	var root := _root_at_original(1)
	assert_not_null(root)
	if root == null:
		return
	assert_eq(root.get_meta("slot_size"), Vector2(45, 34))
	assert_eq((root.get_meta("river_position") as Vector2).y, 5.5,
		"(45-34)/2=5.5，横置牌垂直居中")
	assert_true(bool(root.get_meta("is_riichi", false)))


func test_won_indices_skip_originals_then_compact_by_visible_count() -> void:
	_river.call("set_tiles", _tiles(22), 8, [0, 2, 7])
	var roots := _tile_roots()
	assert_eq(roots.size(), 19)
	assert_null(_root_at_original(0))
	assert_null(_root_at_original(2))
	assert_null(_root_at_original(7))
	var riichi := _root_at_original(8)
	assert_not_null(riichi)
	if riichi != null:
		assert_eq(int(riichi.get_meta("visible_index")), 5,
			"跳过 won 原索引后按可见计数压紧")
		assert_eq(riichi.get_meta("river_position"), Vector2(225.5, 5.5))
		assert_true(bool(riichi.get_meta("is_riichi", false)),
			"立直判断仍使用原索引")
	var latest := _root_at_original(21)
	assert_not_null(latest)
	if latest != null:
		assert_true(bool(latest.get_meta("is_latest", false)),
			"latest 判断仍使用原索引")
		assert_eq(int(latest.get_meta("row")), 3)
		assert_eq(int(latest.get_meta("column")), 0)


func test_skipping_original_last_index_does_not_promote_previous_visible_tile() -> void:
	_river.call("set_tiles", _tiles(8), -1, [7])
	assert_null(_root_at_original(7))
	var previous := _root_at_original(6)
	assert_not_null(previous)
	if previous != null:
		assert_false(bool(previous.get_meta("is_latest", false)))
		assert_null(previous.get_node_or_null("LatestGlow"))


func test_whole_tile_root_enters_from_plus_16_and_zero_opacity_with_reference_spring() -> void:
	_river.set_tiles(_tiles(1))
	var root := _root_at_original(0) as Node2D
	assert_not_null(root)
	if root == null:
		return
	assert_eq(root.position, Vector2(0, 16),
		"投影后的整张牌仍从屏幕下方 16px 入场")
	assert_eq(root.modulate.a, 0.0, "bundle initial opacity:0")
	assert_true(root.find_child("TileFace", true, false) is Polygon2D)
	assert_true(root.find_child("GreenSide", true, false) is Polygon2D)
	assert_true(root.find_child("WhiteSide", true, false) is Polygon2D)
	var constants := _constants()
	assert_eq(constants.get("SPRING_STIFFNESS"), 360.0)
	assert_eq(constants.get("SPRING_DAMPING"), 22.0)
	assert_eq(constants.get("SPRING_MASS"), 0.7)


func test_latest_glow_is_one_second_transient_not_permanent_border() -> void:
	_river.set_tiles(_tiles(1))
	var root := _root_at_original(0)
	assert_not_null(root)
	if root == null:
		return
	var glow := root.get_node_or_null("LatestGlow") as Polygon2D
	assert_not_null(glow)
	if glow != null:
		assert_eq(float(glow.get_meta("duration_seconds", -1.0)), 1.0)
	await get_tree().create_timer(1.1).timeout
	assert_null(root.get_node_or_null("LatestGlow"),
		"discard-glow 结束后节点消失，不留下永久描边")


func test_four_seats_render_reference_directional_depth_and_shadow() -> void:
	var depth_offsets := [
		Vector2(0, 7), Vector2(-7, 0), Vector2(0, -7), Vector2(7, 0),
	]
	var white_offsets := [
		Vector2(0, 4), Vector2(-4, 0), Vector2(0, -4), Vector2(4, 0),
	]
	var shadow_offsets := [
		Vector2(0, 11), Vector2(-11, 0), Vector2(0, -11), Vector2(11, 0),
	]
	for seat_id in range(4):
		var river := DiscardRiverView.new()
		add_child_autofree(river)
		river.set_seat_id(seat_id)
		river.set_tiles(_tiles(1))
		var roots: Array = river.find_children("TileRoot_*", "", true, false)
		assert_eq(roots.size(), 1, "seat %d root" % seat_id)
		if roots.size() != 1:
			continue
		var root: Node = roots[0]
		var face := root.get_node_or_null("TileFace") as Polygon2D
		var green := root.get_node_or_null("GreenSide") as Polygon2D
		var white := root.get_node_or_null("WhiteSide") as Polygon2D
		var shadow := root.get_node_or_null("TileShadow") as Polygon2D
		assert_not_null(face, "seat %d face" % seat_id)
		assert_not_null(green, "seat %d green depth" % seat_id)
		assert_not_null(white, "seat %d ivory depth" % seat_id)
		assert_not_null(shadow, "seat %d shadow" % seat_id)
		if face != null and green != null and white != null and shadow != null:
			assert_eq(face.polygon, root.get_meta("projected_quad"),
				"牌面必须使用四角桌面投影，不得退回 AABB")
			assert_eq(face.uv.size(), 4)
			var face_center := _polygon_center(face.polygon)
			assert_true((_polygon_center(green.polygon) - face_center).is_equal_approx(
				depth_offsets[seat_id]), "seat %d 绿色厚边方向" % seat_id)
			assert_true((_polygon_center(white.polygon) - face_center).is_equal_approx(
				white_offsets[seat_id]), "seat %d 象牙厚边方向" % seat_id)
			assert_true((_polygon_center(shadow.polygon) - face_center).is_equal_approx(
				shadow_offsets[seat_id]), "seat %d 接触阴影方向" % seat_id)
			assert_eq(green.color, Color("2c6b47"))
			assert_eq(white.color, Color("d8d8ce"))
