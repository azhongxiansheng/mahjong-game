extends GutTest

# 公开 bundle `tV` + `.river` 的等价契约：固定容器/四行、按可见索引排位、
# 整牌根节点 spring 入场、一次性 latest glow，以及四向伪 3D 侧面渐变。

var _river: DiscardRiver


func before_each() -> void:
	_river = DiscardRiver.new()
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


func test_reference_container_is_fixed_300_by_144_with_four_53px_rows() -> void:
	var constants := _constants()
	assert_eq(constants.get("RIVER_W"), 300)
	assert_eq(constants.get("RIVER_H"), 144)
	assert_eq(constants.get("ROW_COUNT"), 4)
	assert_eq(constants.get("ROW_H"), 53)
	var container := _river.get_node_or_null("RiverContainer") as Control
	assert_not_null(container)
	if container != null:
		assert_eq(container.size, Vector2(300, 144))
	assert_eq(_river.find_children("RiverRow_*", "Control", true, false).size(), 4,
		"即使为空也固定渲染四行")


func test_top_bottom_use_7px_row_gap_2px_tile_gap_and_25px_left_padding() -> void:
	_river.set_seat_id(0)
	_river.set_tiles(_tiles(25))
	var roots := _tile_roots()
	assert_eq(roots.size(), 25)
	if roots.size() != 25:
		return
	assert_eq(roots[0].get_meta("river_position"), Vector2(25, 0.5))
	assert_eq(roots[5].get_meta("river_position"), Vector2(230, 0.5),
		"普通牌横向步进 39+2")
	assert_eq(roots[6].get_meta("river_position"), Vector2(25, 60.5),
		"行步进 53+7")
	assert_eq(roots[18].get_meta("river_position"), Vector2(25, 180.5))
	assert_eq(roots[24].get_meta("river_position"), Vector2(271, 180.5),
		"第 4 行吸收第 25 张，不再新开第 5 行")
	assert_eq(int(roots[24].get_meta("row")), 3)
	assert_eq(int(roots[24].get_meta("column")), 6)


func test_left_right_use_2px_row_gap_7px_tile_gap_and_6px_left_padding() -> void:
	_river.set_seat_id(1)
	_river.set_tiles(_tiles(19))
	var roots := _tile_roots()
	assert_eq(roots.size(), 19)
	if roots.size() != 19:
		return
	assert_eq(roots[0].get_meta("river_position"), Vector2(6, 0.5))
	assert_eq(roots[5].get_meta("river_position"), Vector2(236, 0.5),
		"普通牌横向步进 39+7")
	assert_eq(roots[6].get_meta("river_position"), Vector2(6, 55.5),
		"行步进 53+2")
	assert_eq(roots[18].get_meta("river_position"), Vector2(6, 165.5))


func test_horizontal_riichi_tile_is_centered_in_53px_row() -> void:
	_river.set_tiles(_tiles(2), 1)
	var root := _root_at_original(1)
	assert_not_null(root)
	if root == null:
		return
	assert_eq(root.get_meta("slot_size"), Vector2(52, 39))
	assert_eq((root.get_meta("river_position") as Vector2).y, 7.0,
		"(53-39)/2=7，横置牌垂直居中")
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
		assert_eq(riichi.get_meta("river_position"), Vector2(230, 7))
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
	var rest_position := root.get_meta("row_position") as Vector2
	assert_eq(root.position, rest_position + Vector2(0, 16),
		"bundle initial y:+16 施加到 whole TileRoot")
	assert_eq(root.modulate.a, 0.0, "bundle initial opacity:0")
	assert_true(root.find_child("TileFace", true, false) is TextureRect)
	assert_true(root.find_child("GreenSide", true, false) is ColorRect)
	assert_true(root.find_child("WhiteSide", true, false) is ColorRect)
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
	var glow := root.get_node_or_null("LatestGlow") as Panel
	assert_not_null(glow)
	if glow != null:
		assert_eq(float(glow.get_meta("duration_seconds", -1.0)), 1.0)
	await get_tree().create_timer(1.1).timeout
	assert_null(root.get_node_or_null("LatestGlow"),
		"discard-glow 结束后节点消失，不留下永久描边")


func test_four_seats_use_exact_reference_side_gradients() -> void:
	var bottom_white := PackedColorArray([
		Color("e9e9e0"), Color("e9e9e0"), Color("bcbdb6"), Color("a2a39d")])
	var bottom_green := PackedColorArray([
		Color("57a271"), Color("4c9564"), Color("3e8254")])
	var top_white := PackedColorArray([
		Color("a2a39d"), Color("bcbdb6"), Color("e9e9e0"), Color("e9e9e0")])
	var top_green := PackedColorArray([
		Color("3e8254"), Color("4c9564"), Color("57a271")])
	for seat_id in range(4):
		var river := DiscardRiver.new()
		add_child_autofree(river)
		river.set_seat_id(seat_id)
		river.set_tiles(_tiles(1))
		var roots: Array = river.find_children("TileRoot_*", "", true, false)
		assert_eq(roots.size(), 1, "seat %d root" % seat_id)
		if roots.size() != 1:
			continue
		var root: Node = roots[0]
		var axis_from := Vector2(0, 0)
		var axis_to := Vector2(0, 1)
		var white_offsets := PackedFloat32Array([0.0, 0.43, 0.55, 1.0])
		var green_offsets := PackedFloat32Array([0.0, 0.60, 1.0])
		var white_colors := bottom_white
		var green_colors := bottom_green
		if seat_id == 1:
			axis_from = Vector2(1, 0)
			axis_to = Vector2(0, 0)
		elif seat_id == 2:
			white_offsets = PackedFloat32Array([0.0, 0.45, 0.57, 1.0])
			green_offsets = PackedFloat32Array([0.0, 0.40, 1.0])
			white_colors = top_white
			green_colors = top_green
		elif seat_id == 3:
			axis_to = Vector2(1, 0)
		_assert_gradient(_gradient_texture(root, "WhiteSide"), axis_from, axis_to,
			white_offsets, white_colors, "seat %d white" % seat_id)
		_assert_gradient(_gradient_texture(root, "GreenSide"), axis_from, axis_to,
			green_offsets, green_colors, "seat %d green" % seat_id)
