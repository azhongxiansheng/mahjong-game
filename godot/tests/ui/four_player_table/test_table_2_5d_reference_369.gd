extends GutTest

const SCENE_PATH := "res://examples/table_2_5d_reference/table_2_5d_reference.tscn"
const POSE_LAB_SCENE_PATH := \
	"res://examples/table_2_5d_reference/tile_pose_lab_369.tscn"


func _make_reference():
	var packed := load(SCENE_PATH) as PackedScene
	assert_not_null(packed, "#369 Phase 1 必须提供可独立运行的截图场景")
	if packed == null:
		return null
	var reference = packed.instantiate()
	add_child_autofree(reference)
	await get_tree().process_frame
	await get_tree().process_frame
	return reference


func _make_pose_lab():
	assert_true(ResourceLoader.exists(POSE_LAB_SCENE_PATH),
		"#369 单牌姿态实验场景必须进入 Phase 1 白名单")
	if not ResourceLoader.exists(POSE_LAB_SCENE_PATH):
		return null
	var packed := load(POSE_LAB_SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var lab = packed.instantiate()
	add_child_autofree(lab)
	await get_tree().process_frame
	await get_tree().process_frame
	return lab


func _surface_texture_seam_samples(visible_mesh: MeshInstance3D,
		surface_index: int) -> Array[Color]:
	var samples: Array[Color] = []
	var material := visible_mesh.get_surface_override_material(surface_index) \
		as StandardMaterial3D
	assert_not_null(material)
	if material == null:
		return samples
	assert_not_null(material.albedo_texture)
	if material.albedo_texture == null:
		return samples
	var image := material.albedo_texture.get_image()
	assert_not_null(image)
	if image == null:
		return samples
	assert_false(image.is_empty(), "像素接缝合同必须读取真实非空纹理")
	if image.is_empty():
		return samples
	var arrays := visible_mesh.mesh.surface_get_arrays(surface_index)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var uvs := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	assert_eq(vertices.size(), uvs.size())
	if vertices.size() != uvs.size():
		return samples
	for index in range(vertices.size()):
		var vertex := vertices[index]
		if absf(vertex.x) <= 0.000001 and absf(vertex.z) <= 0.000001:
			continue
		var uv := uvs[index]
		var center := Vector2i(
			clampi(roundi(uv.x * float(image.get_width() - 1)),
				0, image.get_width() - 1),
			clampi(roundi(uv.y * float(image.get_height() - 1)),
				0, image.get_height() - 1))
		for offset_y in range(-1, 2):
			for offset_x in range(-1, 2):
				var sample := image.get_pixel(
					clampi(center.x + offset_x, 0, image.get_width() - 1),
					clampi(center.y + offset_y, 0, image.get_height() - 1))
				if sample.a >= 0.5:
					samples.append(sample)
	assert_false(samples.is_empty(), "最终 UV 接缝必须映射到可见纹理像素")
	return samples


func _color_bounds(samples: Array[Color]) -> Array[Vector3]:
	assert_false(samples.is_empty())
	if samples.is_empty():
		return [Vector3.ZERO, Vector3.ZERO]
	var minimum := Vector3(samples[0].r, samples[0].g, samples[0].b)
	var maximum := minimum
	for sample in samples.slice(1):
		var rgb := Vector3(sample.r, sample.g, sample.b)
		minimum = minimum.min(rgb)
		maximum = maximum.max(rgb)
	return [minimum, maximum]


func _color_average(samples: Array[Color]) -> Color:
	assert_false(samples.is_empty())
	if samples.is_empty():
		return Color.TRANSPARENT
	var total := Vector3.ZERO
	for sample in samples:
		total += Vector3(sample.r, sample.g, sample.b)
	var average := total / float(samples.size())
	return Color(average.x, average.y, average.z, 1.0)


func _tile_entries(river: Node) -> Array:
	var entries: Array = []
	for child in river.get_children():
		if child.has_meta("tile_index"):
			entries.append(child)
	entries.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get_meta("tile_index")) < int(b.get_meta("tile_index")))
	return entries


func _center(node: Node) -> Vector2:
	var face := node.get_node_or_null("TileFace") as Polygon2D
	assert_not_null(face, "牌河必须由最终可见 Polygon2D 牌面证明")
	if face == null or face.polygon.is_empty():
		return Vector2.ZERO
	var total := Vector2.ZERO
	for point in face.polygon:
		total += point
	return total / face.polygon.size()


func _visible_bounds(root: Node) -> Rect2:
	var points: Array[Vector2] = []
	for child in root.find_children("*", "Polygon2D", true, false):
		var polygon := child as Polygon2D
		for point in polygon.polygon:
			points.append(polygon.global_transform * point)
	assert_false(points.is_empty())
	if points.is_empty():
		return Rect2()
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points.slice(1):
		bounds = bounds.expand(point)
	return bounds


func _polygon_bounds(polygon: Polygon2D) -> Rect2:
	assert_false(polygon.polygon.is_empty())
	if polygon.polygon.is_empty():
		return Rect2()
	var bounds := Rect2(polygon.polygon[0], Vector2.ZERO)
	for point in polygon.polygon.slice(1):
		bounds = bounds.expand(point)
	return bounds


func _merge_rects(rects: Array) -> Rect2:
	assert_false(rects.is_empty())
	if rects.is_empty():
		return Rect2()
	var bounds: Rect2 = rects[0]
	for rect in rects.slice(1):
		bounds = bounds.merge(rect as Rect2)
	return bounds


func _meld_face_rects(area: MeldArea) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for child in area.get_children():
		if child is Polygon2D and not child.has_meta("depth_layer"):
			rects.append(_polygon_bounds(child as Polygon2D))
	return rects


func _river_face_polygons(river: Node) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	for entry in _tile_entries(river):
		var face := entry.get_node("TileFace") as Polygon2D
		var points := PackedVector2Array()
		for point in face.polygon:
			points.append(face.global_transform * point)
		polygons.append(points)
	return polygons


func _polygon_area(points: PackedVector2Array) -> float:
	if points.size() < 3:
		return 0.0
	var doubled_area := 0.0
	for index in range(points.size()):
		var next := (index + 1) % points.size()
		doubled_area += points[index].x * points[next].y \
			- points[next].x * points[index].y
	return absf(doubled_area) * 0.5


func _point_segment_distance(point: Vector2, start: Vector2,
		end: Vector2) -> float:
	var segment := end - start
	var length_squared := segment.length_squared()
	if is_zero_approx(length_squared):
		return point.distance_to(start)
	var ratio := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * ratio)


func _polygon_distance(first: PackedVector2Array,
		second: PackedVector2Array) -> float:
	var closest := INF
	for point in first:
		for index in range(second.size()):
			closest = minf(closest, _point_segment_distance(
				point, second[index], second[(index + 1) % second.size()]))
	for point in second:
		for index in range(first.size()):
			closest = minf(closest, _point_segment_distance(
				point, first[index], first[(index + 1) % first.size()]))
	return closest


func test_keeps_the_real_table_layout_and_replaces_all_four_rivers() -> void:
	var reference = await _make_reference()
	if reference == null:
		return
	assert_true(reference.source_table is FourPlayerTable)
	assert_eq(reference.source_table.position, Vector2.ZERO)
	assert_eq(reference.source_table.scale, Vector2.ONE)
	assert_eq(reference.prototype_rivers.keys(), [0, 1, 2, 3])
	for river in reference.source_table.discard_rivers:
		assert_false(river.visible)
	assert_eq(reference.wall_sides.keys(), [0, 1, 2, 3])


func test_top_and_bottom_use_three_physical_rows_with_six_tile_breaks() -> void:
	var reference = await _make_reference()
	if reference == null:
		return
	for seat_id in [0, 2]:
		var entries := _tile_entries(reference.prototype_rivers[seat_id])
		assert_eq(entries.size(), 18)
		var rows := [0, 0, 0]
		for entry in entries:
			var row := int(entry.get_meta("row"))
			assert_between(row, 0, 2, "不得生成第四行牌河")
			rows[row] += 1
		assert_eq(rows, [6, 6, 6], "拥挤态仍须保持标准三行、每行六张")


func test_side_rivers_use_the_same_three_row_contract() -> void:
	var reference = await _make_reference()
	if reference == null:
		return
	for seat_id in [1, 3]:
		var entries := _tile_entries(reference.prototype_rivers[seat_id])
		var rows := [0, 0, 0]
		for entry in entries:
			rows[int(entry.get_meta("row"))] += 1
		assert_eq(rows, [6, 6, 6])


func test_each_river_contains_one_sideways_riichi_tile() -> void:
	var reference = await _make_reference()
	if reference == null:
		return
	for seat_id in range(4):
		var entries := _tile_entries(reference.prototype_rivers[seat_id])
		var riichi := entries.filter(func(entry: Node) -> bool:
			return bool(entry.get_meta("is_riichi", false)))
		assert_eq(riichi.size(), 1)
		var face := riichi[0].get_node("TileFace") as Polygon2D
		var points := face.polygon
		assert_gt(points[1].distance_to(points[0]),
			points[3].distance_to(points[0]), "立直牌须以横向槽位占据牌河")


func test_each_river_keeps_one_physical_start_baseline_for_all_rows() -> void:
	var reference = await _make_reference()
	if reference == null:
		return
	for seat_id in range(4):
		var entries := _tile_entries(reference.prototype_rivers[seat_id])
		var first := _center(entries[0])
		var seventh := _center(entries[6])
		var thirteenth := _center(entries[12])
		if seat_id == 0 or seat_id == 2:
			assert_almost_eq(first.x, seventh.x, 8.0)
			assert_almost_eq(first.x, thirteenth.x, 8.0)
		else:
			assert_almost_eq(first.y, seventh.y, 8.0)
			assert_almost_eq(first.y, thirteenth.y, 8.0)


func test_top_is_the_physical_180_degree_mirror_of_bottom() -> void:
	var reference = await _make_reference()
	if reference == null:
		return
	var bottom := _tile_entries(reference.prototype_rivers[0])
	var top := _tile_entries(reference.prototype_rivers[2])
	var bottom_first := _center(bottom[0])
	var bottom_sixth := _center(bottom[5])
	var bottom_seventh := _center(bottom[6])
	var top_first := _center(top[0])
	var top_sixth := _center(top[5])
	var top_seventh := _center(top[6])
	assert_lt(bottom_first.x, bottom_sixth.x, "下家须按本人视角从左向右出牌")
	assert_gt(top_first.x, top_sixth.x, "上家须在屏幕上从右向左形成 180° 镜像")
	assert_lt(bottom_first.y, bottom_seventh.y, "下家新行须从中央向本人推进")
	assert_gt(top_first.y, top_seventh.y, "上家新行须从中央向上家推进")
	assert_almost_eq(bottom_first.x + top_first.x, 1600.0, 24.0)
	assert_almost_eq(bottom_sixth.x + top_sixth.x, 1600.0, 24.0)


func test_left_and_right_rivers_keep_mirrored_visible_progression() -> void:
	var reference = await _make_reference()
	if reference == null:
		return
	var right := _tile_entries(reference.prototype_rivers[1])
	var left := _tile_entries(reference.prototype_rivers[3])
	var right_first := _center(right[0])
	var right_sixth := _center(right[5])
	var right_seventh := _center(right[6])
	var left_first := _center(left[0])
	var left_sixth := _center(left[5])
	var left_seventh := _center(left[6])
	assert_gt(right_first.y, right_sixth.y,
		"右家须按本人视角推进，屏幕上由下向上")
	assert_lt(left_first.y, left_sixth.y,
		"左家须形成相反方向，屏幕上由上向下")
	assert_lt(right_first.x, right_seventh.x,
		"右家换行须从中央向本人一侧推进")
	assert_gt(left_first.x, left_seventh.x,
		"左家换行须从中央向本人一侧推进")
	assert_almost_eq(
		right_first.y - right_sixth.y,
		left_sixth.y - left_first.y,
		8.0, "左右首行的可见推进量须近似镜像")


func test_crowded_river_raster_bounds_keep_reference_scale_and_center() -> void:
	var reference = await _make_reference()
	if reference == null:
		return
	var bounds: Dictionary = {}
	for seat_id in range(4):
		bounds[seat_id] = _visible_bounds(reference.prototype_rivers[seat_id])
	var bottom := bounds[0] as Rect2
	var right := bounds[1] as Rect2
	var top := bounds[2] as Rect2
	var left := bounds[3] as Rect2
	assert_between(top.size.x, 280.0, 310.0)
	assert_between(top.size.y, 140.0, 170.0)
	assert_between(bottom.size.x, 300.0, 340.0)
	assert_between(bottom.size.y, 160.0, 190.0)
	for side in [left, right]:
		assert_between(side.size.x, 160.0, 200.0)
		assert_between(side.size.y, 285.0, 335.0)
	assert_almost_eq(top.get_center().x, 800.0, 10.0)
	assert_almost_eq(bottom.get_center().x, 800.0, 10.0)
	assert_almost_eq(left.size.x, right.size.x, 10.0)
	assert_almost_eq(left.size.y, right.size.y, 16.0)


func test_adjacent_river_faces_never_overlap_at_the_four_corners() -> void:
	var reference = await _make_reference()
	if reference == null:
		return
	for seats in [[2, 3], [2, 1], [0, 3], [0, 1]]:
		var first := _river_face_polygons(reference.prototype_rivers[seats[0]])
		var second := _river_face_polygons(reference.prototype_rivers[seats[1]])
		var overlap_area := 0.0
		var minimum_gap := INF
		for first_face in first:
			for second_face in second:
				minimum_gap = minf(minimum_gap,
					_polygon_distance(first_face, second_face))
				for overlap in Geometry2D.intersect_polygons(
						first_face, second_face):
					overlap_area += _polygon_area(overlap)
		assert_lte(overlap_area, 0.5,
			"seat %d 与 seat %d 的最终牌面不得在桌角互相压盖" % seats)
		assert_gte(minimum_gap, 6.0,
			"seat %d 与 seat %d 的最终牌面净距须至少为 6px" % seats)


func test_four_wall_sides_keep_two_tile_high_physical_stacks() -> void:
	var reference = await _make_reference()
	if reference == null:
		return
	for seat_id in range(4):
		var wall: Node = reference.wall_sides[seat_id]
		var pieces: Array = []
		for child in wall.get_children():
			if child.has_meta("wall_stack"):
				pieces.append(child)
		assert_eq(pieces.size(), 34, "每边须有 17 墩×上下两层")
		for stack_index in range(17):
			var levels := pieces.filter(func(piece: Node) -> bool:
				return int(piece.get_meta("wall_stack")) == stack_index)
			assert_eq(levels.size(), 2)
		assert_false(_visible_bounds(wall).intersects(
			_visible_bounds(reference.prototype_rivers[seat_id])),
			"seat %d 牌山与同席牌河不得在最终画面重叠" % seat_id)
	var bottom := _visible_bounds(reference.wall_sides[0])
	var right := _visible_bounds(reference.wall_sides[1])
	var top := _visible_bounds(reference.wall_sides[2])
	var left := _visible_bounds(reference.wall_sides[3])
	var bottom_river := _visible_bounds(reference.prototype_rivers[0])
	var top_river := _visible_bounds(reference.prototype_rivers[2])
	var bottom_hand := _merge_rects(
		reference.source_table.seat_panels[0].get_visual_hand_rects())
	var top_hand := _merge_rects(
		reference.source_table.seat_panels[2].get_visual_hand_rects())
	assert_between(top.size.x, 600.0, 690.0)
	assert_between(top.size.y, 48.0, 68.0)
	assert_between(bottom.size.x, 690.0, 790.0)
	assert_between(bottom.size.y, 55.0, 78.0)
	for side in [left, right]:
		assert_between(side.size.x, 72.0, 100.0)
		assert_between(side.size.y, 550.0, 710.0)
	assert_almost_eq(left.size.x, right.size.x, 10.0)
	assert_almost_eq(left.size.y, right.size.y, 18.0)
	assert_gte(top.position.y - top_hand.end.y, 8.0,
		"上家暗手与牌山须保留可辨识净距")
	assert_gte(top_river.position.y - top.end.y, 8.0,
		"上家牌山与牌河须保留可辨识净距")
	assert_gte(bottom.position.y - bottom_river.end.y, 8.0,
		"下家牌河与牌山须保留可辨识净距")
	assert_gte(bottom_hand.position.y - bottom.end.y, 8.0,
		"下家牌山与暗手须保留可辨识净距")


func test_real_melds_match_hand_scale_gap_and_thickness() -> void:
	var reference = await _make_reference()
	if reference == null:
		return
	for seat_id in range(4):
		var seat: SeatPanel = reference.source_table.seat_panels[seat_id]
		var area: MeldArea = reference.source_table.meld_areas[seat_id]
		var hand_rects: Array[Rect2] = seat.get_visual_hand_rects()
		var face_rects := _meld_face_rects(area)
		assert_false(hand_rects.is_empty())
		assert_false(face_rects.is_empty())
		var hand_bounds := _merge_rects(hand_rects)
		var meld_bounds := _merge_rects(face_rects)
		var gap: float
		match seat_id:
			0: gap = meld_bounds.position.x - hand_bounds.end.x
			1: gap = hand_bounds.position.y - meld_bounds.end.y
			2: gap = hand_bounds.position.x - meld_bounds.end.x
			_: gap = meld_bounds.position.y - hand_bounds.end.y
		assert_between(gap, 8.0, 16.0,
			"seat %d 副露必须贴近同席手牌末端" % seat_id)
		match seat_id:
			0, 2:
				assert_almost_eq(meld_bounds.get_center().y,
					hand_bounds.get_center().y, 14.0,
					"上下家副露须与同席手牌保持同一物理基线")
			1:
				assert_almost_eq(meld_bounds.end.x, hand_bounds.end.x, 14.0,
					"右家副露须与暗手外缘对齐")
			_:
				assert_almost_eq(meld_bounds.position.x,
					hand_bounds.position.x, 14.0,
					"左家副露须与暗手外缘形成镜像")
		var hand_tile := hand_rects[0]
		var hand_dims := [hand_tile.size.x, hand_tile.size.y]
		hand_dims.sort()
		var best_delta := INF
		var best_ratios := Vector2.ZERO
		for face_rect in face_rects:
			var face_dims := [face_rect.size.x, face_rect.size.y]
			face_dims.sort()
			var ratios := Vector2(
				float(face_dims[0]) / float(hand_dims[0]),
				float(face_dims[1]) / float(hand_dims[1]))
			var delta := absf(ratios.x - 1.0) + absf(ratios.y - 1.0)
			if delta < best_delta:
				best_delta = delta
				best_ratios = ratios
		assert_between(best_ratios.x, 0.80, 1.15)
		assert_between(best_ratios.y, 0.80, 1.15)
		var pending_depth: Array[Polygon2D] = []
		for child in area.get_children():
			if not (child is Polygon2D):
				continue
			var polygon := child as Polygon2D
			if polygon.has_meta("depth_layer"):
				pending_depth.append(polygon)
				continue
			var face_bounds := _polygon_bounds(polygon)
			for layer in pending_depth:
				var offset := _polygon_bounds(layer).get_center().distance_to(
					face_bounds.get_center())
				assert_lte(offset / minf(face_bounds.size.x, face_bounds.size.y),
					0.28, "副露厚度不得压过牌面短边")
			pending_depth.clear()


func test_fixture_exercises_all_five_real_meld_kinds_and_visible_shapes() -> void:
	var reference = await _make_reference()
	if reference == null:
		return
	var home_meld: MeldArea = reference.source_table.meld_areas[0]
	var top_meld: MeldArea = reference.source_table.meld_areas[2]
	assert_eq(reference.source_table.seat_panels[0].get("_hand_base_count"), 7,
		"两组副露必须使用合法 7 张暗手")
	for seat_id in [1, 2, 3]:
		assert_eq(reference.source_table.seat_panels[seat_id].get(
			"_hand_base_count"), 10, "一组副露必须使用合法 10 张暗手")
	assert_eq(home_meld.get("_melds").size(), 2)
	assert_eq(top_meld.get("_melds").size(), 1)
	var right_meld: MeldArea = reference.source_table.meld_areas[1]
	var left_meld: MeldArea = reference.source_table.meld_areas[3]
	var actual_kinds: Array[int] = []
	for area in [home_meld, right_meld, top_meld, left_meld]:
		for meld in area.get("_melds"):
			actual_kinds.append(int(meld.kind))
		var visible_polygons: Array = area.get_children().filter(func(child: Node) -> bool:
			return child is Polygon2D)
		assert_gt(visible_polygons.size(), 0,
			"每一种真实副露都必须进入最终 MeldArea 可见节点")
	actual_kinds.sort()
	var expected_kinds: Array[int] = [
		Meld.Kind.CHI, Meld.Kind.PON, Meld.Kind.MINKAN,
		Meld.Kind.ANKAN, Meld.Kind.ADDED_KAN]
	expected_kinds.sort()
	assert_eq(actual_kinds, expected_kinds,
		"真实 MeldArea 必须同时承载吃、碰、明杠、暗杠、加杠")
	var home_faces: Array[Polygon2D] = []
	for child in home_meld.get_children():
		if child is Polygon2D and child.has_meta("tile_id"):
			home_faces.append(child as Polygon2D)
	assert_eq(home_faces.size(), 7, "碰三张 + 明杠四张必须全部进入最终可见节点")
	var minkan_faces := home_faces.slice(3, 7)
	var minkan_sideways := 0
	for face in minkan_faces:
		var bounds := _polygon_bounds(face)
		if bounds.size.x > bounds.size.y:
			minkan_sideways += 1
	assert_eq(minkan_sideways, 1, "真实大明杠必须恰有一张横置被鸣牌")


func test_pose_lab_uses_one_real_beveled_mesh_and_texture_chain() -> void:
	var lab = await _make_pose_lab()
	if lab == null:
		return
	for pose_name in lab.pose_tiles:
		var production_tile: Object = lab.pose_tiles[pose_name] as Object
		assert_true(production_tile is Tile3D,
			"%s 必须直接使用生产 Tile3D，禁止由 example helper 自证" % pose_name)
	var expected_names := [
		"front_standing", "back_standing", "flat_portrait",
		"flat_sideways", "back_flat", "wall_lower", "wall_upper",
		"riichi_sideways", "meld_called_sideways", "meld_companion_left",
		"meld_companion_right", "added_kan_base", "added_kan_top",
		"ankan_left", "ankan_inner_left",
		"ankan_inner_right", "ankan_right", "seat_0", "seat_1",
		"seat_2", "seat_3", "near", "middle", "far",
	]
	assert_eq(lab.pose_tiles.keys(), expected_names,
		"单图必须覆盖单牌、牌山、副露、四席与透视尺度全部确认姿态")
	var shared_mesh: ArrayMesh = null
	var reference_depth := Tile3D.APPROVED_TILE_D
	for pose_name in expected_names:
		var tile := lab.pose_tiles[pose_name] as Tile3D
		assert_not_null(tile, "%s 必须是最终可见 Node3D" % pose_name)
		if tile == null:
			continue
		assert_eq(int(tile.get("tile_id")), TileId.W1,
			"所有姿态必须使用同一张一万，排除牌面差异干扰")
		assert_eq(tile.scale, Vector3.ONE,
			"%s 不得靠缩放伪造近大远小" % pose_name)
		var visible_mesh := tile.get_node_or_null("Mesh") as MeshInstance3D
		assert_not_null(visible_mesh, "%s 必须暴露最终可见牌体" % pose_name)
		if visible_mesh == null:
			continue
		assert_true(visible_mesh.mesh is ArrayMesh)
		var mesh := visible_mesh.mesh as ArrayMesh
		if shared_mesh == null:
			shared_mesh = mesh
		else:
			assert_same(mesh, shared_mesh,
				"所有姿态必须复用同一个物理 mesh，不得逐组手画")
		var mesh_size := mesh.get_aabb().size
		assert_almost_eq(mesh_size.x, Tile3D.TILE_W, 0.00002,
			"统一实体必须保持生产牌宽合同")
		assert_almost_eq(mesh_size.y, reference_depth, 0.00002,
			"统一实体必须使用用户确认的 56mm 日麻厚度")
		assert_almost_eq(mesh_size.z, Tile3D.TILE_H, 0.00002,
			"统一实体必须保持生产牌高合同")
		assert_gte(mesh.get_surface_count(), 5,
			"最终 mesh 须显式包含正面、背面、边线、倒角和侧壁")
		for surface_index in range(mesh.get_surface_count()):
			assert_null(mesh.surface_get_material(surface_index),
				"共享生产 mesh 只能包含几何，禁止写入实例皮肤材质")
		var face_mat := visible_mesh.get_surface_override_material(0) \
			as StandardMaterial3D
		assert_not_null(face_mat, "%s 正面必须进入最终 surface" % pose_name)
		if face_mat != null:
			assert_not_null(face_mat.albedo_texture,
				"%s 必须使用 TextureExtractor 的真实牌面" % pose_name)
		var back_mat := visible_mesh.get_surface_override_material(1) \
			as StandardMaterial3D
		assert_not_null(back_mat, "%s 牌背必须进入最终 surface" % pose_name)
		if back_mat != null:
			assert_not_null(back_mat.albedo_texture,
				"%s 必须从真实牌背纹理生成青岚织界牌背" % pose_name)


func test_pose_lab_uses_the_user_confirmed_riichi_tile_depth_ratio() -> void:
	var lab = await _make_pose_lab()
	if lab == null:
		return
	var tile := lab.pose_tiles["flat_portrait"] as Tile3D
	var contract := (tile.get_script() as Script).get_script_constant_map()
	var reference_depth := float(contract["APPROVED_TILE_D"])
	var reference_height := float(contract["TILE_H"])
	assert_almost_eq(reference_depth, 0.056, 0.000001,
		"单牌实验须把用户确认的日麻 28×21×16 比例映射为 56mm 厚")
	assert_almost_eq(reference_depth / reference_height,
		16.0 / 28.0, 0.000001,
		"厚度/牌高必须严格保持用户确认的 16/28 日麻比例")
	assert_almost_eq(Tile3D.TILE_D, 0.034, 0.000001,
		"既有生产 Tile3D 调用方必须继续默认使用 34mm 厚度")


func test_pose_lab_edge_geometry_keeps_the_final_visible_contract() -> void:
	var lab = await _make_pose_lab()
	if lab == null:
		return
	var tile := lab.pose_tiles["flat_portrait"] as Tile3D
	var visible_mesh := tile.get_node("Mesh") as MeshInstance3D
	var mesh := visible_mesh.mesh as ArrayMesh
	assert_eq(visible_mesh.cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED,
		"双面可见的牌体必须以双面阴影保持倒角明暗，不得依赖错误绕序")
	var contract := (tile.get_script() as Script).get_script_constant_map()
	assert_almost_eq(float(contract["CORNER_RADIUS"]), 0.0072, 0.000001,
		"外轮廓圆角必须锁定为 R7.2")
	assert_almost_eq(float(contract["BEVEL"]), 0.0032, 0.000001,
		"正反面曲面倒角深度不得漂移")
	assert_almost_eq(float(contract["EDGE_LINE"]), 0.00065, 0.000001,
		"牌面嵌入边线必须锁定为 0.65 mm")
	assert_gte(int(contract["CORNER_SEGMENTS"]), 5,
		"四角圆弧必须有足够分段，不能退回切角盒")
	assert_gte(int(contract["BEVEL_SEGMENTS"]), 4,
		"正面倒角必须保持多段明暗过渡")

	var face_vertices := mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] \
		as PackedVector3Array
	var face_bounds := AABB(face_vertices[0], Vector3.ZERO)
	for vertex in face_vertices.slice(1):
		face_bounds = face_bounds.expand(vertex)
	assert_almost_eq(face_bounds.size.x,
		Tile3D.TILE_W - 2.0 * (float(contract["BEVEL"])
		+ float(contract["EDGE_LINE"])), 0.00002,
		"最终可见牌面必须按倒角与嵌入边线等距内收")
	assert_almost_eq(face_bounds.size.z,
		Tile3D.TILE_H - 2.0 * (float(contract["BEVEL"])
		+ float(contract["EDGE_LINE"])), 0.00002)
	var edge_vertices := mesh.surface_get_arrays(2)[Mesh.ARRAY_VERTEX] \
		as PackedVector3Array
	var edge_bounds := AABB(edge_vertices[0], Vector3.ZERO)
	for vertex in edge_vertices.slice(1):
		edge_bounds = edge_bounds.expand(vertex)
	assert_almost_eq(edge_bounds.size.x,
		Tile3D.TILE_W - 2.0 * float(contract["BEVEL"]), 0.00002)
	assert_almost_eq(edge_bounds.size.z,
		Tile3D.TILE_H - 2.0 * float(contract["BEVEL"]), 0.00002)
	assert_almost_eq((edge_bounds.size.x - face_bounds.size.x) * 0.5,
		float(contract["EDGE_LINE"]), 0.00001,
		"最终 surface 的牌面嵌入边线必须四边等厚")
	var bevel_vertices := mesh.surface_get_arrays(3)[Mesh.ARRAY_VERTEX] \
		as PackedVector3Array
	var bevel_bounds := AABB(bevel_vertices[0], Vector3.ZERO)
	var bevel_y_levels := {}
	for vertex in bevel_vertices:
		bevel_bounds = bevel_bounds.expand(vertex)
		bevel_y_levels[roundi(vertex.y * 1000000000.0)] = true
	assert_almost_eq(bevel_bounds.size.x, Tile3D.TILE_W, 0.00002)
	assert_almost_eq(bevel_bounds.size.y, float(contract["BEVEL"]), 0.00002)
	assert_almost_eq(bevel_bounds.size.z, Tile3D.TILE_H, 0.00002)
	assert_eq(bevel_y_levels.size(), int(contract["BEVEL_SEGMENTS"]) + 1,
		"四段倒角必须在最终 mesh 中保留五个连续截面")

	var outer_vertices := mesh.surface_get_arrays(4)[Mesh.ARRAY_VERTEX] \
		as PackedVector3Array
	var radius := float(contract["CORNER_RADIUS"])
	var corner_center := Vector2(Tile3D.TILE_W * 0.5 - radius,
		Tile3D.TILE_H * 0.5 - radius)
	var max_outline_error := 0.0
	for vertex in outer_vertices:
		var delta := Vector2(
			maxf(absf(vertex.x) - corner_center.x, 0.0),
			maxf(absf(vertex.z) - corner_center.y, 0.0))
		max_outline_error = maxf(max_outline_error,
			absf(delta.length() - radius))
	assert_lte(max_outline_error, 0.000001,
		"最终外侧壁的圆弧与直边必须落在同一 R7.2 轮廓上")

	var depth := float(contract["APPROVED_TILE_D"])
	var split_y := -depth * 0.5 + depth / 2.0
	var white_seam := {}
	for vertex in outer_vertices:
		if is_equal_approx(vertex.y, split_y):
			white_seam[Vector2i(roundi(vertex.x * 1000000.0),
				roundi(vertex.z * 1000000.0))] = true
	var green_vertices := mesh.surface_get_arrays(5)[Mesh.ARRAY_VERTEX] \
		as PackedVector3Array
	var green_seam := {}
	for vertex in green_vertices:
		if is_equal_approx(vertex.y, split_y):
			green_seam[Vector2i(roundi(vertex.x * 1000000.0),
				roundi(vertex.z * 1000000.0))] = true
	assert_false(white_seam.is_empty(),
		"青绿 1/2 牌底必须在最终侧壁形成真实分层边界")
	assert_eq(green_seam.size(), white_seam.size(),
		"青绿 1/2 牌底与象牙侧壁必须共享完整边界环")
	for seam_point in white_seam:
		assert_true(green_seam.has(seam_point),
			"青绿背层不得在侧壁接缝处产生裂口")

	var degenerate_triangles: Array[String] = []
	var wrong_winding_triangles: Array[String] = []
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		assert_eq(vertices.size() % 3, 0,
			"surface %d 必须由完整三角形组成" % surface_index)
		assert_eq(normals.size(), vertices.size(),
			"surface %d 每个最终顶点必须有显式法线" % surface_index)
		for vertex_index in range(0, vertices.size(), 3):
			var edge_a := vertices[vertex_index + 1] - vertices[vertex_index]
			var edge_b := vertices[vertex_index + 2] - vertices[vertex_index]
			var geometric_normal := edge_a.cross(edge_b)
			if geometric_normal.length_squared() <= 1.0e-18:
				degenerate_triangles.append(
					"%d:%d" % [surface_index,
						floori(float(vertex_index) / 3.0)])
				continue
			var declared_normal := (normals[vertex_index]
				+ normals[vertex_index + 1]
				+ normals[vertex_index + 2]).normalized()
			# Godot SurfaceTool 以顺时针为正面，几何叉积应与声明法线反向。
			if geometric_normal.dot(declared_normal) >= 0.0:
				wrong_winding_triangles.append(
					"%d:%d" % [surface_index,
						floori(float(vertex_index) / 3.0)])
	assert_true(degenerate_triangles.is_empty(),
		"圆弧与直边衔接不得产生零面积三角形：%s" \
		% str(degenerate_triangles))
	assert_true(wrong_winding_triangles.is_empty(),
		"最终三角形必须遵守 Godot 顺时针正面约定：%s" \
		% str(wrong_winding_triangles))


func test_pose_lab_face_and_ivory_edges_share_one_base_tone() -> void:
	var lab = await _make_pose_lab()
	if lab == null:
		return
	var tile := lab.pose_tiles["flat_portrait"] as Tile3D
	var visible_mesh := tile.get_node("Mesh") as MeshInstance3D
	var face_material := visible_mesh.get_surface_override_material(0) \
		as StandardMaterial3D
	assert_not_null(face_material)
	if face_material == null:
		return
	var face_color := face_material.albedo_color
	assert_gte(face_color.r, 0.95,
		"真实牌面纹理不得靠整体压暗来掩盖贴片与边缘色差")
	assert_gte(face_color.g, 0.95)
	assert_gte(face_color.b, 0.90)
	assert_not_null(face_material.albedo_texture)
	if face_material.albedo_texture == null:
		return
	var face_image := face_material.albedo_texture.get_image()
	assert_not_null(face_image)
	if face_image == null:
		return
	assert_false(face_image.is_empty(), "最终牌面纹理不得返回空 Image")
	if face_image.is_empty():
		return
	for corner in [Vector2i.ZERO,
			Vector2i(face_image.get_width() - 1, 0),
			Vector2i(0, face_image.get_height() - 1),
			Vector2i(face_image.get_width() - 1,
				face_image.get_height() - 1)]:
		var corner_pixel := face_image.get_pixelv(corner)
		assert_gte(corner_pixel.a, 0.99,
			"最终牌面不得保留 2D 牌胚的透明圆角")
		assert_gte(minf(corner_pixel.r,
			minf(corner_pixel.g, corner_pixel.b)), 0.97,
			"最终牌面四角必须是无烘焙光影的中性底色")
	var face_seam_samples := _surface_texture_seam_samples(visible_mesh, 0)
	var face_bounds := _color_bounds(face_seam_samples)
	var seam_min: Vector3 = face_bounds[0]
	var seam_max: Vector3 = face_bounds[1]
	assert_gte(minf(seam_min.x, minf(seam_min.y, seam_min.z)), 0.97,
		"最终 UV 接缝不得带入 2D 牌胚的暗边与固定阴影")
	assert_lte((seam_max - seam_min).length(), 0.02,
		"最终 UV 接缝各位置必须是统一牌胚底色，不能只匹配全圈均值")
	var red_ink_pixels := 0
	var black_ink_pixels := 0
	for y in range(face_image.get_height()):
		for x in range(face_image.get_width()):
			var pixel := face_image.get_pixel(x, y)
			if pixel.r > pixel.g * 1.35 and pixel.r > pixel.b * 1.2 \
					and pixel.r < 0.95:
				red_ink_pixels += 1
			if maxf(pixel.r, maxf(pixel.g, pixel.b)) < 0.35:
				black_ink_pixels += 1
	assert_gt(red_ink_pixels, 500,
		"去除 2D 牌胚时必须保留真实红色牌面图案")
	assert_gt(black_ink_pixels, 200,
		"去除 2D 牌胚时必须保留真实黑色牌面图案")
	var face_seam := _color_average(face_seam_samples)
	var tinted_face_seam := Color(face_seam.r * face_color.r,
		face_seam.g * face_color.g, face_seam.b * face_color.b)
	var seam_chroma := Vector2(tinted_face_seam.g / tinted_face_seam.r,
		tinted_face_seam.b / tinted_face_seam.r)
	var lightness_ranges := {
		2: Vector2(0.98, 1.02),
		3: Vector2(0.56, 0.64),
		4: Vector2(0.66, 0.74),
	}
	for surface_index in [2, 3, 4]:
		var ivory_material := visible_mesh.get_surface_override_material( \
			surface_index) \
			as StandardMaterial3D
		assert_not_null(ivory_material)
		if ivory_material == null:
			continue
		var ivory_color := ivory_material.albedo_color
		var ivory_chroma := Vector2(
			ivory_color.g / ivory_color.r, ivory_color.b / ivory_color.r)
		assert_almost_eq(seam_chroma.x, ivory_chroma.x, 0.01,
			"牌面贴片与象牙边缘必须共用同一基色相")
		assert_almost_eq(seam_chroma.y, ivory_chroma.y, 0.01,
			"牌面贴片不得因独立冷白底色产生纸贴色差")
		var lightness_ratio := ivory_color.r / tinted_face_seam.r
		var allowed := lightness_ranges[surface_index] as Vector2
		assert_gte(lightness_ratio, allowed.x,
			"象牙边缘不得回到与牌面断层的独立暗材质")
		assert_lte(lightness_ratio, allowed.y,
			"倒角和侧壁必须保留高光余量，不能整片剪白")
		assert_almost_eq(ivory_material.roughness,
			face_material.roughness, 0.001,
			"正面与象牙边缘只能由法线产生自然明暗")
		assert_almost_eq(ivory_material.metallic,
			face_material.metallic, 0.001)
	var inset_material := visible_mesh.get_surface_override_material(2) \
		as StandardMaterial3D
	assert_not_null(inset_material)
	if inset_material != null:
		assert_almost_eq(inset_material.albedo_color.r,
			tinted_face_seam.r, 0.025,
			"最终 UV 接缝与 0.65mm 嵌入边线不得形成白色贴片框")
		assert_almost_eq(inset_material.albedo_color.g,
			tinted_face_seam.g, 0.025)
		assert_almost_eq(inset_material.albedo_color.b,
			tinted_face_seam.b, 0.025)


func test_pose_lab_final_transforms_are_physical_not_redrawn() -> void:
	var lab = await _make_pose_lab()
	if lab == null:
		return
	var tiles: Dictionary = lab.pose_tiles
	var flat := tiles["flat_portrait"] as Node3D
	var sideways := tiles["flat_sideways"] as Node3D
	var back := tiles["back_flat"] as Node3D
	var front_standing := tiles["front_standing"] as Node3D
	var back_standing := tiles["back_standing"] as Node3D
	assert_eq(float(lab.TABLE_CLEARANCE), 0.0,
		"单牌与桌面必须真实接触，不得用悬空间隙美化阴影")
	assert_eq(float(lab.STACK_GAP), 0.0,
		"牌山和加杠必须沿厚度轴真实接触")
	assert_eq(front_standing.rotation_degrees, Vector3(90, 0, 0),
		"正面立起只绕 X 轴转向相机")
	assert_eq(back_standing.rotation_degrees, Vector3(-90, 0, 0),
		"牌背立起必须用相反物理旋转展示固定背面")
	assert_almost_eq(front_standing.position.y,
		Tile3D.TILE_H * 0.5 + float(lab.TABLE_CLEARANCE), 0.0001,
		"立起牌必须以牌高计算接触高度，不得穿桌")
	assert_almost_eq(back_standing.position.y,
		front_standing.position.y, 0.0001)
	assert_eq(flat.rotation_degrees, Vector3.ZERO)
	assert_eq(sideways.rotation_degrees, Vector3(0, 90, 0),
		"横置/立直只能让同一实体绕厚度轴旋转 90°")
	assert_eq(back.rotation_degrees, Vector3(180, 0, 0),
		"盖牌必须物理翻面，不能替换成另一张假牌")
	var stack_gap := float(lab.STACK_GAP)
	var depth := Tile3D.APPROVED_TILE_D
	var wall_lower := tiles["wall_lower"] as Node3D
	var wall_upper := tiles["wall_upper"] as Node3D
	assert_almost_eq(wall_lower.position.x, wall_upper.position.x, 0.0001)
	assert_almost_eq(wall_lower.position.z, wall_upper.position.z, 0.0001)
	assert_eq(wall_lower.rotation_degrees, Vector3(180, 0, 0),
		"牌山必须让固定牌背朝上")
	assert_eq(wall_lower.rotation_degrees, wall_upper.rotation_degrees)
	assert_almost_eq(wall_upper.position.y - wall_lower.position.y,
		depth + stack_gap, 0.0001,
		"两层牌山只能沿厚度轴堆叠")
	var kan_base := tiles["added_kan_base"] as Node3D
	var kan_top := tiles["added_kan_top"] as Node3D
	assert_eq((tiles["meld_called_sideways"] as Node3D).rotation_degrees,
		Vector3(0, 90, 0), "吃碰被鸣牌必须是同一牌体横置")
	assert_eq((tiles["meld_companion_left"] as Node3D).rotation_degrees,
		Vector3.ZERO)
	assert_eq((tiles["meld_companion_right"] as Node3D).rotation_degrees,
		Vector3.ZERO)
	assert_eq((tiles["riichi_sideways"] as Node3D).rotation_degrees,
		Vector3(0, 90, 0), "立直牌必须以同一牌体横置")
	assert_almost_eq(kan_base.position.x, kan_top.position.x, 0.0001,
		"加杠上牌必须正叠在被鸣横牌上")
	assert_almost_eq(kan_base.position.z, kan_top.position.z, 0.0001)
	assert_eq(kan_base.rotation_degrees, kan_top.rotation_degrees,
		"加杠上牌必须继承被鸣横牌方向")
	assert_almost_eq(kan_top.position.y - kan_base.position.y,
		depth + stack_gap, 0.0001)
	assert_eq((tiles["ankan_left"] as Node3D).rotation_degrees,
		Vector3(180, 0, 0), "暗杠两端必须以同一牌体盖牌")
	assert_eq((tiles["ankan_right"] as Node3D).rotation_degrees,
		Vector3(180, 0, 0))
	assert_eq((tiles["ankan_inner_left"] as Node3D).rotation_degrees,
		Vector3.ZERO)
	assert_eq((tiles["ankan_inner_right"] as Node3D).rotation_degrees,
		Vector3.ZERO)
	for index in range(4):
		assert_eq((tiles["seat_%d" % index] as Node3D).rotation_degrees.y,
			[0.0, -90.0, 180.0, 90.0][index],
			"四席只旋转同一实体，不得改变牌体比例")
	assert_gt((tiles["near"] as Node3D).global_position.z,
		(tiles["middle"] as Node3D).global_position.z)
	assert_gt((tiles["middle"] as Node3D).global_position.z,
		(tiles["far"] as Node3D).global_position.z,
		"近/中/远必须来自真实相机距离而非节点缩放")


func test_pose_lab_back_color_wraps_one_half_of_the_physical_side() -> void:
	var lab = await _make_pose_lab()
	if lab == null:
		return
	var tile := lab.pose_tiles["flat_portrait"] as Tile3D
	var visible_mesh := tile.get_node("Mesh") as MeshInstance3D
	var mesh := visible_mesh.mesh as ArrayMesh
	var contract := (tile.get_script() as Script).get_script_constant_map()
	var depth := float(contract["APPROVED_TILE_D"])
	assert_gte(mesh.get_surface_count(), 6,
		"牌背颜色必须由独立侧壁几何延伸，不能只给背面贴色")
	if mesh.get_surface_count() < 6:
		return
	var arrays := mesh.surface_get_arrays(5)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	assert_false(vertices.is_empty())
	if vertices.is_empty():
		return
	var min_y := vertices[0].y
	var max_y := vertices[0].y
	for vertex in vertices.slice(1):
		min_y = minf(min_y, vertex.y)
		max_y = maxf(max_y, vertex.y)
	assert_almost_eq(min_y, -depth * 0.5, 0.0001,
		"青绿背层必须从真实牌背表面开始")
	assert_almost_eq(max_y, -depth * 0.5 + depth / 2.0, 0.0002,
		"青绿牌底必须占实体厚度 1/2")
	var back_shell_mat := visible_mesh.get_surface_override_material(5) \
		as StandardMaterial3D
	assert_not_null(back_shell_mat)
	if back_shell_mat != null:
		assert_gt(back_shell_mat.albedo_color.g,
			back_shell_mat.albedo_color.r * 2.0,
			"1/2 侧壁必须使用与牌背一致的青绿色系")
		var back_mat := visible_mesh.get_surface_override_material(1) \
			as StandardMaterial3D
		assert_not_null(back_mat)
		if back_mat == null:
			return
		assert_not_null(back_mat.albedo_texture)
		if back_mat.albedo_texture == null:
			return
		var back_image := back_mat.albedo_texture.get_image()
		assert_not_null(back_image)
		if back_image == null:
			return
		assert_false(back_image.is_empty(), "最终牌背纹理不得返回空 Image")
		if back_image.is_empty():
			return
		for corner in [Vector2i.ZERO,
				Vector2i(back_image.get_width() - 1, 0),
				Vector2i(0, back_image.get_height() - 1),
				Vector2i(back_image.get_width() - 1,
					back_image.get_height() - 1)]:
			assert_gte(back_image.get_pixelv(corner).a, 0.99,
				"最终牌背不得保留 2D 红牌胚的透明圆角")
		var back_seam_samples := _surface_texture_seam_samples(visible_mesh, 1)
		var back_bounds := _color_bounds(back_seam_samples)
		var back_min: Vector3 = back_bounds[0]
		var back_max: Vector3 = back_bounds[1]
		assert_lte((back_max - back_min).length(), 0.02,
			"青绿背纹接缝不得继承 2D 红牌胚的固定高光与暗角")
		var back_seam := _color_average(back_seam_samples)
		var tinted_back_seam := Color(
			back_seam.r * back_mat.albedo_color.r,
			back_seam.g * back_mat.albedo_color.g,
			back_seam.b * back_mat.albedo_color.b)
		var shell_color := back_shell_mat.albedo_color
		assert_almost_eq(shell_color.r / shell_color.g,
			tinted_back_seam.r / tinted_back_seam.g, 0.02,
			"牌背与牌底边缘必须保持同一青绿色相")
		assert_almost_eq(shell_color.b / shell_color.g,
			tinted_back_seam.b / tinted_back_seam.g, 0.02,
			"牌底边缘不得在转面时突变为另一种蓝绿色")
		assert_almost_eq(shell_color.r, tinted_back_seam.r, 0.015,
			"牌背与同朝向青绿边缘必须像素连续，不能留深色贴片框")
		assert_almost_eq(shell_color.g, tinted_back_seam.g, 0.015)
		assert_almost_eq(shell_color.b, tinted_back_seam.b, 0.015)
		assert_almost_eq(back_shell_mat.roughness,
			back_mat.roughness, 0.001,
			"牌背与青绿边缘必须共用同一材质响应")
		assert_almost_eq(back_shell_mat.metallic,
			back_mat.metallic, 0.001)


func test_pose_lab_raster_annotations_expose_the_physical_contract() -> void:
	var lab = await _make_pose_lab()
	if lab == null:
		return
	var visible_text := ""
	for child in lab.find_children("*", "Label", true, false):
		visible_text += (child as Label).text + "\n"
	for required in [
		"72 × 98 × 56", "28:21:16", "牌底 1/2",
		"正面竖牌", "牌背",
		"两层牌山", "立直横牌", "吃 / 碰横置", "加杠上叠",
		"暗杠盖牌", "四席旋转", "近 / 中 / 远",
	]:
		assert_true(visible_text.contains(required),
			"最终 1600×900 图必须直接标注：%s" % required)


func test_pose_lab_keeps_every_mesh_inside_the_uncovered_viewport() -> void:
	var lab = await _make_pose_lab()
	if lab == null:
		return
	for pose_name in lab.pose_tiles:
		var tile := lab.pose_tiles[pose_name] as Node3D
		var viewport := tile.get_viewport() as SubViewport
		assert_not_null(viewport)
		if viewport == null:
			continue
		var host := viewport.get_parent() as SubViewportContainer
		var panel := host.get_parent() as Control
		var footer := panel.get_node_or_null("Footer") as Control
		assert_not_null(footer,
			"%s 所在面板必须暴露实际说明栏边界" % pose_name)
		if footer == null:
			continue
		var host_rect := host.get_global_rect()
		assert_lte(host_rect.end.y, footer.get_global_rect().position.y,
			"%s 的 3D viewport 不得延伸到说明栏背后" % pose_name)
		var camera := viewport.get_camera_3d()
		assert_not_null(camera)
		var visible_mesh := tile.get_node("Mesh") as MeshInstance3D
		var mesh_bounds := visible_mesh.get_aabb()
		var viewport_scale := host.size / Vector2(viewport.size)
		for endpoint_index in range(8):
			var world_point := visible_mesh.global_transform \
				* mesh_bounds.get_endpoint(endpoint_index)
			var viewport_point := camera.unproject_position(world_point)
			var screen_point := host.global_position \
				+ viewport_point * viewport_scale
			assert_true(host_rect.grow(-1.0).has_point(screen_point),
				"%s 的最终牌体角点不得被 viewport 或说明栏裁切" % pose_name)
