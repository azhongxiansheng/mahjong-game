extends Control

## #369 Phase 1 / B：只用于 1600×900 真实 Tile3D 组桌验证。
## 不接 PlayableTable，不切换生产默认渲染路径。

const PHASE_HANDS := &"hands"
const PHASE_OPENING := &"opening"
const PHASE_MIDGAME := &"midgame"
const PHASE_CROWDED := &"crowded"
const VALID_PHASES := [
	PHASE_HANDS, PHASE_OPENING, PHASE_MIDGAME, PHASE_CROWDED,
]
const CAMERA_VIEWS := [
	&"main", &"top", &"south", &"east", &"north", &"west",
]

const TABLE_SIZE := Vector2(2.40, 2.40)
const TABLE_TOP_Y := 0.0
const FRAME_INNER_HALF := 1.196
const FRAME_INNER_MID_HALF := 1.214
const FRAME_INNER_SHOULDER_HALF := 1.234
const FRAME_CROWN_HALF := 1.260
const FRAME_OUTER_SHOULDER_HALF := 1.278
const FRAME_BEVEL_HALF := 1.289
const FRAME_OUTER_HALF := 1.290
const FRAME_LOWER_INNER_HALF := 1.205
const FRAME_INNER_LIP_Y := 0.001
const FRAME_INNER_MID_Y := 0.024
const FRAME_INNER_SHOULDER_Y := 0.034
const FRAME_CROWN_Y := 0.035
const FRAME_OUTER_SHOULDER_Y := 0.024
const FRAME_BEVEL_Y := 0.004
const FRAME_SIDE_BOTTOM_Y := -0.080
const FRAME_SHELL_BOTTOM_Y := -0.092
const FRAME_INNER_BOTTOM_Y := -0.070
const FRAME_INNER_CORNER_RADIUS := 0.024
const FRAME_CORNER_SEGMENTS := 8
const TILE_GAP := 0.006
const HAND_GAP := 0.076
const HAND_RADIUS := 1.03
const RIVER_COLUMN_GAP := 0.083
const RIVER_ROW_GAP := 0.112
const RIVER_INNER := 0.34
const WALL_RADIUS := 0.78
const MELD_RADIUS := 0.92
const WALL_STACKS := 17

var phase: StringName = PHASE_CROWDED
var viewport: SubViewport
var world_root: Node3D
var tile_root: Node3D
var camera: Camera3D
var tile_groups: Dictionary = {}
var meld_fixtures: Dictionary = {}
var meld_tiles: Dictionary = {}
var _next_fixture_instance_id := 369000
static var _felt_shader: Shader = null
static var _wood_shader: Shader = null


func _ready() -> void:
	custom_minimum_size = Vector2(1600, 900)
	size = Vector2(1600, 900)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var requested := StringName(OS.get_environment("MAHJONG_369_TABLE_PHASE"))
	if VALID_PHASES.has(requested):
		phase = requested
	_build_viewport()
	_build_world()
	rebuild_phase(phase)


func rebuild_phase(next_phase: StringName) -> void:
	phase = next_phase if VALID_PHASES.has(next_phase) else PHASE_CROWDED
	_clear_tiles()
	_reset_groups()
	var hand_counts := [13, 13, 13, 13]
	if phase == PHASE_MIDGAME or phase == PHASE_CROWDED:
		hand_counts = [7, 10, 10, 10]
	_build_hands(hand_counts)
	if phase != PHASE_HANDS:
		_build_walls()
	if phase == PHASE_MIDGAME:
		_build_rivers(12)
		_build_melds()
	elif phase == PHASE_CROWDED:
		_build_rivers(18)
		_build_melds()


func _build_viewport() -> void:
	var host := SubViewportContainer.new()
	host.name = "ViewportHost"
	host.position = Vector2.ZERO
	host.size = Vector2(1600, 900)
	host.stretch = true
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)
	viewport = SubViewport.new()
	viewport.name = "TableViewport"
	viewport.size = Vector2i(1600, 900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	host.add_child(viewport)
	world_root = Node3D.new()
	world_root.name = "World"
	viewport.add_child(world_root)
	tile_root = Node3D.new()
	tile_root.name = "ProductionTiles"
	world_root.add_child(tile_root)


func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("061315")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("cedbd4")
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	world_root.add_child(environment_node)

	var felt := _felt_material()
	_add_box(Vector3(TABLE_SIZE.x, 0.07, TABLE_SIZE.y),
		Vector3(0, -0.035, 0), felt, "Felt")
	var wood := _wood_material()
	_add_frame_ring(wood)

	var center_material := _material(Color("0b202d"), 0.74, 0.08)
	_add_box(Vector3(0.54, 0.036, 0.54), Vector3(0, 0.018, 0),
		center_material, "CenterPlate")
	var gold := _material(Color("9c814d"), 0.36, 0.52)
	_add_box(Vector3(0.56, 0.006, 0.009), Vector3(0, 0.039, -0.275),
		gold, "CenterGoldTop")
	_add_box(Vector3(0.56, 0.006, 0.009), Vector3(0, 0.039, 0.275),
		gold, "CenterGoldBottom")
	_add_box(Vector3(0.009, 0.006, 0.55), Vector3(-0.275, 0.039, 0),
		gold, "CenterGoldLeft")
	_add_box(Vector3(0.009, 0.006, 0.55), Vector3(0.275, 0.039, 0),
		gold, "CenterGoldRight")
	_add_box(Vector3(0.12, 0.012, 0.018), Vector3(0, 0.048, 0.16),
		gold, "TurnMarker")

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-54, -32, 0)
	key.light_color = Color("fff0cf")
	key.light_energy = 2.0
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 6.0
	world_root.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.0, 2.1, 1.8)
	fill.light_color = Color("a8d9d2")
	fill.light_energy = 1.15
	fill.omni_range = 5.5
	world_root.add_child(fill)

	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 38.0
	camera.near = 0.04
	camera.current = true
	world_root.add_child(camera)
	var requested_view := StringName(
		OS.get_environment("MAHJONG_369_TABLE_VIEW"))
	set_camera_view(requested_view if CAMERA_VIEWS.has(requested_view)
		else &"main")


func set_camera_view(view_name: StringName) -> bool:
	if camera == null or not CAMERA_VIEWS.has(view_name):
		return false
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 30.0
	match view_name:
		&"top":
			camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			camera.size = 2.72
			camera.look_at_from_position(Vector3(0, 4.0, 0),
				Vector3.ZERO, Vector3.FORWARD)
		_:
			var camera_seat := {
				&"east": 1,
				&"north": 2,
				&"west": 3,
			}.get(view_name, 0) as int
			camera.look_at_from_position(
				_rotate_from_south(Vector3(0, 3.20, 3.40), camera_seat),
				Vector3(0, 0.02, 0), Vector3.UP)
	return true


func _rotate_from_south(point: Vector3, seat: int) -> Vector3:
	match seat:
		1:
			return Vector3(point.z, point.y, -point.x)
		2:
			return Vector3(-point.x, point.y, -point.z)
		3:
			return Vector3(-point.z, point.y, point.x)
	return point


func _clear_tiles() -> void:
	for child in tile_root.get_children():
		child.queue_free()
	meld_fixtures.clear()
	meld_tiles.clear()


func _reset_groups() -> void:
	tile_groups = {
		"hands": [[], [], [], []],
		"walls": [[], [], [], []],
		"rivers": [[], [], [], []],
		"melds": [[], [], [], []],
	}


func _build_hands(counts: Array) -> void:
	for seat in range(4):
		var count: int = counts[seat]
		var span := float(count - 1) * HAND_GAP
		for index in range(count):
			var tile_id := TileId.ALL[(seat * 7 + index) % TileId.ALL.size()]
			var visible_face := seat == 0
			var tile := _create_tile(tile_id if visible_face else -1,
				true, false, "hands", seat)
			var offset := -span * 0.5 + float(index) * HAND_GAP
			var basis := _hand_basis(seat)
			var center := _rotate_from_south(
				Vector3(0, Tile3D.TILE_H * 0.5, HAND_RADIUS), seat)
			var tile_position := center + basis.x * offset
			tile.transform = Transform3D(basis, tile_position)
			tile.set_meta("hand_index", index)


func _hand_basis(seat: int) -> Basis:
	match seat:
		0:
			return Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
		1:
			return Basis(Vector3.FORWARD, Vector3.RIGHT, Vector3.DOWN)
		2:
			return Basis(Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN)
		3:
			return Basis(Vector3.BACK, Vector3.LEFT, Vector3.DOWN)
	return Basis.IDENTITY


func _build_walls() -> void:
	var stack_gap := Tile3D.TILE_W + 0.004
	for seat in range(4):
		for stack_index in range(WALL_STACKS):
			var offset := (float(stack_index) - 8.0) * stack_gap
			for layer in range(2):
				var tile := _create_tile(-1, false, false, "walls", seat)
				var y := Tile3D.APPROVED_TILE_D * (float(layer) + 0.5)
				tile.position = _rotate_from_south(
					Vector3(offset, y, WALL_RADIUS), seat)
				tile.rotation_degrees.y = [0.0, -90.0, 180.0, 90.0][seat]
				tile.set_meta("stack_index", stack_index)
				tile.set_meta("layer", layer)


func _build_rivers(tile_count: int) -> void:
	for seat in range(4):
		for index in range(tile_count):
			var tile_id := TileId.ALL[(seat * 11 + index * 3) % TileId.ALL.size()]
			var red := index == 4 and tile_id in [TileId.W5, TileId.T5, TileId.S5]
			var tile := _create_tile(tile_id, true, red, "rivers", seat)
			var column := index % 6
			var row := floori(float(index) / 6.0)
			var delta := (float(column) - 2.5) * RIVER_COLUMN_GAP
			var outward := RIVER_INNER + float(row) * RIVER_ROW_GAP
			var yaw: float = [0.0, -90.0, 180.0, 90.0][seat]
			tile.position = _rotate_from_south(Vector3(delta,
				Tile3D.APPROVED_TILE_D * 0.5, outward), seat)
			var riichi := index == 7
			tile.rotation_degrees.y = yaw + (90.0 if riichi else 0.0)
			tile.set_meta("river_index", index)
			tile.set_meta("row", row)
			tile.set_meta("column", column)
			tile.set_meta("riichi", riichi)


func _build_melds() -> void:
	_next_fixture_instance_id = 369000
	var seat_zero_pon := _make_open_meld(Meld.Kind.PON,
		[TileId.T7, TileId.T7, TileId.T7], 2, 1)
	var seat_zero_minkan := _make_open_meld(Meld.Kind.MINKAN,
		[TileId.E, TileId.E, TileId.E, TileId.E], 3, 2)
	var seat_one_chi := _make_open_meld(Meld.Kind.CHI,
		[TileId.W3, TileId.W4, TileId.W5], 0, 1)
	var ankan_tiles := _make_fixture_tiles(
		[TileId.CHUN, TileId.CHUN, TileId.CHUN, TileId.CHUN])
	var seat_two_ankan := Meld.make_ankan(ankan_tiles, 369202)
	var seat_three_added := _make_open_meld(Meld.Kind.ADDED_KAN,
		[TileId.S5, TileId.S5, TileId.S5, TileId.S5], 0, 0)
	var fixtures := [
		{"name": &"pon", "seat": 0, "meld": seat_zero_pon,
			"origin": Vector3(0.30, 0, MELD_RADIUS)},
		{"name": &"minkan", "seat": 0, "meld": seat_zero_minkan,
			"origin": Vector3(0.62, 0, MELD_RADIUS)},
		{"name": &"chi", "seat": 1, "meld": seat_one_chi,
			"origin": _rotate_from_south(
				Vector3(0.30, 0, MELD_RADIUS), 1)},
		{"name": &"ankan", "seat": 2, "meld": seat_two_ankan,
			"origin": _rotate_from_south(
				Vector3(0.30, 0, MELD_RADIUS), 2)},
		{"name": &"added_kan", "seat": 3, "meld": seat_three_added,
			"origin": _rotate_from_south(
				Vector3(0.30, 0, MELD_RADIUS), 3)},
	]
	for fixture in fixtures:
		var fixture_name: StringName = fixture["name"]
		meld_fixtures[fixture_name] = fixture["meld"]
		meld_tiles[fixture_name] = _render_meld(
			fixture_name, int(fixture["seat"]), fixture["meld"] as Meld,
			fixture["origin"] as Vector3)


func _make_open_meld(kind: Meld.Kind, ids: Array,
		from_seat: int, called_index: int) -> Meld:
	var tiles := _make_fixture_tiles(ids)
	var called := tiles[called_index] as Tile
	match kind:
		Meld.Kind.CHI:
			return Meld.make_chi(tiles, from_seat,
				_next_fixture_instance_id + 10, called)
		Meld.Kind.PON:
			return Meld.make_pon(tiles, from_seat,
				_next_fixture_instance_id + 11, called)
		Meld.Kind.MINKAN:
			return Meld.make_minkan(tiles, from_seat,
				_next_fixture_instance_id + 12, called)
		Meld.Kind.ADDED_KAN:
			return Meld.make_added_kan(tiles, from_seat,
				_next_fixture_instance_id + 13, called)
	return null


func _make_fixture_tiles(ids: Array) -> Array[Tile]:
	var tiles: Array[Tile] = []
	for raw_id in ids:
		tiles.append(Tile.new(int(raw_id), false, Tile.NO_OWNER,
			_next_fixture_instance_id))
		_next_fixture_instance_id += 1
	return tiles


func _render_meld(fixture_name: StringName, seat: int, meld: Meld,
		origin: Vector3) -> Array[Tile3D]:
	var slots := MeldLayout.compute(meld, seat)
	var output: Array[Tile3D] = []
	var along: Vector3 = [Vector3.RIGHT, Vector3.BACK,
		Vector3.LEFT, Vector3.FORWARD][seat]
	var base_yaw: float = [0.0, -90.0, 180.0, 90.0][seat]
	var cursor := 0.0
	var stacked_anchor: Tile3D = null
	for slot_index in range(slots.size()):
		var slot := slots[slot_index] as Dictionary
		var rotated := bool(slot["rotated"])
		var stacked := bool(slot["stacked_above"])
		var tile := _create_tile(int(slot["tile_id"]),
			not bool(slot["face_down"]), bool(slot["is_red_dora"]),
			"melds", seat)
		if stacked and stacked_anchor != null:
			tile.position = stacked_anchor.position \
				+ Vector3(0, Tile3D.APPROVED_TILE_D, 0)
			tile.rotation_degrees = stacked_anchor.rotation_degrees
		else:
			var footprint := Tile3D.TILE_H if rotated else Tile3D.TILE_W
			tile.position = origin + along * (cursor + footprint * 0.5)
			tile.position.y = Tile3D.APPROVED_TILE_D * 0.5
			tile.rotation_degrees.y = base_yaw + (90.0 if rotated else 0.0)
			cursor += footprint + TILE_GAP
			if rotated:
				stacked_anchor = tile
		tile.set_meta("fixture_name", fixture_name)
		tile.set_meta("meld_kind", int(meld.kind))
		tile.set_meta("slot_index", slot_index)
		tile.set_meta("rotated", rotated)
		tile.set_meta("face_down", bool(slot["face_down"]))
		tile.set_meta("stacked_above", stacked)
		output.append(tile)
	return output


func _create_tile(tile_id: int, face_up: bool, red: bool,
		category: String, seat: int) -> Tile3D:
	var tile := Tile3D.new()
	tile.set_geometry_depth(Tile3D.APPROVED_TILE_D)
	tile.setup(tile_id, face_up, red)
	tile_root.add_child(tile)
	tile.set_meta("category", category)
	tile.set_meta("seat_id", seat)
	(tile_groups[category][seat] as Array).append(tile)
	return tile


func tile_screen_bounds(tile: Tile3D) -> Rect2:
	var bounds := tile._mesh.get_aabb()
	var first := camera.unproject_position(
		tile._mesh.global_transform * bounds.get_endpoint(0))
	var result := Rect2(first, Vector2.ZERO)
	for index in range(1, 8):
		result = result.expand(camera.unproject_position(
			tile._mesh.global_transform * bounds.get_endpoint(index)))
	return result


func tile_world_y_range(tile: Tile3D) -> Vector2:
	var bounds := tile._mesh.get_aabb()
	var minimum := INF
	var maximum := -INF
	for index in range(8):
		var point := tile._mesh.global_transform * bounds.get_endpoint(index)
		minimum = minf(minimum, point.y)
		maximum = maxf(maximum, point.y)
	return Vector2(minimum, maximum)


func _add_frame_ring(frame_material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = "FrameRing"
	instance.mesh = _build_frame_ring_mesh(frame_material)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	world_root.add_child(instance)
	return instance


func _build_frame_ring_mesh(frame_material: Material) -> ArrayMesh:
	var profile: Array[Vector2] = [
		Vector2(FRAME_INNER_HALF, FRAME_INNER_LIP_Y),
		Vector2(FRAME_INNER_MID_HALF, FRAME_INNER_MID_Y),
		Vector2(FRAME_INNER_SHOULDER_HALF, FRAME_INNER_SHOULDER_Y),
		Vector2(FRAME_CROWN_HALF, FRAME_CROWN_Y),
		Vector2(FRAME_OUTER_SHOULDER_HALF, FRAME_OUTER_SHOULDER_Y),
		Vector2(FRAME_BEVEL_HALF, FRAME_BEVEL_Y),
		Vector2(FRAME_OUTER_HALF, FRAME_SIDE_BOTTOM_Y),
		Vector2(FRAME_OUTER_SHOULDER_HALF + 0.002,
			FRAME_SHELL_BOTTOM_Y),
		Vector2(FRAME_LOWER_INNER_HALF, FRAME_SHELL_BOTTOM_Y),
		Vector2(FRAME_INNER_HALF, FRAME_INNER_BOTTOM_Y),
	]
	var rings: Array[PackedVector2Array] = []
	for point in profile:
		rings.append(_rounded_square_ring(point.x))
	var outline_normals := _rounded_square_normals()
	var profile_normals := _frame_profile_normals(profile)
	var mesh := ArrayMesh.new()
	_commit_frame_surface(mesh, "InnerSlope", [Vector2i(0, 1),
		Vector2i(1, 2)], rings, outline_normals, profile,
		profile_normals, frame_material)
	_commit_frame_surface(mesh, "TopCrown", [Vector2i(2, 3),
		Vector2i(3, 4)], rings, outline_normals, profile,
		profile_normals, frame_material)
	_commit_frame_surface(mesh, "OuterBevel", [Vector2i(4, 5)],
		rings, outline_normals, profile, profile_normals, frame_material)
	_commit_frame_surface(mesh, "SideWall", [Vector2i(5, 6)],
		rings, outline_normals, profile, profile_normals, frame_material)
	_commit_frame_surface(mesh, "LowerShell", [Vector2i(6, 7),
		Vector2i(7, 8), Vector2i(8, 9), Vector2i(9, 0)], rings,
		outline_normals, profile, profile_normals, frame_material)
	return mesh


func _rounded_square_ring(half_extent: float) -> PackedVector2Array:
	var radius := FRAME_INNER_CORNER_RADIUS \
		+ half_extent - FRAME_INNER_HALF
	var corner_centers := [
		Vector2(half_extent - radius, -half_extent + radius),
		Vector2(half_extent - radius, half_extent - radius),
		Vector2(-half_extent + radius, half_extent - radius),
		Vector2(-half_extent + radius, -half_extent + radius),
	]
	var start_angles := [-PI * 0.5, 0.0, PI * 0.5, PI]
	var output := PackedVector2Array()
	for corner_index in range(4):
		for segment_index in range(FRAME_CORNER_SEGMENTS + 1):
			var ratio := float(segment_index) / FRAME_CORNER_SEGMENTS
			var angle: float = start_angles[corner_index] + ratio * PI * 0.5
			output.append(corner_centers[corner_index]
				+ Vector2(cos(angle), sin(angle)) * radius)
	return output


func _rounded_square_normals() -> PackedVector2Array:
	var output := PackedVector2Array()
	var start_angles := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for corner_index in range(4):
		for segment_index in range(FRAME_CORNER_SEGMENTS + 1):
			var ratio := float(segment_index) / FRAME_CORNER_SEGMENTS
			var angle: float = start_angles[corner_index] + ratio * PI * 0.5
			output.append(Vector2(cos(angle), sin(angle)))
	return output


func _frame_profile_normals(profile: Array[Vector2]) -> Array[Vector2]:
	var output: Array[Vector2] = []
	for index in range(profile.size()):
		var previous := profile[(index - 1 + profile.size()) % profile.size()]
		var following := profile[(index + 1) % profile.size()]
		var tangent := following - previous
		output.append(Vector2(-tangent.y, tangent.x).normalized())
	return output


func _commit_frame_surface(mesh: ArrayMesh, surface_name: String,
		profile_pairs: Array[Vector2i], rings: Array[PackedVector2Array],
		outline_normals: PackedVector2Array, profile: Array[Vector2],
		profile_normals: Array[Vector2], frame_material: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(frame_material)
	for pair in profile_pairs:
		_emit_frame_strip(surface, rings[pair.x], rings[pair.y],
			outline_normals, profile[pair.x].y, profile[pair.y].y,
			profile_normals[pair.x], profile_normals[pair.y],
			float(pair.x) / (profile.size() - 1),
			float(pair.y) / (profile.size() - 1))
	surface.commit(mesh)
	mesh.surface_set_name(mesh.get_surface_count() - 1, surface_name)


func _emit_frame_strip(surface: SurfaceTool, first_ring: PackedVector2Array,
		second_ring: PackedVector2Array, outline_normals: PackedVector2Array,
		first_y: float, second_y: float, first_profile_normal: Vector2,
		second_profile_normal: Vector2, first_v: float, second_v: float) -> void:
	var point_count := first_ring.size()
	for index in range(point_count):
		var next := (index + 1) % point_count
		var first_u := float(index) / point_count
		var next_u := float(index + 1) / point_count
		_emit_frame_vertex(surface, first_ring[index], first_y,
			outline_normals[index], first_profile_normal,
			Vector2(first_u, first_v))
		_emit_frame_vertex(surface, second_ring[index], second_y,
			outline_normals[index], second_profile_normal,
			Vector2(first_u, second_v))
		_emit_frame_vertex(surface, second_ring[next], second_y,
			outline_normals[next], second_profile_normal,
			Vector2(next_u, second_v))
		_emit_frame_vertex(surface, first_ring[index], first_y,
			outline_normals[index], first_profile_normal,
			Vector2(first_u, first_v))
		_emit_frame_vertex(surface, second_ring[next], second_y,
			outline_normals[next], second_profile_normal,
			Vector2(next_u, second_v))
		_emit_frame_vertex(surface, first_ring[next], first_y,
			outline_normals[next], first_profile_normal,
			Vector2(next_u, first_v))


func _emit_frame_vertex(surface: SurfaceTool, point: Vector2, height: float,
		outline_normal: Vector2, profile_normal: Vector2, uv: Vector2) -> void:
	surface.set_normal(Vector3(outline_normal.x * profile_normal.x,
		profile_normal.y, outline_normal.y * profile_normal.x).normalized())
	surface.set_uv(uv)
	surface.add_vertex(Vector3(point.x, height, point.y))


func _add_box(box_size: Vector3, box_position: Vector3,
		box_material: Material, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = box_size
	instance.mesh = mesh
	instance.position = box_position
	instance.material_override = box_material
	world_root.add_child(instance)
	return instance


func _felt_material() -> ShaderMaterial:
	if _felt_shader == null:
		_felt_shader = Shader.new()
		_felt_shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 felt_base : source_color = vec4(0.047, 0.286, 0.267, 1.0);
uniform vec4 felt_deep : source_color = vec4(0.020, 0.160, 0.150, 1.0);

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 weave_uv = UV * vec2(180.0, 160.0);
	float warp = 0.5 + 0.5 * sin(weave_uv.x * 6.28318 + sin(weave_uv.y * 0.17));
	float weft = 0.5 + 0.5 * sin(weave_uv.y * 6.28318 + 1.5708);
	float fiber = mix(warp, weft, 0.5) - 0.5;
	float mote = hash21(floor(weave_uv * 0.38)) - 0.5;
	float edge = 1.0 - smoothstep(0.10, 0.72, length(UV - vec2(0.5)));
	vec3 color = mix(felt_deep.rgb, felt_base.rgb, 0.74 + edge * 0.20);
	color *= 1.0 + fiber * 0.075 + mote * 0.014;
	ALBEDO = color;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
	SPECULAR = 0.18;
}
"""
	var shader_material := ShaderMaterial.new()
	shader_material.shader = _felt_shader
	shader_material.set_shader_parameter("felt_base", Color("0c4944"))
	shader_material.set_shader_parameter("felt_deep", Color("052a28"))
	return shader_material


func _wood_material() -> ShaderMaterial:
	if _wood_shader == null:
		_wood_shader = Shader.new()
		_wood_shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 wood_base : source_color = vec4(0.306, 0.114, 0.067, 1.0);
uniform vec4 wood_dark : source_color = vec4(0.071, 0.020, 0.012, 1.0);

varying vec3 wood_position;

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	local = local * local * (3.0 - 2.0 * local);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), local.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), local.x),
		local.y);
}

void vertex() {
	wood_position = VERTEX;
}

void fragment() {
	vec2 grain_position = wood_position.xz;
	float bend = value_noise(grain_position * 5.0) * 4.5;
	float fine = value_noise(grain_position * vec2(72.0, 16.0)
		+ vec2(bend, -bend));
	float streak = value_noise(grain_position * vec2(145.0, 31.0)
		+ vec2(-bend, bend));
	float broad = value_noise(grain_position * 7.0 + vec2(2.1, 5.7));
	float height_light = smoothstep(-0.092, 0.035, wood_position.y);
	vec3 color = mix(wood_dark.rgb, wood_base.rgb,
		0.52 + broad * 0.30 + height_light * 0.12);
	color *= 0.82 + fine * 0.22 + streak * 0.07;
	color += vec3(0.045, 0.024, 0.015) * height_light;
	ALBEDO = color;
	ROUGHNESS = 0.53;
	METALLIC = 0.05;
	SPECULAR = 0.30;
}
"""
	var shader_material := ShaderMaterial.new()
	shader_material.shader = _wood_shader
	shader_material.set_shader_parameter("wood_base", Color("4e1d11"))
	shader_material.set_shader_parameter("wood_dark", Color("120503"))
	return shader_material


func _material(color: Color, roughness: float,
		metallic: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result
