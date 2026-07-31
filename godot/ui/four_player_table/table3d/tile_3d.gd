class_name Tile3D extends Area3D

## 可复用立体麻将牌。
##
## X=宽、Y=厚度、Z=牌高。既有调用方默认继续使用 34mm 厚度；#369
## 可显式选择用户确认的 56mm 日麻比例。所有同尺寸实例共享纯几何 mesh，
## 牌面、牌背与牌胚外观只通过实例 surface override 绑定。

const TILE_W: float = 0.072
const TILE_H: float = 0.098
const TILE_D: float = 0.034
const APPROVED_TILE_D: float = 0.056

const CORNER_RADIUS: float = 0.0072
const BEVEL: float = 0.0032
const EDGE_LINE: float = 0.00065
const CORNER_SEGMENTS: int = 5
const BEVEL_SEGMENTS: int = 4
const BACK_LAYER_RATIO: float = 0.5
const DEFAULT_SKIN_PATH := \
	"res://ui/four_player_table/table3d/skins/qinglan_weave.tres"

# E2-02 / #232：点击发 tile_instance_id；hover 仍发 tile_id（同名联动）
signal tile_clicked(tile_instance_id: int)
signal tile_hover(tile_id: int, entered: bool)

static var _shared_meshes: Dictionary = {}
static var _face_textures: Dictionary = {}
static var _face_materials: Dictionary = {}
static var _back_materials: Dictionary = {}
static var _overlay_materials: Dictionary = {}
static var _default_skin: Resource = null

@export var tile_skin: Resource = null

var tile_id: int = -1
var is_red_dora: bool = false
var face_up: bool = true
var clickable: bool = false
# entity identity；setup() 纯展示清空；setup_entity 注入
var tile_instance_id: int = Tile.INVALID_INSTANCE_ID
var _mesh: MeshInstance3D = null
var _collision: CollisionShape3D = null
var _geometry_depth: float = TILE_D
var _base_y: float = 0.0
var _lifted: bool = false
var _is_hovered: bool = false
var _is_dora: bool = false
var _is_hover_match: bool = false
var _is_latest_discard: bool = false
var _is_win_tile: bool = false
var _is_selected: bool = false
var _is_dim: bool = false


func _ready() -> void:
	_ensure_mesh()
	input_ray_pickable = true
	collision_layer = 1
	collision_mask = 0
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not mouse_exited.is_connected(_on_mouse_exited):
		mouse_exited.connect(_on_mouse_exited)


func _ensure_mesh() -> void:
	if _mesh != null:
		return
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_mesh.mesh = _shared_mesh_for_depth(_geometry_depth)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	add_child(_mesh)
	_collision = CollisionShape3D.new()
	_collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(TILE_W, _geometry_depth, TILE_H)
	_collision.shape = shape
	add_child(_collision)


func set_geometry_depth(depth: float) -> void:
	var normalized_depth := depth if depth > 0.0 else TILE_D
	if is_equal_approx(_geometry_depth, normalized_depth) and _mesh != null:
		return
	_geometry_depth = normalized_depth
	_ensure_mesh()
	_mesh.mesh = _shared_mesh_for_depth(_geometry_depth)
	var shape := _collision.shape as BoxShape3D
	if shape != null:
		shape.size = Vector3(TILE_W, _geometry_depth, TILE_H)
	_apply_materials()


func get_geometry_depth() -> float:
	return _geometry_depth


func set_tile_skin(skin: Resource) -> void:
	tile_skin = skin if skin != null else _load_default_skin()
	_apply_materials()


func get_tile_skin() -> Resource:
	if tile_skin == null:
		tile_skin = _load_default_skin()
	return tile_skin


static func _shared_mesh_for_depth(depth: float) -> ArrayMesh:
	var key := roundi(depth * 1000000.0)
	if not _shared_meshes.has(key):
		_shared_meshes[key] = _build_box_mesh(depth)
	return _shared_meshes[key] as ArrayMesh


# 6 个语义 surface：0=牌面、1=牌背、2=嵌入边、3=正面倒角、
# 4=象牙半层侧壁、5=牌背倒角与着色半层。
static func _build_box_mesh(depth: float = TILE_D) -> ArrayMesh:
	return _build_beveled_mesh(depth)


# 纯展示入口：清空 entity identity
func setup(p_tile_id: int, p_face_up: bool = true, p_red: bool = false) -> void:
	tile_id = p_tile_id
	face_up = p_face_up
	is_red_dora = p_red
	tile_instance_id = Tile.INVALID_INSTANCE_ID
	_ensure_mesh()
	_apply_materials()


# 手牌等可动作牌：注入 instance_id
func setup_entity(p_tile_id: int, p_face_up: bool, p_red: bool,
		p_instance_id: int) -> void:
	tile_id = p_tile_id
	face_up = p_face_up
	is_red_dora = p_red
	tile_instance_id = p_instance_id
	_ensure_mesh()
	_apply_materials()


## 只更新牌面身份，不改变 face_up、几何、皮肤或动作 instance_id。
## setup() 继续保留“纯展示并清空 identity”的既有语义。
func set_tile_visual(p_tile_id: int, p_red: bool = false) -> void:
	tile_id = p_tile_id
	is_red_dora = p_red
	_apply_materials()


func set_face_up(p_face_up: bool) -> void:
	face_up = p_face_up
	_apply_materials()


func set_clickable(b: bool) -> void:
	clickable = b
	input_ray_pickable = true
	if not clickable and _is_hovered:
		_is_hovered = false
		_refresh_lifted()


# 兼容既有调用：旧的 lifted 即选中态；鼠标 hover 另由 _is_hovered 记录，
# 两者合并后再驱动实际位移，避免 hover 退出清掉仍然有效的选中态。
func set_lifted(b: bool) -> void:
	set_selected(b)


func _set_lifted_visual(b: bool) -> void:
	if _lifted == b:
		return
	_lifted = b
	var target_y: float = _base_y + (0.018 if b else 0.0)
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_property(self, "position:y", target_y, 0.08)
	else:
		position.y = target_y


func _refresh_lifted() -> void:
	_set_lifted_visual(_is_selected or _is_hovered)


func set_base_position(pos: Vector3) -> void:
	_base_y = pos.y
	position = pos
	if _lifted:
		position.y = _base_y + 0.018


func set_dim(b: bool) -> void:
	if _is_dim == b:
		return
	_is_dim = b
	_ensure_mesh()
	# dim 只使用 GeometryInstance3D 的透明度，不修改任一牌面材质的 RGB。
	_mesh.transparency = 0.4 if b else 0.0


func is_dim() -> bool:
	return _is_dim


func set_dora(b: bool) -> void:
	if _is_dora == b:
		return
	_is_dora = b
	_refresh_material_overlay()


func set_hover_match(b: bool) -> void:
	if _is_hover_match == b:
		return
	_is_hover_match = b
	_refresh_material_overlay()


func set_latest_discard(b: bool) -> void:
	if _is_latest_discard == b:
		return
	_is_latest_discard = b
	_refresh_material_overlay()


func set_win_tile(b: bool) -> void:
	if _is_win_tile == b:
		return
	_is_win_tile = b
	_refresh_material_overlay()


func set_selected(b: bool) -> void:
	if _is_selected == b:
		return
	_is_selected = b
	_refresh_material_overlay()
	_refresh_lifted()


func visual_state() -> Dictionary:
	return {
		"dora": _is_dora,
		"hover_match": _is_hover_match,
		"latest_discard": _is_latest_discard,
		"win_tile": _is_win_tile,
		"selected": _is_selected,
		"dim": _is_dim,
		"overlay": String(_active_overlay()),
	}


func _active_overlay() -> StringName:
	if _is_win_tile:
		return &"win"
	if _is_latest_discard:
		return &"latest"
	if _is_selected:
		return &"selected"
	if _is_hover_match:
		return &"hover_match"
	if _is_dora:
		return &"dora"
	return &""


func _refresh_material_overlay() -> void:
	_ensure_mesh()
	var overlay := _active_overlay()
	_mesh.material_overlay = null if overlay == &"" \
		else _overlay_material_for(overlay)


static func _overlay_material_for(state: StringName) -> StandardMaterial3D:
	if _overlay_materials.has(state):
		return _overlay_materials[state] as StandardMaterial3D
	var colors := {
		&"dora": Color(1.0, 0.78, 0.18, 0.24),
		&"hover_match": Color(0.24, 0.55, 0.86, 0.30),
		&"selected": Color(0.96, 0.68, 0.16, 0.36),
		&"latest": Color(1.0, 0.34, 0.16, 0.40),
		&"win": Color(0.95, 0.20, 0.48, 0.46),
	}
	var material := StandardMaterial3D.new()
	material.albedo_color = colors.get(state, Color.TRANSPARENT) as Color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_overlay_materials[state] = material
	return material


# 平滑飞到目标位姿（切牌入河 / 摸牌落下）
func animate_to(pos: Vector3, rot_deg: Vector3,
		duration: float = 0.22) -> void:
	_base_y = pos.y
	if not is_inside_tree():
		position = pos
		rotation_degrees = rot_deg
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position", pos, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation_degrees", rot_deg, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func animate_draw_drop(from_y_extra: float = 0.12,
		duration: float = 0.2) -> void:
	var target := position
	position.y = target.y + from_y_extra
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_property(self, "position:y", target.y, duration) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _apply_materials() -> void:
	_ensure_mesh()
	var skin := get_tile_skin()
	var face_material := _face_material_for(skin)
	var back_material := _back_material_for(skin)
	var edge_material := _skin_material(skin, &"edge_material",
		Color(0.99, 0.985, 0.975), 0.38)
	var bevel_material := _skin_material(skin, &"bevel_material",
		Color(0.594, 0.591, 0.585), 0.38)
	var side_material := _skin_material(skin, &"side_material",
		Color(0.693, 0.6895, 0.6825), 0.38)
	var back_shell_material := _skin_material(skin,
		&"back_shell_material", Color(0.07, 0.32, 0.285), 0.58)
	if face_up:
		_mesh.set_surface_override_material(0, face_material)
		_mesh.set_surface_override_material(1, back_material)
		_mesh.set_surface_override_material(2, edge_material)
		_mesh.set_surface_override_material(3, bevel_material)
		_mesh.set_surface_override_material(4, side_material)
		_mesh.set_surface_override_material(5, back_shell_material)
	else:
		# 与物理翻牌一致：牌背、牌背倒角和着色半层移到可见顶面；
		# 原牌面和象牙半层则落到底面。
		_mesh.set_surface_override_material(0, back_material)
		_mesh.set_surface_override_material(1, face_material)
		_mesh.set_surface_override_material(2, back_shell_material)
		_mesh.set_surface_override_material(3, back_shell_material)
		_mesh.set_surface_override_material(4, back_shell_material)
		_mesh.set_surface_override_material(5, side_material)


func _face_material_for(skin: Resource) -> StandardMaterial3D:
	var atlas_key := ""
	if tile_id >= 0:
		atlas_key = CardTileBack.tile_id_to_atlas_key(tile_id, is_red_dora)
	var final_override := _face_override(skin, atlas_key)
	var source := final_override \
		if final_override != null else _get_tex(atlas_key)
	var source_id := source.get_instance_id() if source != null else 0
	var skin_id := skin.get_instance_id() if skin != null else 0
	var cache_key := "%d:%s:%d" % [skin_id, atlas_key, source_id]
	if _face_materials.has(cache_key):
		return _face_materials[cache_key] as StandardMaterial3D
	var material := _duplicate_skin_material(skin,
		&"face_material_template", Color.WHITE, 0.38)
	if source != null:
		# skin.face_textures 定义的是最终不透明牌面；仓库既有 2D 牌图
		# 才需要去除旧牌胚并烘入当前皮肤的牌面底色。
		material.albedo_texture = final_override if final_override != null \
			else _face_texture_for(skin, atlas_key, source)
		material.albedo_color = Color.WHITE
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	else:
		material.albedo_texture = null
		material.albedo_color = _face_background_color(skin)
	_face_materials[cache_key] = material
	return material


func _back_material_for(skin: Resource) -> StandardMaterial3D:
	var skin_id := skin.get_instance_id() if skin != null else 0
	if _back_materials.has(skin_id):
		return _back_materials[skin_id] as StandardMaterial3D
	var material := _duplicate_skin_material(skin,
		&"back_material_template", Color(0.07, 0.32, 0.285), 0.58)
	if material.albedo_texture == null:
		var base_color := material.albedo_color
		var source_back := _get_tex("back")
		material.albedo_texture = _make_weave_back_texture(
			base_color, source_back)
		material.albedo_color = Color.WHITE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_back_materials[skin_id] = material
	return material


func _face_override(skin: Resource, atlas_key: String) -> Texture2D:
	if atlas_key == "":
		return null
	if skin != null:
		var override_value: Variant = skin.get("face_textures")
		if override_value is Dictionary:
			var overrides := override_value as Dictionary
			if overrides.has(atlas_key) and overrides[atlas_key] is Texture2D:
				return overrides[atlas_key] as Texture2D
			var named_key := StringName(atlas_key)
			if overrides.has(named_key) and overrides[named_key] is Texture2D:
				return overrides[named_key] as Texture2D
	return null


func _face_texture_for(skin: Resource, atlas_key: String,
		source: Texture2D) -> Texture2D:
	var skin_id := skin.get_instance_id() if skin != null else 0
	var cache_key := "%d:%s:%d" % [
		skin_id, atlas_key, source.get_instance_id()]
	if not _face_textures.has(cache_key):
		_face_textures[cache_key] = _make_face_texture(
			source, _face_background_color(skin))
	return _face_textures[cache_key] as Texture2D


static func _make_face_texture(source: Texture2D,
		background: Color) -> Texture2D:
	var source_image := source.get_image()
	if source_image == null or source_image.is_empty():
		return source
	source_image.convert(Image.FORMAT_RGBA8)
	var image := Image.create(source_image.get_width(),
		source_image.get_height(), false, Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var source_color := source_image.get_pixel(x, y)
			var maximum := maxf(source_color.r,
				maxf(source_color.g, source_color.b))
			var minimum := minf(source_color.r,
				minf(source_color.g, source_color.b))
			var chroma_mask := smoothstep(0.055, 0.18,
				maximum - minimum)
			var dark_mask := 1.0 - smoothstep(0.30, 0.61,
				source_color.get_luminance())
			var ink_mask := maxf(chroma_mask, dark_mask) * source_color.a
			var result := background.lerp(Color(source_color.r,
				source_color.g, source_color.b, 1.0), ink_mask)
			result.a = 1.0
			image.set_pixel(x, y, result)
	return ImageTexture.create_from_image(image)


static func _make_weave_back_texture(base_color: Color,
		source: Texture2D) -> Texture2D:
	var width := 272
	var height := 389
	if source != null:
		var source_image := source.get_image()
		if source_image != null and not source_image.is_empty():
			width = source_image.get_width()
			height = source_image.get_height()
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var image_size := Vector2(width, height)
	for y in range(height):
		for x in range(width):
			var uv := Vector2(x, y) / image_size
			var weave := (sin((uv.x + uv.y) * 150.0)
				+ sin((uv.x - uv.y) * 142.0)) * 0.006
			var tone := 1.0 + weave
			image.set_pixel(x, y, Color(base_color.r * tone,
				base_color.g * tone, base_color.b * tone, 1.0))
	return ImageTexture.create_from_image(image)


func _face_background_color(skin: Resource) -> Color:
	if skin != null:
		var value: Variant = skin.get("face_background_color")
		if value is Color:
			return value as Color
	return Color(0.99, 0.985, 0.975)


func _skin_material(skin: Resource, property_name: StringName,
		fallback_color: Color, roughness: float) -> StandardMaterial3D:
	if skin != null:
		var value: Variant = skin.get(property_name)
		if value is StandardMaterial3D:
			return value as StandardMaterial3D
	return _fallback_material(fallback_color, roughness)


func _duplicate_skin_material(skin: Resource, property_name: StringName,
		fallback_color: Color, roughness: float) -> StandardMaterial3D:
	var template := _skin_material(
		skin, property_name, fallback_color, roughness)
	return template.duplicate() as StandardMaterial3D


static func _fallback_material(color: Color,
		roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func _load_default_skin() -> Resource:
	if _default_skin == null and ResourceLoader.exists(DEFAULT_SKIN_PATH):
		_default_skin = load(DEFAULT_SKIN_PATH) as Resource
	return _default_skin


func _get_tex(key: String) -> Texture2D:
	if key == "":
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var extractor: Node = tree.root.get_node_or_null("TextureExtractor")
	if extractor == null or not extractor.has_method("get_tile_texture"):
		return null
	return extractor.get_tile_texture(key)


static func _build_beveled_mesh(depth: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var half_w := TILE_W * 0.5
	var half_h := TILE_H * 0.5
	var half_d := depth * 0.5
	var top_half_w := half_w - BEVEL
	var top_half_h := half_h - BEVEL
	var top_radius := CORNER_RADIUS - BEVEL
	var face_half_w := top_half_w - EDGE_LINE
	var face_half_h := top_half_h - EDGE_LINE
	var face_radius := maxf(top_radius - EDGE_LINE, 0.0008)
	var full_ring := _rounded_ring(half_w, half_h, CORNER_RADIUS)
	var top_ring := _rounded_ring(top_half_w, top_half_h, top_radius)
	var face_ring := _rounded_ring(face_half_w, face_half_h, face_radius)

	var face_surface := SurfaceTool.new()
	face_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_face(face_surface, face_ring, half_d, Vector3.UP, false,
		face_half_w, face_half_h)
	face_surface.commit(mesh)

	var back_surface := SurfaceTool.new()
	back_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_face(back_surface, face_ring, -half_d, Vector3.DOWN, true,
		face_half_w, face_half_h)
	back_surface.commit(mesh)

	var edge_surface := SurfaceTool.new()
	edge_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_flat_ring(edge_surface, top_ring, face_ring, half_d, Vector3.UP)
	edge_surface.commit(mesh)

	var bevel_surface := SurfaceTool.new()
	bevel_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_curved_bevel(bevel_surface, depth, true)
	bevel_surface.commit(mesh)

	var back_layer_y := -half_d + depth * BACK_LAYER_RATIO
	var side_surface := SurfaceTool.new()
	side_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_side(side_surface, full_ring, half_d - BEVEL, back_layer_y)
	side_surface.commit(mesh)

	var back_shell_surface := SurfaceTool.new()
	back_shell_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_flat_ring(back_shell_surface, top_ring, face_ring,
		-half_d, Vector3.DOWN)
	_emit_curved_bevel(back_shell_surface, depth, false)
	_emit_side(back_shell_surface, full_ring,
		back_layer_y, -half_d + BEVEL)
	back_shell_surface.commit(mesh)
	return mesh


static func _rounded_ring(half_w: float, half_h: float,
		radius: float) -> Array[Vector2]:
	var ring: Array[Vector2] = []
	var centers := [
		Vector2(half_w - radius, -half_h + radius),
		Vector2(half_w - radius, half_h - radius),
		Vector2(-half_w + radius, half_h - radius),
		Vector2(-half_w + radius, -half_h + radius),
	]
	var starts := [-90.0, 0.0, 90.0, 180.0]
	for corner in range(4):
		for step in range(CORNER_SEGMENTS + 1):
			var angle := deg_to_rad(starts[corner]
				+ 90.0 * float(step) / float(CORNER_SEGMENTS))
			ring.append(centers[corner]
				+ Vector2(cos(angle), sin(angle)) * radius)
	return ring


static func _emit_face(surface: SurfaceTool, ring: Array[Vector2],
		y: float, normal: Vector3, reverse: bool,
		face_half_w: float, face_half_h: float) -> void:
	for index in range(ring.size()):
		var next := (index + 1) % ring.size()
		var points := [Vector2.ZERO, ring[index], ring[next]]
		if reverse:
			points = [Vector2.ZERO, ring[next], ring[index]]
		for point in points:
			_emit_vertex(surface, Vector3(point.x, y, point.y), normal,
				Vector2(point.x / (face_half_w * 2.0) + 0.5,
					point.y / (face_half_h * 2.0) + 0.5))


static func _emit_flat_ring(surface: SurfaceTool, outer: Array[Vector2],
		inner: Array[Vector2], y: float, normal: Vector3) -> void:
	for index in range(outer.size()):
		var next := (index + 1) % outer.size()
		var outer_a := Vector3(outer[index].x, y, outer[index].y)
		var outer_b := Vector3(outer[next].x, y, outer[next].y)
		var inner_b := Vector3(inner[next].x, y, inner[next].y)
		var inner_a := Vector3(inner[index].x, y, inner[index].y)
		if normal.y < 0.0:
			_emit_quad(surface, outer_a, inner_a, inner_b, outer_b,
				normal, normal, normal, normal)
		else:
			_emit_quad(surface, outer_a, outer_b, inner_b, inner_a,
				normal, normal, normal, normal)


static func _emit_curved_bevel(surface: SurfaceTool,
		depth: float, top: bool) -> void:
	var half_w := TILE_W * 0.5
	var half_h := TILE_H * 0.5
	var half_d := depth * 0.5
	var cap_normal := Vector3.UP if top else Vector3.DOWN
	for segment in range(BEVEL_SEGMENTS):
		var ratio_a := float(segment) / float(BEVEL_SEGMENTS)
		var ratio_b := float(segment + 1) / float(BEVEL_SEGMENTS)
		var angle_a := ratio_a * PI * 0.5
		var angle_b := ratio_b * PI * 0.5
		var expand_a := BEVEL * sin(angle_a)
		var expand_b := BEVEL * sin(angle_b)
		var half_w_a := half_w - BEVEL + expand_a
		var half_h_a := half_h - BEVEL + expand_a
		var half_w_b := half_w - BEVEL + expand_b
		var half_h_b := half_h - BEVEL + expand_b
		var radius_a := CORNER_RADIUS - BEVEL + expand_a
		var radius_b := CORNER_RADIUS - BEVEL + expand_b
		var ring_a := _rounded_ring(half_w_a, half_h_a, radius_a)
		var ring_b := _rounded_ring(half_w_b, half_h_b, radius_b)
		var offset_a := BEVEL * (1.0 - cos(angle_a))
		var offset_b := BEVEL * (1.0 - cos(angle_b))
		var y_a := half_d - offset_a if top else -half_d + offset_a
		var y_b := half_d - offset_b if top else -half_d + offset_b
		for index in range(ring_a.size()):
			var next := (index + 1) % ring_a.size()
			var outward_a := _ring_outward_normal(
				ring_a[index], half_w_a, half_h_a, radius_a)
			var outward_a_next := _ring_outward_normal(
				ring_a[next], half_w_a, half_h_a, radius_a)
			var outward_b := _ring_outward_normal(
				ring_b[index], half_w_b, half_h_b, radius_b)
			var outward_b_next := _ring_outward_normal(
				ring_b[next], half_w_b, half_h_b, radius_b)
			var normal_a := (cap_normal * cos(angle_a)
				+ outward_a * sin(angle_a)).normalized()
			var normal_a_next := (cap_normal * cos(angle_a)
				+ outward_a_next * sin(angle_a)).normalized()
			var normal_b := (cap_normal * cos(angle_b)
				+ outward_b * sin(angle_b)).normalized()
			var normal_b_next := (cap_normal * cos(angle_b)
				+ outward_b_next * sin(angle_b)).normalized()
			var point_a := Vector3(ring_a[index].x, y_a, ring_a[index].y)
			var point_a_next := Vector3(
				ring_a[next].x, y_a, ring_a[next].y)
			var point_b_next := Vector3(
				ring_b[next].x, y_b, ring_b[next].y)
			var point_b := Vector3(ring_b[index].x, y_b, ring_b[index].y)
			if top:
				_emit_quad(surface, point_a, point_b,
					point_b_next, point_a_next,
					normal_a, normal_b, normal_b_next, normal_a_next)
			else:
				_emit_quad(surface, point_a, point_a_next,
					point_b_next, point_b,
					normal_a, normal_a_next, normal_b_next, normal_b)


static func _emit_side(surface: SurfaceTool, ring: Array[Vector2],
		top_y: float, bottom_y: float) -> void:
	for index in range(ring.size()):
		var next := (index + 1) % ring.size()
		var normal_a := _outward_normal(ring[index])
		var normal_b := _outward_normal(ring[next])
		_emit_quad(surface,
			Vector3(ring[index].x, top_y, ring[index].y),
			Vector3(ring[index].x, bottom_y, ring[index].y),
			Vector3(ring[next].x, bottom_y, ring[next].y),
			Vector3(ring[next].x, top_y, ring[next].y),
			normal_a, normal_a, normal_b, normal_b)


static func _outward_normal(point: Vector2) -> Vector3:
	var half_w := TILE_W * 0.5
	var half_h := TILE_H * 0.5
	return _ring_outward_normal(point, half_w, half_h, CORNER_RADIUS)


static func _ring_outward_normal(point: Vector2, half_w: float,
		half_h: float, radius: float) -> Vector3:
	var corner_center := Vector2(
		clampf(point.x, -half_w + radius, half_w - radius),
		clampf(point.y, -half_h + radius, half_h - radius))
	var direction := (point - corner_center).normalized()
	return Vector3(direction.x, 0, direction.y)


static func _emit_quad(surface: SurfaceTool,
		p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3,
		n0: Vector3, n1: Vector3, n2: Vector3, n3: Vector3) -> void:
	var points := [p0, p1, p2, p0, p2, p3]
	var normals := [n0, n1, n2, n0, n2, n3]
	for index in range(6):
		_emit_vertex(surface, points[index], normals[index], Vector2.ZERO)


static func _emit_vertex(surface: SurfaceTool, point: Vector3,
		normal: Vector3, uv: Vector2) -> void:
	surface.set_normal(normal)
	surface.set_uv(uv)
	surface.add_vertex(point)


func _input_event(_camera: Camera3D, event: InputEvent,
		_pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if not clickable:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if not Tile.is_valid_instance_id(tile_instance_id):
				return
			tile_clicked.emit(tile_instance_id)


func _on_mouse_entered() -> void:
	if clickable:
		_is_hovered = true
		_refresh_lifted()
		tile_hover.emit(tile_id, true)


func _on_mouse_exited() -> void:
	if clickable:
		_is_hovered = false
		_refresh_lifted()
		tile_hover.emit(tile_id, false)
