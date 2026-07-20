class_name MahjongTable3D extends Control

# 雀魂式真 3D 牌桌（非假透视 2.5D）：
# - 桌/牌/河/副露：3D mesh + 透视相机（对齐雀魂 Unity 桌）
# - HUD 操作条仍在 2D Control 层（PlayableTable）
# - 自家手牌：近景放大立牌，保证可读可点

signal player_card_clicked(tile_id: int)
signal hand_tile_hover(tile_id: int, entered: bool)

const TABLE_W: float = 2.4
const TABLE_D: float = 2.4
const WALL_RADIUS: float = 0.68
const WALL_GAP: float = 0.078
const PLATE_HALF: float = 0.18
const WALL_STACKS_PER_SIDE_MAX: int = 6
const SHOW_LIVE_WALL: bool = true
# 自家手牌相对桌面的放大（雀魂：手牌占屏底大特写）
const HAND_SCALE: float = 1.65
const HAND_Z: float = 1.08
# 绕 +X 正转：+Y 牌面倾向相机（在 +Z 侧）；负角会把牌面背对相机只见白边+绿底
const HAND_TILT_DEG: float = 48.0

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
var _wall_tiles: Array = []
var _dead_wall_tiles: Array = []
var _riichi_stick_meshes: Array = []
var _center_side_labels: Array = []
var _hand_clickable: bool = false
var _state: BattleState = null
var _center_label: Label3D = null
var _center_plate: MeshInstance3D = null
var _active_marker: MeshInstance3D = null
var _active_light: OmniLight3D = null
var _wall_mesh: BoxMesh = null
var _wall_mat: StandardMaterial3D = null
var _stick_mesh: BoxMesh = null
var _stick_mat: StandardMaterial3D = null
var _stick_glow_mat: StandardMaterial3D = null
var _prev_hand_count: int = -1
var _prev_river_count: Array = [0, 0, 0, 0]
var _prev_wall_count: int = -1
var _scores_override: Array = []


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
	e.ambient_light_energy = 0.72
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# SSAO 在小牌上易糊成色块，可读性优先关掉
	e.ssao_enabled = false
	env_node.environment = e
	_world_root.add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 20, 0)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	sun.light_color = Color(1.0, 0.99, 0.96)
	_world_root.add_child(sun)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 1.4, 0.55)
	fill.light_energy = 0.7
	fill.omni_range = 5.5
	fill.light_color = Color(0.9, 0.92, 1.0)
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

	# 共享牌山 / 立直棒 mesh
	_wall_mesh = BoxMesh.new()
	_wall_mesh.size = Vector3(Tile3D.TILE_W * 0.92, Tile3D.TILE_D, Tile3D.TILE_H * 0.92)
	# 牌山用牙白+暗红顶，避免整墙贴 back.png 远看一片血红
	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_color = Color(0.94, 0.92, 0.88)
	_wall_mat.roughness = 0.5

	_stick_mesh = BoxMesh.new()
	_stick_mesh.size = Vector3(0.055, 0.008, 0.012)
	_stick_mat = StandardMaterial3D.new()
	_stick_mat.albedo_color = Color(0.96, 0.95, 0.92)
	_stick_mat.roughness = 0.4
	_stick_glow_mat = StandardMaterial3D.new()
	_stick_glow_mat.albedo_color = Color(1.0, 0.92, 0.55)
	_stick_glow_mat.emission_enabled = true
	_stick_glow_mat.emission = Color(0.95, 0.75, 0.2)
	_stick_glow_mat.emission_energy_multiplier = 0.55
	_stick_glow_mat.roughness = 0.35

	# 中心盘
	_center_plate = MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(PLATE_HALF * 2.0, 0.02, PLATE_HALF * 2.0)
	_center_plate.mesh = plate_mesh
	_center_plate.position = Vector3(0, 0.012, 0)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.07, 0.09, 0.16)
	pmat.metallic = 0.4
	pmat.roughness = 0.32
	_center_plate.material_override = pmat
	_world_root.add_child(_center_plate)

	_center_label = Label3D.new()
	_center_label.text = "东1 本0 余70"
	_center_label.font_size = 22
	_center_label.modulate = Color(0.98, 0.88, 0.45)
	_center_label.position = Vector3(0, 0.036, 0)
	_center_label.rotation_degrees = Vector3(-90, 0, 0)
	_center_label.outline_size = 8
	_center_label.outline_modulate = Color(0, 0, 0, 0.9)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world_root.add_child(_center_label)

	# 四方风位+分数：贴盘外缘，避免与盘心字重叠
	_center_side_labels.clear()
	for s in range(4):
		var lab := Label3D.new()
		lab.font_size = 18
		lab.modulate = Color(0.92, 0.9, 0.82)
		lab.outline_size = 5
		lab.outline_modulate = Color(0, 0, 0, 0.9)
		lab.rotation_degrees = Vector3(-90, 0, 0)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.position = _side_label_pos(s)
		_world_root.add_child(lab)
		_center_side_labels.append(lab)

	# 当前家高亮条 + 灯
	_active_marker = MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.16, 0.006, 0.02)
	_active_marker.mesh = am
	var amat := StandardMaterial3D.new()
	amat.albedo_color = Color(0.98, 0.82, 0.28)
	amat.emission_enabled = true
	amat.emission = Color(1.0, 0.78, 0.2)
	amat.emission_energy_multiplier = 0.9
	_active_marker.material_override = amat
	_active_marker.position = Vector3(0, 0.028, PLATE_HALF - 0.01)
	_world_root.add_child(_active_marker)

	_active_light = OmniLight3D.new()
	_active_light.light_energy = 0.35
	_active_light.omni_range = 0.85
	_active_light.light_color = Color(1.0, 0.9, 0.55)
	_active_light.position = Vector3(0, 0.45, 0.55)
	_world_root.add_child(_active_light)

	# 雀魂式固定俯斜：略低、略近，手牌面朝相机
	_camera = Camera3D.new()
	_camera.fov = 46.0
	_camera.position = Vector3(0, 1.15, 1.88)
	_camera.current = true
	_world_root.add_child(_camera)
	_camera.look_at(Vector3(0, 0.08, 0.38), Vector3.UP)


func _try_back_tex() -> Texture2D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var ext: Node = tree.root.get_node_or_null("TextureExtractor")
	if ext == null or not ext.has_method("get_tile_texture"):
		return null
	return ext.get_tile_texture("back")


func _add_rail(pos: Vector3, rail_size: Vector3) -> void:
	var m := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = rail_size
	m.mesh = box
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.17, 0.08)
	mat.roughness = 0.72
	m.material_override = mat
	_world_root.add_child(m)


func _side_label_pos(seat_id: int) -> Vector3:
	# 放在盘外缘外一点，不与盘心「东N·本场·余」重叠
	var r: float = PLATE_HALF + 0.18
	match seat_id:
		0: return Vector3(0, 0.032, r)
		1: return Vector3(r, 0.032, 0)
		2: return Vector3(0, 0.032, -r)
		3: return Vector3(-r, 0.032, 0)
	return Vector3.ZERO


# ---- API ----

func bind_battle_state(state: BattleState, hand_index: int = 0, _hpr: int = 4) -> void:
	_state = state
	if state == null:
		return
	_update_center_info(state, hand_index)
	_update_active_seat(state.current_seat)
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
	var wall_n: int = state.wall.live_wall_size() if state.wall else 0
	# 张数变化才重建牌山，避免每帧 70 mesh 重建
	if wall_n != _prev_wall_count:
		_rebuild_live_wall(wall_n)
		_rebuild_dead_wall(state)
		_prev_wall_count = wall_n
	_rebuild_riichi_sticks(state)


func bind_cumulative_scores(scores: Array) -> void:
	_scores_override = scores.duplicate() if scores != null else []
	if _state != null:
		_update_center_info(_state, maxi(_state.hand_number - 1, 0))


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


func _wind_char(wind: int) -> String:
	match wind:
		TileId.E: return "东"
		TileId.S_WIND: return "南"
		TileId.W_WIND: return "西"
		TileId.N: return "北"
	return "?"


func _round_wind_char(wind: int) -> String:
	return "东" if wind == TileId.E else "南"


func _seat_points(state: BattleState, seat_id: int) -> int:
	if _scores_override.size() > seat_id:
		return int(_scores_override[seat_id])
	if state.seats.size() > seat_id:
		return int(state.seats[seat_id].points)
	return 25000


func _update_center_info(state: BattleState, hand_index: int) -> void:
	if _center_label == null:
		return
	var wall_n: int = state.wall.live_wall_size() if state.wall else 0
	var hn: int = state.hand_number if state.hand_number > 0 else hand_index + 1
	# 单行短文案，避免与四方分重叠
	_center_label.text = "%s%d · 本%d · 棒%d · 余%d" % [
		_round_wind_char(state.round_wind), hn, state.honba, state.riichi_sticks, wall_n
	]
	for s in range(4):
		if s >= _center_side_labels.size() or s >= state.seats.size():
			continue
		var seat: Seat = state.seats[s]
		var lab: Label3D = _center_side_labels[s]
		var mark: String = "▶" if s == state.current_seat else ""
		lab.text = "%s%s %d" % [mark, _wind_char(seat.seat_wind), _seat_points(state, s)]
		if seat.riichi.declared:
			lab.modulate = Color(1.0, 0.86, 0.35)
		elif s == state.current_seat:
			lab.modulate = Color(1.0, 0.95, 0.65)
		else:
			lab.modulate = Color(0.9, 0.88, 0.8)


func _update_active_seat(seat_id: int) -> void:
	if _active_marker == null:
		return
	var r: float = PLATE_HALF - 0.01
	var pos: Vector3
	var rot_y: float = 0.0
	match seat_id:
		0:
			pos = Vector3(0, 0.028, r)
			rot_y = 0.0
		1:
			pos = Vector3(r, 0.028, 0)
			rot_y = 90.0
		2:
			pos = Vector3(0, 0.028, -r)
			rot_y = 0.0
		3:
			pos = Vector3(-r, 0.028, 0)
			rot_y = 90.0
		_:
			pos = Vector3(0, 0.028, r)
	_active_marker.position = pos
	_active_marker.rotation_degrees = Vector3(0, rot_y, 0)
	if _active_light:
		var dir: Vector3 = _seat_in_dir(seat_id)
		_active_light.position = dir * 0.55 + Vector3(0, 0.5, 0)


func _make_wall_piece() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _wall_mesh
	mi.material_override = _wall_mat
	_world_root.add_child(mi)
	return mi


func _rebuild_live_wall(live: int) -> void:
	_free_arr(_wall_tiles)
	if not SHOW_LIVE_WALL or live <= 0 or _wall_mesh == null:
		return
	# 示意堆：每侧最多 WALL_STACKS_PER_SIDE_MAX 双层，gap ≥ 牌宽，避免红墙糊屏
	var stacks_total: int = mini(int(ceili(float(live) / 2.0)), WALL_STACKS_PER_SIDE_MAX * 4)
	var per: Array = [0, 0, 0, 0]
	var base_n: int = stacks_total / 4
	var rem: int = stacks_total % 4
	for s in range(4):
		per[s] = base_n + (1 if s < rem else 0)
	var y0: float = Tile3D.TILE_D * 0.5 + 0.002
	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_color = Color(0.78, 0.18, 0.16)
	top_mat.roughness = 0.55
	for seat_id in range(4):
		var n: int = int(per[seat_id])
		if n <= 0:
			continue
		for i in range(n):
			var t_along: float = (i - (n - 1) * 0.5) * WALL_GAP
			for layer in range(2):
				var mi := _make_wall_piece()
				if layer == 1:
					mi.material_override = top_mat
				var pos: Vector3
				var yaw: float = 0.0
				match seat_id:
					0:
						pos = Vector3(t_along, y0 + layer * Tile3D.TILE_D, WALL_RADIUS)
						yaw = 0.0
					1:
						pos = Vector3(WALL_RADIUS, y0 + layer * Tile3D.TILE_D, -t_along)
						yaw = -90.0
					2:
						pos = Vector3(-t_along, y0 + layer * Tile3D.TILE_D, -WALL_RADIUS)
						yaw = 180.0
					3:
						pos = Vector3(-WALL_RADIUS, y0 + layer * Tile3D.TILE_D, t_along)
						yaw = 90.0
					_:
						pos = Vector3(t_along, y0, WALL_RADIUS)
				mi.position = pos
				mi.rotation_degrees = Vector3(0, yaw, 0)
				_wall_tiles.append(mi)


func _rebuild_dead_wall(state: BattleState) -> void:
	_free_arr(_dead_wall_tiles)
	if state == null or state.wall == null or _wall_mesh == null:
		return
	# 王牌区：5 叠示意（非满 14），牙白底+暗红顶
	var y0: float = Tile3D.TILE_D * 0.5 + 0.002
	var stacks: int = 5
	var gap: float = WALL_GAP
	var base_x: float = 0.16
	var base_z: float = -0.14
	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_color = Color(0.72, 0.16, 0.14)
	top_mat.roughness = 0.55
	for i in range(stacks):
		for layer in range(2):
			var mi := _make_wall_piece()
			if layer == 1:
				mi.material_override = top_mat
			mi.position = Vector3(base_x + i * gap, y0 + layer * Tile3D.TILE_D, base_z)
			mi.rotation_degrees = Vector3(0, 0, 0)
			_dead_wall_tiles.append(mi)


func _make_stick(glow: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _stick_mesh
	mi.material_override = _stick_glow_mat if glow else _stick_mat
	_world_root.add_child(mi)
	# 红点识别条
	var tip := MeshInstance3D.new()
	var tip_mesh := BoxMesh.new()
	tip_mesh.size = Vector3(0.012, 0.009, 0.013)
	tip.mesh = tip_mesh
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.85, 0.12, 0.12)
	if glow:
		tmat.emission_enabled = true
		tmat.emission = Color(0.9, 0.2, 0.15)
		tmat.emission_energy_multiplier = 0.4
	tip.material_override = tmat
	tip.position = Vector3(0, 0.001, 0)
	mi.add_child(tip)
	return mi


func _rebuild_riichi_sticks(state: BattleState) -> void:
	_free_arr(_riichi_stick_meshes)
	if state == null or _stick_mesh == null:
		return
	# 桌上供托立直棒（池）
	var pool: int = mini(state.riichi_sticks, 8)
	for i in range(pool):
		var stick := _make_stick(true)
		stick.position = Vector3(-0.07 + i * 0.028, 0.026, 0.06)
		stick.rotation_degrees = Vector3(0, 12.0 * (i % 3 - 1), 0)
		_riichi_stick_meshes.append(stick)
	# 各家已立直：面前放一根
	for s in range(4):
		if s >= state.seats.size():
			continue
		if not state.seats[s].riichi.declared:
			continue
		var stick2 := _make_stick(true)
		var r: float = PLATE_HALF + 0.06
		match s:
			0: stick2.position = Vector3(0.1, 0.026, r)
			1: stick2.position = Vector3(r, 0.026, -0.1)
			2: stick2.position = Vector3(-0.1, 0.026, -r)
			3: stick2.position = Vector3(-r, 0.026, 0.1)
		stick2.rotation_degrees = Vector3(0, 90.0 if s % 2 == 1 else 0.0, 0)
		_riichi_stick_meshes.append(stick2)


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
	var show_ids: Array = sorted_ids + drawn_ids
	var n: int = show_ids.size()
	if n == 0:
		return
	var sc: float = HAND_SCALE
	var gap: float = (Tile3D.TILE_W + 0.006) * sc
	var drawn_gap: float = 0.04 * sc
	var total: float = n * gap + (drawn_gap if drawn_ids.size() > 0 and sorted_ids.size() > 0 else 0.0)
	var x0: float = -total * 0.5 + gap * 0.5
	# 近景倾牌：+Y 面朝向相机（HAND_TILT 为正）
	var y: float = Tile3D.TILE_D * 0.5 * sc + 0.01
	var z: float = HAND_Z
	var x_cursor: float = x0
	for i in range(n):
		var tid: int = int(show_ids[i])
		var is_red := false
		for t in seat.hand._tiles:
			if t.id == tid and t.is_red_dora:
				is_red = true
				break
		var is_drawn_slot: bool = drawn_ids.size() > 0 and i == sorted_ids.size() and sorted_ids.size() > 0
		if is_drawn_slot:
			x_cursor += drawn_gap
		var tile := Tile3D.new()
		_world_root.add_child(tile)
		tile.setup(tid, true, is_red)
		tile.scale = Vector3(sc, sc, sc)
		tile.set_base_position(Vector3(x_cursor, y, z))
		tile.rotation_degrees = Vector3(HAND_TILT_DEG, 0, 0)
		tile.set_clickable(_hand_clickable)
		tile.tile_clicked.connect(_on_tile_clicked)
		tile.tile_hover.connect(_on_tile_hover)
		if animate_draw and is_drawn_slot:
			tile.animate_draw_drop(0.18 * sc, 0.22)
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
	var cursor: Vector3
	var yaw: float = 0.0
	var along: Vector3
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
			var face: bool = true
			if m.kind == Meld.Kind.ANKAN and (j == 0 or j == 3):
				face = false
			tile.setup(tt.id, face, tt.is_red_dora)
			var pos: Vector3 = cursor + along * (j * gap)
			if m.kind == Meld.Kind.ADDED_KAN and j == 3:
				pos = cursor + along * (1.0 * gap) + Vector3(0, Tile3D.TILE_D + 0.002, 0)
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
		# 略偏王牌区左侧，避免与 dead wall 重叠
		tile.set_base_position(Vector3(-0.18 + i * (Tile3D.TILE_W + 0.006), y, -0.12))
		tile.rotation_degrees = Vector3(0, 0, 0)
		_dora_tiles.append(tile)
		i += 1


func _on_tile_clicked(tile_id: int) -> void:
	if _hand_clickable:
		player_card_clicked.emit(tile_id)


func _on_tile_hover(tile_id: int, entered: bool) -> void:
	hand_tile_hover.emit(tile_id, entered)
