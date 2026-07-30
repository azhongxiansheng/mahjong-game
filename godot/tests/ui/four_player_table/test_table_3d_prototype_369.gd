extends GutTest

const SCENE_PATH := \
	"res://examples/table_2_5d_reference/table_3d_prototype_369.tscn"


func _make_table(target_phase: StringName):
	var packed := load(SCENE_PATH) as PackedScene
	assert_not_null(packed)
	if packed == null:
		return null
	var table = packed.instantiate()
	table.phase = target_phase
	add_child_autofree(table)
	await get_tree().process_frame
	await get_tree().process_frame
	return table


func _seat_tiles(table, category: String, seat: int) -> Array:
	return table.tile_groups[category][seat] as Array


func _all_tiles(table) -> Array:
	var output: Array = []
	for category in ["hands", "walls", "rivers", "melds"]:
		for seat in range(4):
			output.append_array(_seat_tiles(table, category, seat))
	return output


func _mesh_world_rect_xz(mesh_instance: MeshInstance3D) -> Rect2:
	var bounds := mesh_instance.get_aabb()
	var first := mesh_instance.global_transform * bounds.get_endpoint(0)
	var result := Rect2(Vector2(first.x, first.z), Vector2.ZERO)
	for index in range(1, 8):
		var point := mesh_instance.global_transform * bounds.get_endpoint(index)
		result = result.expand(Vector2(point.x, point.z))
	return result


func _tiles_world_rect_xz(tiles: Array) -> Rect2:
	var first := tiles[0] as Tile3D
	var result := _mesh_world_rect_xz(first._mesh)
	for index in range(1, tiles.size()):
		result = result.merge(_mesh_world_rect_xz((tiles[index] as Tile3D)._mesh))
	return result


func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(a.position.x - b.end.x,
		b.position.x - a.end.x), 0.0)
	var dz := maxf(maxf(a.position.y - b.end.y,
		b.position.y - a.end.y), 0.0)
	return Vector2(dx, dz).length()


func _rotate_from_south(point: Vector3, seat: int) -> Vector3:
	match seat:
		1:
			return Vector3(point.z, point.y, -point.x)
		2:
			return Vector3(-point.x, point.y, -point.z)
		3:
			return Vector3(-point.z, point.y, point.x)
	return point


func _assert_real_production_tiles(tiles: Array, context: String) -> void:
	assert_false(tiles.is_empty(), "%s 必须包含最终可见牌" % context)
	if tiles.is_empty():
		return
	var shared_mesh := (tiles[0] as Tile3D)._mesh.mesh
	for tile_node in tiles:
		assert_true(tile_node is Tile3D,
			"%s 禁止用 Polygon2D / BoxMesh 冒充麻将牌" % context)
		if not (tile_node is Tile3D):
			continue
		var tile := tile_node as Tile3D
		assert_almost_eq(tile.get_geometry_depth(),
			Tile3D.APPROVED_TILE_D, 0.000001)
		assert_eq(tile.scale, Vector3.ONE,
			"近大远小只能来自同一相机，禁止缩放牌体")
		assert_same(tile._mesh.mesh, shared_mesh,
			"同一 56mm 牌桌必须复用生产 ArrayMesh")
		for surface_index in range(tile._mesh.mesh.get_surface_count()):
			assert_null(tile._mesh.mesh.surface_get_material(surface_index),
				"共享 mesh 只允许保存几何")


func test_table_3d_prototype_is_a_real_runnable_scene() -> void:
	assert_true(ResourceLoader.exists(SCENE_PATH),
		"#369 B 阶段必须提供可运行的真实 1600×900 Tile3D 组桌场景")
	if not ResourceLoader.exists(SCENE_PATH):
		return
	var table = await _make_table(&"hands")
	if table == null:
		return
	assert_not_null(table.get_script(), "场景脚本不得因 Parse Error 静默丢失")
	assert_eq(table.size, Vector2(1600, 900))
	assert_not_null(table.viewport)
	assert_eq(table.find_children("*", "SubViewport", true, false).size(), 1,
		"整桌必须共享一个 3D viewport，禁止每张牌单独渲染")
	assert_not_null(table.camera)
	assert_eq(table.camera.get_viewport(), table.viewport)


func test_prototype_capture_contains_only_table_and_tile_entities() -> void:
	var table = await _make_table(&"hands")
	if table == null:
		return
	assert_eq(table.find_children("*", "Panel", true, false).size(), 0,
		"本轮只验收牌桌摆放，禁止分数、操作带或中央文字面板遮挡")
	assert_eq(table.find_children("*", "Label", true, false).size(), 0,
		"截图不得保留标题、阶段或分数文字")
	assert_eq(table.find_children("*", "ColorRect", true, false).size(), 0,
		"截图不得保留牌桌之外的说明底板")


func test_square_table_uses_one_rotated_layout_for_all_four_seats() -> void:
	var table = await _make_table(&"opening")
	if table == null:
		return
	assert_almost_eq(table.TABLE_SIZE.x, table.TABLE_SIZE.y, 0.000001,
		"实体桌面必须是正方形")
	var felt := table.world_root.get_node("Felt") as MeshInstance3D
	var felt_size := felt.get_aabb().size
	assert_almost_eq(felt_size.x, felt_size.z, 0.000001,
		"最终可见桌布必须是正方形，不只改常量")
	var center_plate := table.world_root.get_node("CenterPlate") as MeshInstance3D
	var center_size := center_plate.get_aabb().size
	assert_almost_eq(center_size.x, center_size.z, 0.000001,
		"中央物理盘也须保持四席旋转对称")
	for category in ["hands", "walls"]:
		var south := _seat_tiles(table, category, 0)
		for seat in range(1, 4):
			var rotated := _seat_tiles(table, category, seat)
			assert_eq(rotated.size(), south.size())
			for index in range(south.size()):
				var expected := _rotate_from_south(
					(south[index] as Tile3D).position, seat)
				assert_true((rotated[index] as Tile3D).position.is_equal_approx(
					expected),
					"%s 四席必须复用同一局部坐标并逐席旋转 90°" % category)


func _surface_vertices_at_y(mesh: ArrayMesh, surface_index: int,
		expected_y: float) -> Dictionary:
	var output := {}
	var arrays := mesh.surface_get_arrays(surface_index)
	var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	for vertex in vertices:
		if is_equal_approx(vertex.y, expected_y):
			output[Vector3i(roundi(vertex.x * 1000000.0),
				roundi(vertex.y * 1000000.0),
				roundi(vertex.z * 1000000.0))] = true
	return output


func _assert_boundary_is_shared(smaller: Dictionary, larger: Dictionary,
		context: String) -> void:
	assert_false(smaller.is_empty(), "%s 必须包含真实边界顶点" % context)
	for point in smaller:
		assert_true(larger.has(point), "%s 不得出现几何裂口：%s" % [
			context, str(point)])


func test_table_uses_procedural_qinglan_felt_and_continuous_wood_frame() -> void:
	var table = await _make_table(&"hands")
	if table == null:
		return
	var felt := table.world_root.get_node("Felt") as MeshInstance3D
	assert_true(felt.material_override is ShaderMaterial,
		"桌布必须使用低反光细织纹材质，禁止继续使用纯色塑料面")
	if felt.material_override is ShaderMaterial:
		var felt_material := felt.material_override as ShaderMaterial
		assert_eq(felt_material.get_shader_parameter("felt_base"),
			Color("0c4944"), "桌布保持青岚织界的低反光青绿基色")
	for legacy_name in ["TopRail", "BottomRail", "LeftRail", "RightRail"]:
		assert_null(table.world_root.get_node_or_null(legacy_name),
			"木框不得继续由四根 BoxMesh 硬拼：%s" % legacy_name)
	var frame := table.world_root.get_node_or_null("FrameRing") as MeshInstance3D
	assert_not_null(frame, "木框必须是唯一连续的 FrameRing 实体")
	if frame == null:
		return
	assert_true(frame.mesh is ArrayMesh,
		"木框须用单一连续 ArrayMesh 表达转角和立体截面")
	assert_null(frame.material_override,
		"禁止用全局 override 掩盖最终各截面的真实材质绑定")
	if not (frame.mesh is ArrayMesh):
		return
	var mesh := frame.mesh as ArrayMesh
	assert_eq(mesh.get_surface_count(), 5,
		"木框只保留四个可见截面和一个闭合底壳")
	var expected_surfaces := [
		"InnerSlope", "TopCrown", "OuterBevel", "SideWall", "LowerShell",
	]
	for surface_index in range(mini(mesh.get_surface_count(),
			expected_surfaces.size())):
		assert_eq(mesh.surface_get_name(surface_index),
			expected_surfaces[surface_index])
		assert_eq(mesh.surface_get_primitive_type(surface_index),
			Mesh.PRIMITIVE_TRIANGLES)
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		assert_false(vertices.is_empty(),
			"%s 必须直接进入最终可见 mesh" % expected_surfaces[surface_index])
		assert_eq(normals.size(), vertices.size(),
			"%s 的每个最终顶点都必须有显式法线" % expected_surfaces[surface_index])
		var material := mesh.surface_get_material(surface_index)
		assert_true(material is ShaderMaterial,
			"%s 必须显式绑定深木纹材质" % expected_surfaces[surface_index])
		if material is ShaderMaterial:
			assert_eq((material as ShaderMaterial).get_shader_parameter(
				"wood_base"), Color("4e1d11"),
				"木框基色沿用 2D TableStage 的深红木抽象")
	var bounds := mesh.get_aabb()
	assert_almost_eq(bounds.size.x, bounds.size.z, 0.000001,
		"连续木框外轮廓必须保持正方形")
	assert_almost_eq(bounds.get_center().x, 0.0, 0.000001)
	assert_almost_eq(bounds.get_center().z, 0.0, 0.000001)
	assert_gte(bounds.end.y, table.TABLE_TOP_Y + 0.025,
		"顶冠必须真实抬高，不能继续像平面贴片")
	assert_lte(bounds.position.y, table.TABLE_TOP_Y - 0.070,
		"外侧壁必须下沉形成可见木框厚度")
	if mesh.get_surface_count() == 5:
		var top_vertices := mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX] \
			as PackedVector3Array
		var top_y_levels := {}
		for vertex in top_vertices:
			top_y_levels[roundi(vertex.y * 1000000.0)] = true
		assert_gte(top_y_levels.size(), 2,
			"顶面必须有拱起截面，禁止退回单一水平面")
		_assert_boundary_is_shared(_surface_vertices_at_y(mesh, 0, 0.034),
			_surface_vertices_at_y(mesh, 1, 0.034), "内斜面 → 顶冠")
		_assert_boundary_is_shared(_surface_vertices_at_y(mesh, 2, 0.024),
			_surface_vertices_at_y(mesh, 1, 0.024), "顶冠 → 外倒角")
		_assert_boundary_is_shared(_surface_vertices_at_y(mesh, 3, 0.004),
			_surface_vertices_at_y(mesh, 2, 0.004), "外倒角 → 下沉侧壁")
		_assert_boundary_is_shared(_surface_vertices_at_y(mesh, 4, -0.080),
			_surface_vertices_at_y(mesh, 3, -0.080), "下沉侧壁 → 闭合底壳")
		var wood_material := mesh.surface_get_material(0) as ShaderMaterial
		if wood_material != null:
			assert_string_contains(wood_material.shader.code,
				"wood_position = VERTEX",
				"木纹必须由连续实体坐标采样，禁止四条边各自重启 UV")


func test_hands_phase_uses_four_seats_of_13_real_standing_tiles() -> void:
	var table = await _make_table(&"hands")
	if table == null:
		return
	var hands: Array = []
	for seat in range(4):
		var seat_hand := _seat_tiles(table, "hands", seat)
		assert_eq(seat_hand.size(), 13)
		hands.append_array(seat_hand)
		for tile_node in seat_hand:
			var tile := tile_node as Tile3D
			var y_range: Vector2 = table.tile_world_y_range(tile)
			assert_almost_eq(y_range.x, table.TABLE_TOP_Y, 0.00002,
				"四席立牌底边必须真实接桌")
			assert_true(tile.face_up,
				"立牌须保持物理正向，三家隐藏信息由背面朝向观察者实现")
			assert_true(tile.tile_id >= 0 if seat == 0 else tile.tile_id < 0,
				"仅自家注入真实牌面，三家必须隐藏 tile_id")
	assert_eq(hands.size(), 52)
	_assert_real_production_tiles(hands, "四席手牌")


func test_hands_use_exact_quarter_turn_frames_and_top_view_mirrors() -> void:
	var table = await _make_table(&"hands")
	if table == null:
		return
	var expected_x := [Vector3.RIGHT, Vector3.FORWARD,
		Vector3.LEFT, Vector3.BACK]
	var expected_y := [Vector3.BACK, Vector3.RIGHT,
		Vector3.FORWARD, Vector3.LEFT]
	for seat in range(4):
		var side_hand := _seat_tiles(table, "hands", seat)
		var first := side_hand[0] as Tile3D
		var second := side_hand[1] as Tile3D
		assert_true(first.basis.x.is_equal_approx(expected_x[seat]),
			"四席牌宽轴必须由同一立牌逐席精确旋转 90°")
		assert_true(first.basis.y.is_equal_approx(expected_y[seat]),
			"四席牌面法线必须精确朝向各自座位，禁止为主镜头斜切实体")
		assert_true(first.basis.z.is_equal_approx(Vector3.DOWN),
			"四席立牌必须共享同一向下高度轴")
		var center_step := (second.position - first.position).normalized()
		assert_gte(center_step.dot(first.basis.x.normalized()), 0.999,
			"相邻手牌中心必须沿该席牌宽轴前进，禁止产生锯齿叠压")
		assert_almost_eq(first.position.distance_to(second.position),
			table.HAND_GAP, 0.000001,
			"四席手牌必须共享同一中心步长")
	var right_hand := _seat_tiles(table, "hands", 1)
	var left_hand := _seat_tiles(table, "hands", 3)
	for index in range(right_hand.size()):
		assert_almost_eq((right_hand[index] as Tile3D).position.x,
			-(left_hand[index] as Tile3D).position.x, 0.00001)
		assert_almost_eq((right_hand[index] as Tile3D).position.z,
			-(left_hand[index] as Tile3D).position.z, 0.00001,
			"左右手牌必须先在俯视世界坐标中逐张做 180° 镜像")
	assert_true(table.has_method("set_camera_view"),
		"prototype 必须提供俯视与四席诊断镜头，不能只凭主镜头硬调")
	if table.has_method("set_camera_view"):
		for view_name in [&"top", &"south", &"east", &"north", &"west"]:
			assert_true(table.set_camera_view(view_name),
				"必须可切换诊断视角：%s" % view_name)
		assert_true(table.set_camera_view(&"top"))
		await get_tree().process_frame
		for index in range(right_hand.size()):
			var right_screen: Vector2 = table.camera.unproject_position(
				(right_hand[index] as Tile3D).global_position)
			var left_screen: Vector2 = table.camera.unproject_position(
				(left_hand[index] as Tile3D).global_position)
			assert_almost_eq(right_screen.x + left_screen.x, 1600.0, 0.2)
			assert_almost_eq(right_screen.y + left_screen.y, 900.0, 0.2,
				"俯视投影必须证明左右手牌逐张中心对称")
		assert_true(table.set_camera_view(&"main"))
	var frame_contract := (table.get_script() as Script).get_script_constant_map()
	var inner_half := float(frame_contract.get("FRAME_INNER_HALF", 0.0))
	assert_gt(inner_half - table.HAND_RADIUS,
		Tile3D.APPROVED_TILE_D * 0.5,
		"抬高后的木框内沿仍须给四席立牌保留真实净空")


func test_top_and_four_seat_cameras_keep_every_tile_inside_safe_frame() -> void:
	var table = await _make_table(&"crowded")
	if table == null:
		return
	var safe_frame := Rect2(Vector2(8, 8), Vector2(1584, 884))
	assert_true(table.set_camera_view(&"south"))
	var south_position: Vector3 = table.camera.position
	var south_basis: Basis = table.camera.basis
	var seat_views := [&"south", &"east", &"north", &"west"]
	for seat in range(4):
		assert_true(table.set_camera_view(seat_views[seat]))
		assert_true(table.camera.position.is_equal_approx(
			_rotate_from_south(south_position, seat)),
			"四席诊断相机位置必须由同一基准逐席旋转 90°")
		for axis in range(3):
			assert_true(table.camera.basis[axis].is_equal_approx(
				_rotate_from_south(south_basis[axis], seat)),
				"四席诊断相机姿态必须由同一基准逐席旋转 90°")
		for tile_node in _all_tiles(table):
			assert_true(safe_frame.encloses(table.tile_screen_bounds(
				tile_node as Tile3D)),
				"四席诊断图中的真实牌不得贴边或裁切：seat=%d" % seat)
	assert_true(table.set_camera_view(&"top"))
	for tile_node in _all_tiles(table):
		assert_true(safe_frame.encloses(table.tile_screen_bounds(
			tile_node as Tile3D)), "俯视校准图中的真实牌不得贴边或裁切")
	assert_true(table.set_camera_view(&"main"))


func test_opening_phase_builds_17_by_2_real_wall_stacks_per_side() -> void:
	var table = await _make_table(&"opening")
	if table == null:
		return
	var walls: Array = []
	for seat in range(4):
		var seat_wall := _seat_tiles(table, "walls", seat)
		assert_eq(seat_wall.size(), 34,
			"每边必须是 17 墩 × 两层真实 Tile3D")
		walls.append_array(seat_wall)
		var lower_tiles := seat_wall.filter(func(tile: Tile3D) -> bool:
			return int(tile.get_meta("layer")) == 0)
		for stack_index in range(1, lower_tiles.size()):
			assert_almost_eq((lower_tiles[stack_index] as Tile3D).position.distance_to(
				(lower_tiles[stack_index - 1] as Tile3D).position),
				Tile3D.TILE_W + 0.004, 0.000001,
				"四边牌山相邻墩必须共享同一中心步长")
		for stack_index in range(17):
			var lower: Tile3D = null
			var upper: Tile3D = null
			for tile_node in seat_wall:
				var tile := tile_node as Tile3D
				if int(tile.get_meta("stack_index")) != stack_index:
					continue
				if int(tile.get_meta("layer")) == 0:
					lower = tile
				else:
					upper = tile
			assert_not_null(lower)
			assert_not_null(upper)
			if lower == null or upper == null:
				continue
			var lower_range: Vector2 = table.tile_world_y_range(lower)
			var upper_range: Vector2 = table.tile_world_y_range(upper)
			assert_almost_eq(lower_range.x, table.TABLE_TOP_Y, 0.00002)
			assert_almost_eq(lower_range.y, upper_range.x, 0.00002,
				"牌山上下层必须零间隙真实接触")
			assert_false(lower.face_up)
			assert_false(upper.face_up)
	assert_eq(walls.size(), 136)
	assert_eq(_seat_tiles(table, "rivers", 0).size(), 0)
	assert_eq(_seat_tiles(table, "melds", 0).size(), 0)
	_assert_real_production_tiles(walls, "四边牌山")


func test_crowded_rivers_use_6_by_3_and_exact_opposite_seat_mirrors() -> void:
	var table = await _make_table(&"crowded")
	if table == null:
		return
	var rivers: Array = []
	for seat in range(4):
		var river := _seat_tiles(table, "rivers", seat)
		assert_eq(river.size(), 18)
		rivers.append_array(river)
		var riichi_count := 0
		for row in range(3):
			assert_eq(river.filter(func(tile: Tile3D) -> bool:
				return int(tile.get_meta("row")) == row).size(), 6,
				"每席牌河必须严格 6/6/6")
		for tile_node in river:
			var tile := tile_node as Tile3D
			if bool(tile.get_meta("riichi")):
				riichi_count += 1
			var bounds: Rect2 = table.tile_screen_bounds(tile)
			assert_true(Rect2(Vector2.ZERO, Vector2(1600, 900)).encloses(bounds),
				"最终河牌不得被 1600×900 viewport 裁切")
		assert_eq(riichi_count, 1,
			"每席必须由同一 Tile3D 横置一张立直牌")
	var bottom := _seat_tiles(table, "rivers", 0)
	var right := _seat_tiles(table, "rivers", 1)
	var top := _seat_tiles(table, "rivers", 2)
	var left := _seat_tiles(table, "rivers", 3)
	for index in range(18):
		assert_almost_eq((bottom[index] as Tile3D).position.x,
			-(top[index] as Tile3D).position.x, 0.000001)
		assert_almost_eq((bottom[index] as Tile3D).position.z,
			-(top[index] as Tile3D).position.z, 0.000001)
		assert_almost_eq((right[index] as Tile3D).position.x,
			-(left[index] as Tile3D).position.x, 0.000001)
		assert_almost_eq((right[index] as Tile3D).position.z,
			-(left[index] as Tile3D).position.z, 0.000001)
		for seat in range(1, 4):
			var rotated := _seat_tiles(table, "rivers", seat)[index] as Tile3D
			assert_true(rotated.position.is_equal_approx(_rotate_from_south(
				(bottom[index] as Tile3D).position, seat)),
				"四席牌河必须由同一 6×3 局部网格逐席旋转 90°")
			var expected_yaw: float = float(
				[0.0, -90.0, 180.0, 90.0][seat]) \
				+ (90.0 if bool(rotated.get_meta("riichi")) else 0.0)
			assert_almost_eq(fposmod(rotated.rotation_degrees.y, 360.0),
				fposmod(expected_yaw, 360.0), 0.00001,
				"立直牌只能在该席基准 yaw 上追加 90°")
	_assert_real_production_tiles(rivers, "四席 6/6/6 牌河")


func test_top_view_zones_have_real_world_clearance_without_overlap() -> void:
	var table = await _make_table(&"crowded")
	if table == null:
		return
	var center_nodes := ["CenterPlate", "CenterGoldTop", "CenterGoldBottom",
		"CenterGoldLeft", "CenterGoldRight"]
	var center_rect := _mesh_world_rect_xz(
		table.world_root.get_node(center_nodes[0]) as MeshInstance3D)
	for index in range(1, center_nodes.size()):
		center_rect = center_rect.merge(_mesh_world_rect_xz(
			table.world_root.get_node(center_nodes[index]) as MeshInstance3D))
	for seat in range(4):
		var hands_rect := _tiles_world_rect_xz(_seat_tiles(table, "hands", seat))
		var walls_rect := _tiles_world_rect_xz(_seat_tiles(table, "walls", seat))
		var rivers_rect := _tiles_world_rect_xz(_seat_tiles(table, "rivers", seat))
		assert_gte(_rect_gap(rivers_rect, center_rect), table.TILE_GAP - 0.0001,
			"牌河不得穿进中央盘或金属结构线：seat=%d" % seat)
		assert_gte(_rect_gap(rivers_rect, walls_rect), table.TILE_GAP - 0.0001,
			"牌河与牌山之间必须保留真实桌毡缝：seat=%d" % seat)
		assert_gte(_rect_gap(walls_rect, hands_rect), table.TILE_GAP - 0.0001,
			"牌山与手牌之间必须保留真实桌毡缝：seat=%d" % seat)
		var melds := _seat_tiles(table, "melds", seat)
		if not melds.is_empty():
			var melds_rect := _tiles_world_rect_xz(melds)
			assert_gte(_rect_gap(melds_rect, walls_rect), table.TILE_GAP - 0.0001,
				"副露与牌山不得并成一体：seat=%d" % seat)
			assert_gte(_rect_gap(melds_rect, hands_rect), table.TILE_GAP - 0.0001,
				"副露与暗手不得并成一体：seat=%d" % seat)


func test_five_meld_kinds_follow_real_meld_layout_slots() -> void:
	var table = await _make_table(&"crowded")
	if table == null:
		return
	assert_eq(table.meld_fixtures.size(), 5)
	var actual_kinds: Array[int] = []
	var all_meld_tiles: Array = []
	for fixture_name in table.meld_fixtures:
		var meld := table.meld_fixtures[fixture_name] as Meld
		var visible := table.meld_tiles[fixture_name] as Array
		var seat := int((visible[0] as Tile3D).get_meta("seat_id"))
		var slots := MeldLayout.compute(meld, seat)
		assert_eq(visible.size(), slots.size())
		actual_kinds.append(int(meld.kind))
		all_meld_tiles.append_array(visible)
		for index in range(slots.size()):
			var tile := visible[index] as Tile3D
			var slot := slots[index] as Dictionary
			assert_eq(int(tile.get_meta("slot_index")), index)
			assert_eq(bool(tile.get_meta("rotated")), bool(slot["rotated"]))
			assert_eq(bool(tile.get_meta("face_down")), bool(slot["face_down"]))
			assert_eq(bool(tile.get_meta("stacked_above")),
				bool(slot["stacked_above"]))
			assert_eq(tile.face_up, not bool(slot["face_down"]))
	actual_kinds.sort()
	var expected_kinds: Array[int] = [
		Meld.Kind.CHI, Meld.Kind.PON, Meld.Kind.MINKAN,
		Meld.Kind.ANKAN, Meld.Kind.ADDED_KAN,
	]
	expected_kinds.sort()
	assert_eq(actual_kinds, expected_kinds,
		"最终真实节点必须同时覆盖吃、碰、大明杠、暗杠、加杠")
	var ankan := table.meld_tiles[&"ankan"] as Array
	assert_eq(ankan.filter(func(tile: Tile3D) -> bool:
		return bool(tile.get_meta("face_down"))).size(), 2,
		"暗杠两端必须用生产牌背盖牌")
	var minkan := table.meld_tiles[&"minkan"] as Array
	assert_eq(minkan.filter(func(tile: Tile3D) -> bool:
		return bool(tile.get_meta("rotated"))).size(), 1,
		"大明杠必须有一张真实横置被鸣牌")
	var added := table.meld_tiles[&"added_kan"] as Array
	var stacked := added.filter(func(tile: Tile3D) -> bool:
		return bool(tile.get_meta("stacked_above")))
	var rotated_base := added.filter(func(tile: Tile3D) -> bool:
		return bool(tile.get_meta("rotated")) \
			and not bool(tile.get_meta("stacked_above")))
	assert_eq(stacked.size(), 1)
	assert_eq(rotated_base.size(), 1)
	if stacked.size() == 1 and rotated_base.size() == 1:
		var top_tile := stacked[0] as Tile3D
		var base_tile := rotated_base[0] as Tile3D
		assert_almost_eq(top_tile.position.x, base_tile.position.x, 0.000001)
		assert_almost_eq(top_tile.position.z, base_tile.position.z, 0.000001)
		assert_almost_eq(top_tile.position.y - base_tile.position.y,
			Tile3D.APPROVED_TILE_D, 0.000001,
			"加杠上牌必须沿厚度轴零间隙接触")
		assert_eq(top_tile.rotation_degrees, base_tile.rotation_degrees)
	assert_eq(all_meld_tiles.size(), 18)
	_assert_real_production_tiles(all_meld_tiles, "五类副露")


func test_crowded_table_tile_root_contains_no_fake_tile_body() -> void:
	var table = await _make_table(&"crowded")
	if table == null:
		return
	var final_tiles := _all_tiles(table)
	assert_eq(table.tile_root.get_child_count(), final_tiles.size())
	for child in table.tile_root.get_children():
		assert_true(child is Tile3D,
			"ProductionTiles 直属可见实体必须全部是生产 Tile3D")
