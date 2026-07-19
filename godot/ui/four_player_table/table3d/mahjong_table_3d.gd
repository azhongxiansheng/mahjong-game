class_name MahjongTable3D extends Control

# 雀魂式 3D 牌桌 M2：副露 + 摸切动画 + 光照/中心盘 + 六面材质

signal player_card_clicked(tile_id: int)
signal hand_tile_hover(tile_id: int, entered: bool)

const TABLE_W: float = 2.5
const TABLE_D: float = 2.5

var seat_panels: Array = []
var discard_rivers: Array = []
var meld_areas: Array = []
var center_info = null
var ability_panel = null

var _vp: SubViewport = null
var _vp_host: SubViewportContainer = null
var _world_root: Node3D = null
var _camera: Camera3D = null
var _hand_tiles: Array = []
var _river_tiles: Array = [[], [], [], []]
var _opp_tiles: Array = [[], [], [], []]
var _meld_tiles: Array = [[], [], [], []]
var _dora_tiles: Array = []
var _hand_clickable: bool = false
var _state: BattleState = null
var _center_label: Label3D = null
var _center_plate: MeshInstance3D = null
var _prev_hand_count: int = -1
var _prev_river_count: Array = [0, 0, 0, 0]


func _ready() -> void:
	custom_minimum_size = Vector2(TableLayout.TABLE_W, TableLayout.TABLE_H)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_3d()
	# duck：adapter 把 self 当 seat0
	seat_panels = [self, self, self, self]


func _build_3d() -> void:
	_vp_host = SubViewportContainer.new()
	_vp_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp_host.stretch = true
	_vp_host.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_vp_host)

	_vp = SubViewport.new()
	_vp.size = Vector2i(int(TableLayout.TABLE_W), int(TableLayout.TABLE_H))
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	_vp.handle_input_locally = true
	_vp.physics_object_picking = true
	_vp.transparent_bg = false
	_vp_host.add_child(_vp)

	_world_root = Node3D.new()
	_world_root.name = "World"
	_vp.add_child(_world_root)

	var env_node := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.035, 0.04, 0.055)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.68)
	e.ambient_light_energy = 0.5
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.ssao_radius = 0.8
	e.ssao_intensity = 1.2
	env_node.environment = e
	_world_root.add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 28, 0)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.98, 0.94)
	_world_root.add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 1.6, 0.35)
	fill.light_energy = 0.55
	fill.omni_range = 5.5
	fill.light_color = Color(0.85, 0.9, 1.0)
	_world_root.add_child(fill)

	# 桌面
	var table := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(TABLE_W, 0.06, TABLE_D)
	table.mesh = plane
	table.position = Vector3(0, -0.03, 0)
	var tmat := StandardMaterial3D.new()
	tmat.roughness = 0.9
	if ResourceLoader.exists("res://assets/table_felt.png"):
		tmat.albedo_texture = load("res://assets/table_felt.png")
		tmat.albedo_color = Color(0.88, 0.98, 0.9)
	else:
		tmat.albedo_color = Color(0.08, 0.34, 0.22)
	table.material_override = tmat
	_world_root.add_child(table)

	_add_rail(Vector3(0, 0.025, -TABLE_D * 0.5 - 0.055), Vector3(TABLE_W + 0.18, 0.10, 0.11))
	_add_rail(Vector3(0, 0.025, TABLE_D * 0.5 + 0.055), Vector3(TABLE_W + 0.18, 0.10, 0.11))
	_add_rail(Vector3(-TABLE_W * 0.5 - 0.055, 0.025, 0), Vector3(0.11, 0.10, TABLE_D))
	_add_rail(Vector3(TABLE_W * 0.5 + 0.055, 0.025, 0), Vector3(0.11, 0.10, TABLE_D))

	# 中心盘（3D 圆角近似方块 + 金字）
	_center_plate = MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.42, 0.02, 0.42)
	_center_plate.mesh = plate_mesh
	_center_plate.position = Vector3(0, 0.012, 0)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.08, 0.10, 0.18)
	pmat.metallic = 0.35
	pmat.roughness = 0.35
	_center_plate.material_override = pmat
	_world_root.add_child(_center_plate)

	_center_label = Label3D.new()
	_center_label.text = "东 1 局"
	_center_label.font_size = 42
	_center_label.modulate = Color(0.98, 0.88, 0.45)
	_center_label.position = Vector3(0, 0.035, 0)
	_center_label.rotation_degrees = Vector3(-90, 0, 0)
	_center_label.outline_size = 10
	_center_label.outline_modulate = Color(0, 0, 0, 0.85)
	_world_root.add_child(_center_label)

	# 相机：更俯、更近，接近雀魂桌感
	_camera = Camera3D.new()
	_camera.fov = 34.0
	_camera.position = Vector3(0, 2.05, 1.72)
	_camera.current = true
	_world_root.add_child(_camera)
	_camera.look_at(Vector3(0, 0, 0.12), Vector3.UP)


func _add_rail(pos: Vector3, size: Vector3) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	m.mesh = box
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.17, 0.08)
	mat.roughness = 0.72
	m.material_override = mat
	_world_root.add_child(m)


# ---- API ----

func bind_battle_state(state: BattleState, hand_index: int = 0, _hpr: int = 4) -> void:
	_state = state
	if state == null:
		return
	if _center_label:
		var wall_n: int = state.wall.live_wall_size() if state.wall else 0
		_center_label.text = "东 %d 局\n余 %d" % [hand_index + 1, wall_n]
	var hand_n: int = state.seats[0].hand.size()
	var animate_draw: bool = _prev_hand_count >= 0 and hand_n == _prev_hand_count + 1
	_rebuild_player_hand(state.seats[0], animate_draw)
	_prev_hand_count = hand_n
	for s in range(4):
		var river: Array = state.discards_per_seat[s]
		var animate_disc: bool = _prev_river_count[s] >= 0 and river.size() == _prev_river_count[s] + 1
		_rebuild_river(s, river, state.seats[s].riichi.riichi_discard_index, animate_disc)
		_prev_river_count[s] = river.size()
		_rebuild_melds(s, state.seats[s].melds)
	for s in range(1, 4):
		_rebuild_opponent_backs(s, state.seats[s].hand.size())
	_rebuild_dora(state)


func bind_cumulative_scores(_scores: Array) -> void:
	pass


func highlight_tile_id(_tile_id: int) -> void:
	pass


func clear_tile_highlight() -> void:
	pass


func set_hand_clickable(b: bool) -> void:
	_hand_clickable = b
	for t in _hand_tiles:
		if t is Tile3D:
			(t as Tile3D).set_clickable(b)
			if not b:
				(t as Tile3D).set_lifted(false)


func dim_hand_except(allowed: Array) -> void:
	for t in _hand_tiles:
		if t is Tile3D:
			var tid: int = (t as Tile3D).tile_id
			var ok := false
			for a in allowed:
				if int(a) == tid:
					ok = true
					break
			(t as Tile3D).set_dim(not ok)


func clear_hand_dim() -> void:
	for t in _hand_tiles:
		if t is Tile3D:
			(t as Tile3D).set_dim(false)


func mark_win_tile(_tid: int) -> void:
	pass


func clear_hand_reveal() -> void:
	pass


func reveal_hand_face_up(_hand, _animate: bool = true) -> void:
	pass


func set_emote(_s: String) -> void:
	pass


func say(_t: String) -> void:
	pass


func get_portrait_texture() -> Texture2D:
	return null


func get_hand_slot_global_center(_tile_id: int) -> Vector2:
	return size * 0.5


func set_active(_b: bool) -> void:
	pass


func set_tenpai(_b: bool) -> void:
	pass


func set_wait_tiles(_ids: Array) -> void:
	pass


func clear_wait_tiles() -> void:
	pass


func set_ippatsu(_b: bool) -> void:
	pass


func set_dora_ids(_ids: Array) -> void:
	pass


func set_discards_count(_n: int) -> void:
	pass


func set_score(_n: int) -> void:
	pass


func bind_seat(_s) -> void:
	pass


func set_ai_persona(_a, _b, _c = "") -> void:
	pass


# ---- rebuild ----

func _free_arr(arr: Array) -> void:
	for n in arr:
		if n is Node and is_instance_valid(n):
			(n as Node).queue_free()
	arr.clear()


func _rebuild_player_hand(seat: Seat, animate_draw: bool = false) -> void:
	_free_arr(_hand_tiles)
	if seat == null or seat.hand == null:
		return
	var ids: Array = seat.hand.to_id_array()
	var drawn_id: int = seat.last_drawn_tile_id
	var sorted_ids: Array = ids.duplicate()
	var drawn_ids: Array = []
	if drawn_id >= 0:
		var idx: int = sorted_ids.find(drawn_id)
		if idx >= 0:
			sorted_ids.remove_at(idx)
			drawn_ids.append(drawn_id)
	sorted_ids.sort()
	var show: Array = sorted_ids + drawn_ids
	var n: int = show.size()
	if n == 0:
		return
	var gap: float = Tile3D.TILE_W + 0.005
	var total: float = n * gap + (0.028 if drawn_ids.size() > 0 and sorted_ids.size() > 0 else 0.0)
	var x0: float = -total * 0.5 + gap * 0.5
	var z: float = 0.98
	var y: float = Tile3D.TILE_D * 0.5 + 0.002
	var x_cursor: float = x0
	for i in range(n):
		var tid: int = int(show[i])
		var is_red := false
		for t in seat.hand._tiles:
			if t.id == tid and t.is_red_dora:
				is_red = true
				break
		var is_drawn_slot: bool = drawn_ids.size() > 0 and i == sorted_ids.size() and sorted_ids.size() > 0
		if is_drawn_slot:
			x_cursor += 0.028
		var tile := Tile3D.new()
		_world_root.add_child(tile)
		tile.setup(tid, true, is_red)
		tile.set_base_position(Vector3(x_cursor, y, z))
		tile.rotation_degrees = Vector3(-20, 0, 0)
		tile.set_clickable(_hand_clickable)
		tile.tile_clicked.connect(_on_tile_clicked)
		tile.tile_hover.connect(_on_tile_hover)
		if animate_draw and is_drawn_slot:
			tile.animate_draw_drop(0.14, 0.22)
		_hand_tiles.append(tile)
		x_cursor += gap


func _rebuild_river(seat_id: int, tiles: Array, riichi_idx: int, animate_last: bool = false) -> void:
	_free_arr(_river_tiles[seat_id])
	if tiles == null:
		return
	var i := 0
	var last_i: int = tiles.size() - 1
	for t in tiles:
		if t == null:
			continue
		var tid: int = t.id if t is Tile else int(t)
		var is_red: bool = (t is Tile and t.is_red_dora)
		var tile := Tile3D.new()
		_world_root.add_child(tile)
		tile.setup(tid, true, is_red)
		var col: int = i % 6
		var row: int = int(i / 6.0)
		var lr: Dictionary = _river_pose(seat_id, col, row, i == riichi_idx and riichi_idx >= 0)
		if animate_last and i == last_i:
			# 从该 seat 手牌方向飞入
			var from: Vector3 = lr.pos + _seat_in_dir(seat_id) * 0.35 + Vector3(0, 0.12, 0)
			tile.position = from
			tile.rotation_degrees = lr.rot + Vector3(-40, 0, 0)
			tile.animate_to(lr.pos, lr.rot, 0.2)
			tile._base_y = lr.pos.y
		else:
			tile.set_base_position(lr.pos)
			tile.rotation_degrees = lr.rot
		_river_tiles[seat_id].append(tile)
		i += 1


func _seat_in_dir(seat_id: int) -> Vector3:
	match seat_id:
		0: return Vector3(0, 0, 1)
		1: return Vector3(1, 0, 0)
		2: return Vector3(0, 0, -1)
		3: return Vector3(-1, 0, 0)
	return Vector3.ZERO


func _river_pose(seat_id: int, col: int, row: int, riichi: bool) -> Dictionary:
	var gx: float = Tile3D.TILE_W + 0.003
	var gz: float = Tile3D.TILE_H + 0.003
	var y: float = Tile3D.TILE_D * 0.5 + 0.002
	var dx: float = (col - 2.5) * gx
	var dz: float = row * gz
	var pos: Vector3
	var rot: Vector3 = Vector3.ZERO
	match seat_id:
		0:
			pos = Vector3(dx, y, 0.32 + dz)
		1:
			pos = Vector3(0.38 + dz, y, -dx)
			rot = Vector3(0, -90, 0)
		2:
			pos = Vector3(-dx, y, -0.32 - dz)
			rot = Vector3(0, 180, 0)
		3:
			pos = Vector3(-0.38 - dz, y, dx)
			rot = Vector3(0, 90, 0)
		_:
			pos = Vector3(dx, y, 0.32)
	if riichi:
		rot.y += 90.0
	return {"pos": pos, "rot": rot}


func _rebuild_opponent_backs(seat_id: int, count: int) -> void:
	_free_arr(_opp_tiles[seat_id])
	var n: int = clampi(count, 0, 14)
	if n == 0:
		return
	var gap: float = Tile3D.TILE_W * 0.50
	var y: float = Tile3D.TILE_D * 0.5 + 0.002
	for i in range(n):
		var tile := Tile3D.new()
		_world_root.add_child(tile)
		tile.setup(-1, false, false)
		var t: float = (i - (n - 1) * 0.5) * gap
		match seat_id:
			1:
				tile.set_base_position(Vector3(1.12, y + 0.015, t * 0.62))
				tile.rotation_degrees = Vector3(0, -90, 58)
			2:
				tile.set_base_position(Vector3(t, y, -1.08))
				tile.rotation_degrees = Vector3(0, 180, 0)
			3:
				tile.set_base_position(Vector3(-1.12, y + 0.015, -t * 0.62))
				tile.rotation_degrees = Vector3(0, 90, -58)
		_opp_tiles[seat_id].append(tile)


func _rebuild_melds(seat_id: int, melds: Array) -> void:
	_free_arr(_meld_tiles[seat_id])
	if melds == null or melds.is_empty():
		return
	var y: float = Tile3D.TILE_D * 0.5 + 0.002
	var gap: float = Tile3D.TILE_W + 0.004
	var group_gap: float = 0.028
	# 各 seat 副露锚点（面前右侧）
	var cursor: Vector3
	var yaw: float = 0.0
	var along: Vector3  # 牌并排方向
	match seat_id:
		0:
			cursor = Vector3(0.55, y, 0.72)
			along = Vector3(-1, 0, 0)
			yaw = 0.0
		1:
			cursor = Vector3(0.72, y, -0.55)
			along = Vector3(0, 0, 1)
			yaw = -90.0
		2:
			cursor = Vector3(-0.55, y, -0.72)
			along = Vector3(1, 0, 0)
			yaw = 180.0
		3:
			cursor = Vector3(-0.72, y, 0.55)
			along = Vector3(0, 0, -1)
			yaw = 90.0
		_:
			return
	for meld in melds:
		if meld == null or not (meld is Meld):
			continue
		var m: Meld = meld
		var tiles: Array = m.tiles
		var n: int = tiles.size()
		for j in range(n):
			var tt: Tile = tiles[j]
			var tile := Tile3D.new()
			_world_root.add_child(tile)
			# 暗杠：两端背朝上
			var face: bool = true
			if m.kind == Meld.Kind.ANKAN and (j == 0 or j == 3):
				face = false
			tile.setup(tt.id, face, tt.is_red_dora)
			var pos: Vector3 = cursor + along * (j * gap)
			# 加杠第 4 张叠在中间
			if m.kind == Meld.Kind.ADDED_KAN and j == 3:
				pos = cursor + along * (1.0 * gap) + Vector3(0, Tile3D.TILE_D + 0.002, 0)
			# 叫牌来源略横放（简化：碰/明杠第一张横）
			var rot := Vector3(0, yaw, 0)
			if m.from_seat != Meld.NO_SOURCE_SEAT and j == 0 and m.kind != Meld.Kind.ANKAN:
				rot.y += 90.0
			tile.set_base_position(pos)
			tile.rotation_degrees = rot
			_meld_tiles[seat_id].append(tile)
		cursor += along * (n * gap + group_gap)


func _rebuild_dora(state: BattleState) -> void:
	_free_arr(_dora_tiles)
	if state == null or state.dora_indicators == null:
		return
	var y: float = Tile3D.TILE_D * 0.5 + 0.004
	var i := 0
	for ti in state.dora_indicators.visible:
		if ti == null:
			continue
		var tile := Tile3D.new()
		_world_root.add_child(tile)
		tile.setup(ti.id, true, false)
		tile.set_base_position(Vector3(-0.12 + i * (Tile3D.TILE_W + 0.006), y, -0.02))
		tile.rotation_degrees = Vector3(0, 0, 0)
		_dora_tiles.append(tile)
		i += 1


func _on_tile_clicked(tile_id: int) -> void:
	if _hand_clickable:
		player_card_clicked.emit(tile_id)


func _on_tile_hover(tile_id: int, entered: bool) -> void:
	hand_tile_hover.emit(tile_id, entered)
