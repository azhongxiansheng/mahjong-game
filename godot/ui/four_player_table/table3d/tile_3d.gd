class_name Tile3D extends Area3D

# 雀魂式立体牌：有厚度方块，+Y 面贴牌图，其余面实体色。

# 世界单位：桌面河/副露用此尺寸；自家手牌在 MahjongTable3D 再 scale
const TILE_W: float = 0.072
const TILE_H: float = 0.098
const TILE_D: float = 0.034

# E2-02 / #232：点击发 tile_instance_id；hover 仍发 tile_id（同名联动）
signal tile_clicked(tile_instance_id: int)
signal tile_hover(tile_id: int, entered: bool)

var tile_id: int = -1
var is_red_dora: bool = false
var face_up: bool = true
var clickable: bool = false
# entity identity；setup() 纯展示清空；setup_entity 注入
var tile_instance_id: int = Tile.INVALID_INSTANCE_ID
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


# 纯展示入口：清空 entity identity
func setup(p_tile_id: int, p_face_up: bool = true, p_red: bool = false) -> void:
	tile_id = p_tile_id
	face_up = p_face_up
	is_red_dora = p_red
	tile_instance_id = Tile.INVALID_INSTANCE_ID
	_ensure_mesh()
	_apply_materials()


# 手牌等可动作牌：注入 instance_id
func setup_entity(p_tile_id: int, p_face_up: bool, p_red: bool, p_instance_id: int) -> void:
	tile_id = p_tile_id
	face_up = p_face_up
	is_red_dora = p_red
	tile_instance_id = p_instance_id
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
	_mesh.transparency = 0.4 if b else 0.0


# 平滑飞到目标位姿（切牌入河 / 摸牌落下）
func animate_to(pos: Vector3, rot_deg: Vector3, duration: float = 0.22) -> void:
	_base_y = pos.y
	if not is_inside_tree():
		position = pos
		rotation_degrees = rot_deg
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position", pos, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "rotation_degrees", rot_deg, duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func animate_draw_drop(from_y_extra: float = 0.12, duration: float = 0.2) -> void:
	var target := position
	position.y = target.y + from_y_extra
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_property(self, "position:y", target.y, duration)\
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _apply_materials() -> void:
	_ensure_mesh()
	# 雀魂感：正面牌图、侧面牙白、底/背深绿
	var mat_face := _make_face_mat()
	var mat_side := StandardMaterial3D.new()
	mat_side.albedo_color = Color(0.96, 0.94, 0.90)
	mat_side.roughness = 0.42
	mat_side.metallic = 0.05
	var mat_bottom := StandardMaterial3D.new()
	mat_bottom.albedo_color = Color(0.08, 0.32, 0.20)
	mat_bottom.roughness = 0.7
	var mat_back_face := _make_back_mat()
	# 0=+Y 正面, 1=-Y 底, 2..5 侧
	if _mesh.mesh.get_surface_count() >= 6:
		if face_up:
			_mesh.set_surface_override_material(0, mat_face)
			_mesh.set_surface_override_material(1, mat_bottom)
		else:
			_mesh.set_surface_override_material(0, mat_back_face)
			_mesh.set_surface_override_material(1, mat_face if tile_id >= 0 else mat_bottom)
		for s in range(2, 6):
			_mesh.set_surface_override_material(s, mat_side)
	else:
		_mesh.material_override = mat_face if face_up else mat_back_face


func _make_face_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 0.38
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if tile_id >= 0:
		var key: String = CardTileBack.tile_id_to_atlas_key(tile_id, is_red_dora)
		var tex: Texture2D = _get_tex(key)
		if tex != null:
			m.albedo_texture = tex
			m.albedo_color = Color.WHITE
			# 不用 mipmap：远景小牌 mip 会糊成纯色条
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
			return m
	m.albedo_color = Color(0.95, 0.94, 0.9)
	return m


func _make_back_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 0.55
	var back: Texture2D = _get_tex("back")
	if back != null:
		m.albedo_texture = back
		m.albedo_color = Color.WHITE
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	else:
		m.albedo_color = Color(0.10, 0.38, 0.24)
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
			if not Tile.is_valid_instance_id(tile_instance_id):
				return
			tile_clicked.emit(tile_instance_id)


func _on_mouse_entered() -> void:
	if clickable:
		set_lifted(true)
		tile_hover.emit(tile_id, true)


func _on_mouse_exited() -> void:
	if clickable:
		set_lifted(false)
		tile_hover.emit(tile_id, false)
