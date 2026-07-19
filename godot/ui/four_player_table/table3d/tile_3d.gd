class_name Tile3D extends Area3D

# 雀魂式立体牌：有厚度方块，+Y 面贴牌图，其余面实体色。

const TILE_W: float = 0.058
const TILE_H: float = 0.078
const TILE_D: float = 0.028

signal tile_clicked(tile_id: int)
signal tile_hover(tile_id: int, entered: bool)

var tile_id: int = -1
var is_red_dora: bool = false
var face_up: bool = true
var clickable: bool = false
var _mesh: MeshInstance3D = null
var _collision: CollisionShape3D = null
var _base_y: float = 0.0
var _lifted: bool = false


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
	_mesh.mesh = _build_box_mesh()
	add_child(_mesh)
	_collision = CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(TILE_W, TILE_D, TILE_H)
	_collision.shape = shape
	add_child(_collision)


# 6 面 ArrayMesh：0=+Y 正面, 1=-Y 底, 2..5 侧面
static func _build_box_mesh() -> ArrayMesh:
	var hw := TILE_W * 0.5
	var hd := TILE_D * 0.5
	var hh := TILE_H * 0.5
	var am := ArrayMesh.new()
	# 面: verts (4) + normal + uvs
	var faces: Array = [
		# +Y face (top / face)
		[Vector3(-hw, hd, -hh), Vector3(hw, hd, -hh), Vector3(hw, hd, hh), Vector3(-hw, hd, hh), Vector3.UP],
		# -Y bottom
		[Vector3(-hw, -hd, hh), Vector3(hw, -hd, hh), Vector3(hw, -hd, -hh), Vector3(-hw, -hd, -hh), Vector3.DOWN],
		# +Z
		[Vector3(-hw, -hd, hh), Vector3(-hw, hd, hh), Vector3(hw, hd, hh), Vector3(hw, -hd, hh), Vector3(0, 0, 1)],
		# -Z
		[Vector3(hw, -hd, -hh), Vector3(hw, hd, -hh), Vector3(-hw, hd, -hh), Vector3(-hw, -hd, -hh), Vector3(0, 0, -1)],
		# +X
		[Vector3(hw, -hd, hh), Vector3(hw, hd, hh), Vector3(hw, hd, -hh), Vector3(hw, -hd, -hh), Vector3.RIGHT],
		# -X
		[Vector3(-hw, -hd, -hh), Vector3(-hw, hd, -hh), Vector3(-hw, hd, hh), Vector3(-hw, -hd, hh), Vector3.LEFT],
	]
	var uvs: PackedVector2Array = [
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)
	]
	for fi in range(faces.size()):
		var f: Array = faces[fi]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n: Vector3 = f[4]
		# tri 0-1-2, 0-2-3
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(uvs[idx])
			st.add_vertex(f[idx])
		st.generate_tangents()
		st.commit(am)
	return am


func setup(p_tile_id: int, p_face_up: bool = true, p_red: bool = false) -> void:
	tile_id = p_tile_id
	face_up = p_face_up
	is_red_dora = p_red
	_ensure_mesh()
	_apply_materials()


func set_face_up(p_face_up: bool) -> void:
	face_up = p_face_up
	_apply_materials()


func set_clickable(b: bool) -> void:
	clickable = b
	input_ray_pickable = true


func set_lifted(b: bool) -> void:
	if _lifted == b:
		return
	_lifted = b
	var target_y: float = _base_y + (0.018 if b else 0.0)
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_property(self, "position:y", target_y, 0.08)
	else:
		position.y = target_y


func set_base_position(pos: Vector3) -> void:
	_base_y = pos.y
	position = pos
	if _lifted:
		position.y = _base_y + 0.018


func set_dim(b: bool) -> void:
	if _mesh == null:
		return
	# Area3D 无 modulate；用 mesh 透明度近似压暗
	_mesh.transparency = 0.4 if b else 0.0


func _apply_materials() -> void:
	_ensure_mesh()
	var mat_face := _make_face_mat()
	var mat_side := StandardMaterial3D.new()
	mat_side.albedo_color = Color(0.94, 0.92, 0.88)
	mat_side.roughness = 0.5
	var mat_bottom := StandardMaterial3D.new()
	mat_bottom.albedo_color = Color(0.10, 0.38, 0.24)
	mat_bottom.roughness = 0.65
	# surface 0 = face, 1 = bottom, 2-5 = sides
	if _mesh.mesh.get_surface_count() >= 6:
		_mesh.set_surface_override_material(0, mat_face)
		_mesh.set_surface_override_material(1, mat_bottom)
		for s in range(2, 6):
			_mesh.set_surface_override_material(s, mat_side)
	else:
		_mesh.material_override = mat_face


func _make_face_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 0.4
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if face_up and tile_id >= 0:
		var key: String = CardTileBack.tile_id_to_atlas_key(tile_id, is_red_dora)
		var tex: Texture2D = _get_tex(key)
		if tex != null:
			m.albedo_texture = tex
			m.albedo_color = Color.WHITE
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			return m
	var back: Texture2D = _get_tex("back")
	if back != null:
		m.albedo_texture = back
		m.albedo_color = Color.WHITE
	else:
		m.albedo_color = Color(0.12, 0.42, 0.28)
	return m


func _get_tex(key: String) -> Texture2D:
	if key == "":
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var ext: Node = tree.root.get_node_or_null("TextureExtractor")
	if ext == null or not ext.has_method("get_tile_texture"):
		return null
	return ext.get_tile_texture(key)


func _input_event(_camera: Camera3D, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if not clickable:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			tile_clicked.emit(tile_id)


func _on_mouse_entered() -> void:
	if clickable:
		set_lifted(true)
		tile_hover.emit(tile_id, true)


func _on_mouse_exited() -> void:
	if clickable:
		set_lifted(false)
		tile_hover.emit(tile_id, false)
