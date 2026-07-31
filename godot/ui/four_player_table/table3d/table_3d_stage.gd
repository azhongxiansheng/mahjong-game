extends RefCounted

## #405：由 #369 视觉合同抽出的 production 3D 桌体。
## 只负责桌体、中央盘、光照与相机；牌局状态仍由 PlayableTable 投影。

const TABLE_SIZE := Vector2(2.40, 2.40)
const TABLE_TOP_Y := 0.001
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
const CAMERA_VIEWS := [&"main", &"top", &"south", &"east", &"north", &"west"]

static var _felt_shader: Shader = null
static var _wood_shader: Shader = null


static func build(world: Node3D) -> Dictionary:
	_build_environment(world)
	_add_box(world, Vector3(TABLE_SIZE.x, 0.07, TABLE_SIZE.y),
		Vector3(0, TABLE_TOP_Y - 0.035, 0), _felt_material(), "Felt")
	var frame := MeshInstance3D.new()
	frame.name = "FrameRing"
	frame.mesh = _build_frame_ring_mesh(_wood_material())
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	world.add_child(frame)
	_build_center(world)
	_build_zone_lines(world)
	_build_lights(world)
	var camera := _build_camera(world)
	return {"camera": camera, "frame": frame}


## 透明混合模式只共享已校准相机与灯，不建立桌体或中央盘 mesh。
static func build_tile_overlay(world: Node3D) -> Dictionary:
	_build_lights(world)
	return {"camera": _build_camera(world)}


static func _build_camera(world: Node3D) -> Camera3D:
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.near = 0.04
	camera.current = true
	world.add_child(camera)
	return camera


static func set_camera_view(camera: Camera3D, view_name: StringName) -> bool:
	if camera == null or not CAMERA_VIEWS.has(view_name):
		return false
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 11.15
	if view_name == &"top":
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 2.72
		camera.look_at_from_position(Vector3(0, 4.0, 0),
			Vector3.ZERO, Vector3.FORWARD)
		return true
	var seat := {&"east": 1, &"north": 2, &"west": 3}.get(view_name, 0) as int
	# 对齐生产 2D 的 18° 平面投影视觉：远相机长焦形成弱收束，
	# 中等俯角保留扁平桌面比例，并让四席手牌同时进入 HUD 安全区。
	var position := rotate_from_south(Vector3(0, 4.893, 6.098), seat)
	camera.look_at_from_position(position,
		rotate_from_south(Vector3(0, 0.0, 0.153), seat), Vector3.UP)
	return true


static func rotate_from_south(point: Vector3, seat: int) -> Vector3:
	match seat:
		1: return Vector3(point.z, point.y, -point.x)
		2: return Vector3(-point.x, point.y, -point.z)
		3: return Vector3(-point.z, point.y, point.x)
	return point


static func _build_environment(world: Node3D) -> void:
	var node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("061315")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("cedbd4")
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = false
	node.environment = environment
	world.add_child(node)


static func _build_lights(world: Node3D) -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-54, -32, 0)
	key.light_color = Color("fff0cf")
	key.light_energy = 2.0
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 6.0
	world.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.0, 2.1, 1.8)
	fill.light_color = Color("a8d9d2")
	fill.light_energy = 1.15
	fill.omni_range = 5.5
	world.add_child(fill)


static func _build_center(world: Node3D) -> void:
	var center := _material(Color("0b202d"), 0.74, 0.08)
	_add_box(world, Vector3(0.54, 0.036, 0.54),
		Vector3(0, TABLE_TOP_Y + 0.018, 0), center, "CenterPlate")
	var metal := _material(Color("8b754b"), 0.48, 0.38)
	for item in [
		[Vector3(0.56, 0.006, 0.007), Vector3(0, TABLE_TOP_Y + 0.039, -0.275), "CenterMetalNorth"],
		[Vector3(0.56, 0.006, 0.007), Vector3(0, TABLE_TOP_Y + 0.039, 0.275), "CenterMetalSouth"],
		[Vector3(0.007, 0.006, 0.55), Vector3(-0.275, TABLE_TOP_Y + 0.039, 0), "CenterMetalWest"],
		[Vector3(0.007, 0.006, 0.55), Vector3(0.275, TABLE_TOP_Y + 0.039, 0), "CenterMetalEast"],
	]:
		_add_box(world, item[0], item[1], metal, item[2])
	_add_box(world, Vector3(0.12, 0.012, 0.018),
		Vector3(0, TABLE_TOP_Y + 0.048, 0.16), metal, "TurnMarker")


static func _build_zone_lines(world: Node3D) -> void:
	var root := Node3D.new()
	root.name = "ZoneLines"
	world.add_child(root)
	var material := _material(Color("364a43"), 0.84, 0.12)
	for seat in range(4):
		var line := MeshInstance3D.new()
		line.name = "Seat%d" % seat
		line.mesh = _zone_line_mesh(material)
		line.position.y = TABLE_TOP_Y
		line.rotation_degrees.y = -90.0 * seat
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(line)


static func _zone_line_mesh(material: Material) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	var inner_z := 0.292
	var outer_z := 0.602
	var inner_half := 0.274
	var outer_half := 0.408
	var width := 0.0024
	_emit_strip(surface, Vector2(-inner_half, inner_z),
		Vector2(-outer_half, outer_z), width)
	_emit_strip(surface, Vector2(inner_half, inner_z),
		Vector2(outer_half, outer_z), width)
	var mesh := ArrayMesh.new()
	surface.commit(mesh)
	return mesh


static func _emit_strip(surface: SurfaceTool, start: Vector2,
		finish: Vector2, width: float) -> void:
	var side := (finish - start).normalized().orthogonal() * width * 0.5
	var points := [start + side, finish + side, finish - side,
		start + side, finish - side, start - side]
	for point in points:
		surface.set_normal(Vector3.UP)
		surface.add_vertex(Vector3(point.x, 0.0008, point.y))


static func _build_frame_ring_mesh(material: Material) -> ArrayMesh:
	# #369 已验收的十点闭合截面：内斜面、双层顶冠、外倒角、
	# 下沉侧壁与闭合底壳共用同一组连续环和实体坐标木纹。
	var profile: Array[Vector2] = [
		Vector2(FRAME_INNER_HALF, FRAME_INNER_LIP_Y),
		Vector2(FRAME_INNER_MID_HALF, FRAME_INNER_MID_Y),
		Vector2(FRAME_INNER_SHOULDER_HALF, FRAME_INNER_SHOULDER_Y),
		Vector2(FRAME_CROWN_HALF, FRAME_CROWN_Y),
		Vector2(FRAME_OUTER_SHOULDER_HALF, FRAME_OUTER_SHOULDER_Y),
		Vector2(FRAME_BEVEL_HALF, FRAME_BEVEL_Y),
		Vector2(FRAME_OUTER_HALF, FRAME_SIDE_BOTTOM_Y),
		Vector2(FRAME_OUTER_SHOULDER_HALF + 0.002, FRAME_SHELL_BOTTOM_Y),
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
		profile_normals, material)
	_commit_frame_surface(mesh, "TopCrown", [Vector2i(2, 3),
		Vector2i(3, 4)], rings, outline_normals, profile,
		profile_normals, material)
	_commit_frame_surface(mesh, "OuterBevel", [Vector2i(4, 5)],
		rings, outline_normals, profile, profile_normals, material)
	_commit_frame_surface(mesh, "SideWall", [Vector2i(5, 6)],
		rings, outline_normals, profile, profile_normals, material)
	_commit_frame_surface(mesh, "LowerShell", [Vector2i(6, 7),
		Vector2i(7, 8), Vector2i(8, 9), Vector2i(9, 0)], rings,
		outline_normals, profile, profile_normals, material)
	return mesh


static func _rounded_square_ring(half_extent: float) -> PackedVector2Array:
	var radius := FRAME_INNER_CORNER_RADIUS + half_extent - FRAME_INNER_HALF
	var centers := [
		Vector2(half_extent - radius, -half_extent + radius),
		Vector2(half_extent - radius, half_extent - radius),
		Vector2(-half_extent + radius, half_extent - radius),
		Vector2(-half_extent + radius, -half_extent + radius),
	]
	var starts := [-PI * 0.5, 0.0, PI * 0.5, PI]
	var output := PackedVector2Array()
	for corner in range(4):
		for segment in range(FRAME_CORNER_SEGMENTS + 1):
			var angle: float = starts[corner] + PI * 0.5 \
				* float(segment) / FRAME_CORNER_SEGMENTS
			output.append(centers[corner] + Vector2(cos(angle), sin(angle)) * radius)
	return output


static func _rounded_square_normals() -> PackedVector2Array:
	var output := PackedVector2Array()
	var starts := [-PI * 0.5, 0.0, PI * 0.5, PI]
	for corner in range(4):
		for segment in range(FRAME_CORNER_SEGMENTS + 1):
			var angle: float = starts[corner] + PI * 0.5 \
				* float(segment) / FRAME_CORNER_SEGMENTS
			output.append(Vector2(cos(angle), sin(angle)))
	return output


static func _frame_profile_normals(profile: Array[Vector2]) -> Array[Vector2]:
	var output: Array[Vector2] = []
	for index in range(profile.size()):
		var previous := profile[(index - 1 + profile.size()) % profile.size()]
		var following := profile[(index + 1) % profile.size()]
		var tangent := following - previous
		output.append(Vector2(-tangent.y, tangent.x).normalized())
	return output


static func _commit_frame_surface(mesh: ArrayMesh, surface_name: String,
		profile_pairs: Array[Vector2i], rings: Array[PackedVector2Array],
		outline_normals: PackedVector2Array, profile: Array[Vector2],
		profile_normals: Array[Vector2], material: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(material)
	for pair in profile_pairs:
		_emit_frame_strip(surface, rings[pair.x], rings[pair.y],
			outline_normals, profile[pair.x].y, profile[pair.y].y,
			profile_normals[pair.x], profile_normals[pair.y],
			float(pair.x) / (profile.size() - 1),
			float(pair.y) / (profile.size() - 1))
	surface.commit(mesh)
	mesh.surface_set_name(mesh.get_surface_count() - 1, surface_name)


static func _emit_frame_strip(surface: SurfaceTool,
		first_ring: PackedVector2Array, second_ring: PackedVector2Array,
		outline_normals: PackedVector2Array, first_y: float, second_y: float,
		first_profile_normal: Vector2, second_profile_normal: Vector2,
		first_v: float, second_v: float) -> void:
	for index in range(first_ring.size()):
		var next := (index + 1) % first_ring.size()
		var first_u := float(index) / first_ring.size()
		var next_u := float(index + 1) / first_ring.size()
		_emit_frame_vertex(surface, first_ring[index], first_y,
			outline_normals[index], first_profile_normal, Vector2(first_u, first_v))
		_emit_frame_vertex(surface, second_ring[index], second_y,
			outline_normals[index], second_profile_normal, Vector2(first_u, second_v))
		_emit_frame_vertex(surface, second_ring[next], second_y,
			outline_normals[next], second_profile_normal, Vector2(next_u, second_v))
		_emit_frame_vertex(surface, first_ring[index], first_y,
			outline_normals[index], first_profile_normal, Vector2(first_u, first_v))
		_emit_frame_vertex(surface, second_ring[next], second_y,
			outline_normals[next], second_profile_normal, Vector2(next_u, second_v))
		_emit_frame_vertex(surface, first_ring[next], first_y,
			outline_normals[next], first_profile_normal, Vector2(next_u, first_v))


static func _emit_frame_vertex(surface: SurfaceTool, point: Vector2,
		height: float, outline_normal: Vector2, profile_normal: Vector2,
		uv: Vector2) -> void:
	surface.set_normal(Vector3(outline_normal.x * profile_normal.x,
		profile_normal.y, outline_normal.y * profile_normal.x).normalized())
	surface.set_uv(uv)
	surface.add_vertex(Vector3(point.x, height, point.y))


static func _add_box(world: Node3D, size: Vector3, position: Vector3,
		material: Material, node_name: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	world.add_child(instance)
	return instance


static func _material(color: Color, roughness: float,
		metallic: float) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = roughness
	result.metallic = metallic
	return result


static func _felt_material() -> ShaderMaterial:
	if _felt_shader == null:
		_felt_shader = Shader.new()
		_felt_shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 felt_base : source_color = vec4(0.047, 0.286, 0.267, 1.0);
uniform vec4 felt_deep : source_color = vec4(0.020, 0.160, 0.150, 1.0);
void fragment() {
	vec2 p = UV * vec2(180.0, 160.0);
	float fiber = (sin((p.x + p.y) * 6.28318) + sin((p.x - p.y) * 6.1)) * 0.018;
	float edge = 1.0 - smoothstep(0.10, 0.72, length(UV - vec2(0.5)));
	ALBEDO = mix(felt_deep.rgb, felt_base.rgb, 0.74 + edge * 0.20) * (1.0 + fiber);
	ROUGHNESS = 0.95; METALLIC = 0.0; SPECULAR = 0.18;
}
"""
	var result := ShaderMaterial.new()
	result.shader = _felt_shader
	return result


static func _wood_material() -> ShaderMaterial:
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
	ROUGHNESS = 0.53; METALLIC = 0.05; SPECULAR = 0.30;
}
"""
	var result := ShaderMaterial.new()
	result.shader = _wood_shader
	result.set_shader_parameter("wood_base", Color("4e1d11"))
	result.set_shader_parameter("wood_dark", Color("120503"))
	return result
