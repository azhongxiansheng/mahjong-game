class_name MahjongTable3D extends Control

const Table3DStage := preload(
	"res://ui/four_player_table/table3d/table_3d_stage.gd")
const PublicTableAdapter := preload(
	"res://ui/four_player_table/public_table_projection_adapter.gd")

# 雀魂式真 3D 牌桌（非假透视 2.5D）：
# - 桌/牌/河/副露：3D mesh + 透视相机（对齐雀魂 Unity 桌）
# - HUD 操作条仍在 2D Control 层（PlayableTable）
# - 自家手牌：近景放大立牌，保证可读可点

# E2-02 / #232：点击 = tile_instance_id；hover 仍 = tile_id
signal player_card_clicked(tile_instance_id: int)
signal hand_tile_hover(tile_id: int, entered: bool)
signal hand_interaction_state_changed(state: Dictionary)

enum RenderProfile { FULL_TABLE, TILE_OVERLAY }

const HAND_ACTIVATION_IMMEDIATE: StringName = &"immediate"
const HAND_ACTIVATION_CONFIRM_DISCARD: StringName = &"confirm_discard"

const TABLE_W: float = 2.4
const TABLE_D: float = 2.4
const TABLE_TOP_Y: float = Table3DStage.TABLE_TOP_Y
# 布局半径（由内到外）：中心盘 → 河 → 牌山示意 → 手牌
const PLATE_HALF: float = 0.16
const RIVER_INNER: float = 0.32
# 自家 24 张牌河必须完整避开上层中央盘与操作栏：适度外移并压缩网格。
const SELF_RIVER_INNER: float = 0.404
const SELF_RIVER_SCALE: float = 0.82
# 混合桌横向（初始东/西家）牌河按各自朝向做轻微镜像倾角；抬高中心点
# 抵消旋转后的垂直包围盒，既增强桌面贴合感也避免牌角穿入毡面。
const OVERLAY_HORIZONTAL_RIVER_PITCH_DEGREES: float = 7.0
const WALL_RADIUS: float = 0.70
const WALL_GAP: float = 0.080
const WALL_STACKS_PER_SIDE_MAX: int = 17
const WALL_STACK_COUNT: int = WALL_STACKS_PER_SIDE_MAX * 4
const SHOW_LIVE_WALL: bool = true
const SCORE_LABEL_R: float = 0.35
# 自家手牌相对桌面的放大（雀魂：手牌占屏底大特写）
const SELF_HAND_SCALE: float = 1.28
const OPPONENT_HAND_RADIUS: float = 0.97
const OPPONENT_HAND_SCALE: float = 0.88
const MELD_RADIUS: float = 0.815
const HAND_Z: float = 1.085

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
var _hand_activation_mode: StringName = HAND_ACTIVATION_IMMEDIATE
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
var _prev_wall_draw_index: int = -1
var _prev_rinshan_taken: int = -1
var _prev_wall: Wall = null
var _scores_override: Array = []
var _render_profile: RenderProfile = RenderProfile.FULL_TABLE
var _tile_registry: Dictionary = {}
var _desired_tile_keys: Dictionary = {}
var _reconcile_active: bool = false
var _hands_visible: bool = true
var _hand_dim_active: bool = false
var _hand_dim_allowed_instances: Array = []
var _selected_hand_instance_ids: Array = []
var _revealed_seats: Dictionary = {}
var _pending_reveal_animation_seats: Dictionary = {}
var _win_tile_ids_by_seat: Dictionary = {}
var _current_dora_ids: Array = []


## 必须在 add_child 前调用；ready 后切 profile 会留下不一致的 3D world。
func configure_tile_overlay() -> void:
	if is_inside_tree() or _world_root != null:
		return
	_render_profile = RenderProfile.TILE_OVERLAY


func is_tile_overlay() -> bool:
	return _render_profile == RenderProfile.TILE_OVERLAY


## 牌层只有在节点 ready 且 viewport/world/camera 全部建立后才可接管 2D 实体。
## _ready 中途失败时这些引用不会同时成立，调用方据此保持 2D 回退。
func is_renderer_ready() -> bool:
	return is_inside_tree() and is_node_ready() \
		and _vp_host != null and is_instance_valid(_vp_host) \
		and _vp != null and is_instance_valid(_vp) \
		and _world_root != null and is_instance_valid(_world_root) \
		and _camera != null and is_instance_valid(_camera)


func uses_native_tile_animations() -> bool:
	return true


func _ready() -> void:
	custom_minimum_size = Vector2(TableLayout.TABLE_W, TableLayout.TABLE_H)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_PASS if is_tile_overlay() \
		else Control.MOUSE_FILTER_STOP
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
	_vp.transparent_bg = is_tile_overlay()
	_vp_host.add_child(_vp)

	_world_root = Node3D.new()
	_world_root.name = "World"
	_vp.add_child(_world_root)

	var stage: Dictionary = Table3DStage.build_tile_overlay(_world_root) \
		if is_tile_overlay() else Table3DStage.build(_world_root)
	_camera = stage["camera"] as Camera3D
	set_camera_view(&"main")
	if is_tile_overlay():
		return

	# 共享牌山 / 立直棒 mesh
	_wall_mesh = BoxMesh.new()
	_wall_mesh.size = Vector3(Tile3D.TILE_W, Tile3D.APPROVED_TILE_D, Tile3D.TILE_H)
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

	_center_plate = _world_root.get_node("CenterPlate") as MeshInstance3D

	_center_label = Label3D.new()
	_center_label.text = "东1"
	_center_label.font_size = 18
	_center_label.pixel_size = 0.0032
	_center_label.modulate = Color(0.98, 0.88, 0.45)
	_center_label.position = Vector3(0, 0.036, 0)
	_center_label.rotation_degrees = Vector3(-90, 0, 0)
	_center_label.outline_size = 6
	_center_label.outline_modulate = Color(0, 0, 0, 0.92)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_world_root.add_child(_center_label)

	# 四方分紧贴物理中央盘，形成局风/庄家/点数的单一空间锚点。
	_center_side_labels.clear()
	for s in range(4):
		var lab := Label3D.new()
		lab.font_size = 14
		lab.pixel_size = 0.0028
		lab.modulate = Color(0.95, 0.92, 0.8)
		lab.outline_size = 4
		lab.outline_modulate = Color(0, 0, 0, 0.92)
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



func set_camera_view(view_name: StringName) -> bool:
	return Table3DStage.set_camera_view(_camera, view_name)


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
	# 河外侧固定点，不进盘心
	var r: float = SCORE_LABEL_R
	match seat_id:
		0: return Vector3(0, 0.028, r)
		1: return Vector3(r, 0.028, 0)
		2: return Vector3(0, 0.028, -r)
		3: return Vector3(-r, 0.028, 0)
	return Vector3.ZERO


# ---- API ----

func bind_battle_state(state: BattleState, hand_index: int = 0, _hpr: int = 4) -> void:
	_state = state
	if state == null:
		return
	if not is_tile_overlay():
		_update_center_info(state, hand_index)
		_update_active_seat(state.current_seat)
	_begin_tile_reconcile()
	var hand_n: int = state.seats[0].hand.size()
	var animate_draw: bool = _prev_hand_count >= 0 and hand_n == _prev_hand_count + 1
	_rebuild_player_hand(state.seats[0], animate_draw, state.seats[0].melds.all())
	_prev_hand_count = hand_n
	for s in range(4):
		var river: Array = state.seats[s].river.tiles()
		var animate_disc: bool = _prev_river_count[s] >= 0 and river.size() == _prev_river_count[s] + 1
		_rebuild_river(s, river, state.seats[s].river.riichi_discard_index(), animate_disc)
		_prev_river_count[s] = river.size()
	for s in range(1, 4):
		_rebuild_opponent_backs(s, state.seats[s], state.seats[s].melds.all(),
			s, _revealed_seats.has(s), state.seats[s].last_drawn_instance_id,
			-1, false, _pending_reveal_animation_seats.has(s), false,
			_revealed_seats.has(s))
		_pending_reveal_animation_seats.erase(s)
	for s in range(4):
		var concealed_count: int = state.seats[s].hand.size()
		var has_drawn: bool = Tile.is_valid_instance_id(
			state.seats[s].last_drawn_instance_id)
		var hand_extent := _hand_world_extent(s, concealed_count, has_drawn)
		_rebuild_melds(s, state.seats[s].melds.all(), s, hand_extent)
	_finish_tile_reconcile()
	_apply_win_tile_markers()
	_current_dora_ids = _dora_ids_from_indicators(
		state.dora_indicators.visible_tiles() if state.dora_indicators else [])
	_apply_tile_dora_ids(_current_dora_ids)
	if not is_tile_overlay():
		_rebuild_dora(state)
	var wall_n: int = state.wall.live_wall_size() if state.wall else 0
	var wall_draw_index: int = state.wall.draw_index() if state.wall else -1
	var rinshan_taken: int = state.wall.rinshan_taken() if state.wall else -1
	# 只在权威牌墙游标变化时重建；固定槽位不会随剩余张数重新居中。
	if not is_tile_overlay() and (state.wall != _prev_wall or wall_n != _prev_wall_count \
			or wall_draw_index != _prev_wall_draw_index \
			or rinshan_taken != _prev_rinshan_taken):
		_rebuild_live_wall(state)
		_rebuild_dead_wall(state)
		_prev_wall_count = wall_n
		_prev_wall_draw_index = wall_draw_index
		_prev_rinshan_taken = rinshan_taken
		_prev_wall = state.wall
	if not is_tile_overlay():
		_rebuild_riichi_sticks(state)


## 公共桌直接消费 renderer-neutral 视图；不构造 BattleState。
func bind_core_table_view(core: Dictionary) -> void:
	var view: Dictionary = PublicTableAdapter.renderer_view(core)
	if view.is_empty():
		return
	_state = null
	_begin_tile_reconcile()
	var seats: Array = view.get("seats", [])
	for seat_view_value in seats:
		if typeof(seat_view_value) != TYPE_DICTIONARY:
			continue
		var seat_view := seat_view_value as Dictionary
		var screen_seat: int = int(seat_view.get("screen_seat", -1))
		if screen_seat < 0 or screen_seat > 3:
			continue
		var melds: Array = seat_view.get("melds", [])
		var concealed_count: int = int(seat_view.get("concealed_count", 0))
		var last_drawn: int = int(seat_view.get(
			"last_drawn_tile_instance_id", Tile.INVALID_INSTANCE_ID))
		var has_drawn: bool = bool(seat_view.get("has_drawn", false))
		var concealed_tiles := seat_view.get("concealed_tiles", []) as Array
		if screen_seat == 0:
			var animate_draw := _prev_hand_count >= 0 \
				and concealed_count == _prev_hand_count + 1
			_rebuild_player_hand_tiles(
				concealed_tiles, last_drawn, animate_draw, melds,
				int(seat_view.get("absolute_seat", 0)))
			_prev_hand_count = concealed_count
		else:
			_rebuild_opponent_backs(screen_seat, concealed_tiles, melds,
				int(seat_view.get("absolute_seat", screen_seat)),
				not concealed_tiles.is_empty(), Tile.INVALID_INSTANCE_ID,
				concealed_count, has_drawn, not concealed_tiles.is_empty(), true)
		var river := seat_view.get("river", []) as Array
		var animate_discard: bool = int(_prev_river_count[screen_seat]) >= 0 \
			and river.size() == int(_prev_river_count[screen_seat]) + 1
		_rebuild_river(screen_seat, seat_view.get("river", []) as Array,
			int(seat_view.get("riichi_discard_index", -1)), animate_discard)
		_prev_river_count[screen_seat] = river.size()
		var hand_extent := _hand_world_extent(screen_seat, concealed_count,
			has_drawn)
		_rebuild_melds(screen_seat, melds,
			int(seat_view.get("layout_claimant_absolute", screen_seat)), hand_extent)
	_finish_tile_reconcile()
	_apply_win_tile_markers()
	_current_dora_ids = (view.get("dora_ids", []) as Array).duplicate()
	_apply_tile_dora_ids(_current_dora_ids)


func bind_cumulative_scores(scores: Array) -> void:
	_scores_override = scores.duplicate() if scores != null else []
	if _state != null:
		_update_center_info(_state, maxi(_state.hand_number - 1, 0))


func highlight_tile_id(tile_id: int) -> void:
	for tile in _all_entity_tiles():
		(tile as Tile3D).set_hover_match((tile as Tile3D).tile_id == tile_id)


func clear_tile_highlight() -> void:
	for tile in _all_entity_tiles():
		(tile as Tile3D).set_hover_match(false)


func set_hand_clickable(b: bool) -> void:
	_hand_clickable = b
	if not b:
		_selected_hand_instance_ids.clear()
	for t in _hand_tiles:
		if t is Tile3D:
			(t as Tile3D).set_clickable(b)
			if not b:
				(t as Tile3D).set_selected(false)
	hand_interaction_state_changed.emit(get_hand_interaction_state())


func set_hand_activation_mode(mode: StringName) -> void:
	var normalized := HAND_ACTIVATION_CONFIRM_DISCARD \
		if mode == HAND_ACTIVATION_CONFIRM_DISCARD else HAND_ACTIVATION_IMMEDIATE
	if _hand_activation_mode == normalized:
		return
	_hand_activation_mode = normalized
	set_selected_instances([])


func dim_hand_except(allowed: Array) -> void:
	# allowed = tile_instance_id 列表
	_hand_dim_active = true
	_hand_dim_allowed_instances = allowed.duplicate()
	for t in _hand_tiles:
		if t is Tile3D:
			var iid: int = (t as Tile3D).tile_instance_id
			var ok := false
			for a in allowed:
				if int(a) == iid:
					ok = true
					break
			(t as Tile3D).set_dim(not ok)
	hand_interaction_state_changed.emit(get_hand_interaction_state())


func clear_hand_dim() -> void:
	_hand_dim_active = false
	_hand_dim_allowed_instances.clear()
	for t in _hand_tiles:
		if t is Tile3D:
			(t as Tile3D).set_dim(false)
	hand_interaction_state_changed.emit(get_hand_interaction_state())


func set_selected_instances(instance_ids: Array) -> void:
	_selected_hand_instance_ids = instance_ids.duplicate()
	for tile in _hand_tiles:
		if tile is Tile3D:
			(tile as Tile3D).set_selected(instance_ids.has(
				(tile as Tile3D).tile_instance_id))
	hand_interaction_state_changed.emit(get_hand_interaction_state())


func get_hand_interaction_state() -> Dictionary:
	return {
		"clickable": _hand_clickable,
		"activation_mode": _hand_activation_mode,
		"dim_active": _hand_dim_active,
		"dim_allowed_instances": _hand_dim_allowed_instances.duplicate(),
		"selected_instances": _selected_hand_instance_ids.duplicate(),
	}


func apply_hand_interaction_state(state: Dictionary) -> void:
	set_hand_activation_mode(StringName(state.get(
		"activation_mode", HAND_ACTIVATION_IMMEDIATE)))
	set_hand_clickable(bool(state.get("clickable", false)))
	if bool(state.get("dim_active", false)):
		dim_hand_except(state.get("dim_allowed_instances", []) as Array)
	else:
		clear_hand_dim()
	set_selected_instances(state.get("selected_instances", []) as Array)


func mark_win_tile(tile_id: int, seat_id: int = 0) -> void:
	mark_seat_win_tile(seat_id, tile_id)


func mark_seat_win_tile(seat_id: int, tile_id: int) -> void:
	if seat_id < 0 or seat_id > 3 or tile_id < 0:
		return
	_win_tile_ids_by_seat[seat_id] = tile_id
	_apply_win_tile_markers()


func _tiles_for_hand_seat(seat_id: int) -> Array:
	return _hand_tiles if seat_id == 0 else _opp_tiles[seat_id]


func _apply_win_tile_markers() -> void:
	for seat_id in range(4):
		var marked := false
		var target_id := int(_win_tile_ids_by_seat.get(seat_id, -1))
		for tile in _tiles_for_hand_seat(seat_id):
			if not (tile is Tile3D):
				continue
			var should_mark := not marked and target_id >= 0 \
				and (tile as Tile3D).tile_id == target_id
			(tile as Tile3D).set_win_tile(should_mark)
			marked = marked or should_mark


func clear_hand_reveal() -> void:
	clear_all_hand_reveals()


func reveal_hand_face_up(hand, animate: bool = true) -> void:
	reveal_seat_hand_face_up(0, hand, animate)


func reveal_seat_hand_face_up(seat_id: int, hand: Hand,
		animate: bool = true) -> void:
	if seat_id < 0 or seat_id > 3 or hand == null:
		return
	_revealed_seats[seat_id] = hand
	if animate:
		_pending_reveal_animation_seats[seat_id] = true
	if _state != null:
		bind_battle_state(_state, maxi(_state.hand_number - 1, 0), 4)


func clear_all_hand_reveals() -> void:
	_revealed_seats.clear()
	_pending_reveal_animation_seats.clear()
	_win_tile_ids_by_seat.clear()
	_apply_win_tile_markers()
	if _state != null:
		bind_battle_state(_state, maxi(_state.hand_number - 1, 0), 4)


func set_hands_visible(hands_visible: bool) -> void:
	_hands_visible = hands_visible
	for tile in _hand_tiles:
		if tile is CanvasItem:
			(tile as CanvasItem).visible = hands_visible
		elif tile is Node3D:
			(tile as Node3D).visible = hands_visible
	for seat_id in range(1, 4):
		for tile in _opp_tiles[seat_id]:
			if tile is Node3D:
				(tile as Node3D).visible = hands_visible


func set_emote(_s: String) -> void:
	pass


func say(_t: String) -> void:
	pass


func get_portrait_texture() -> Texture2D:
	return null


# 飞牌定位：参数语义 = tile_instance_id；找不到返回 ZERO（禁止 tile_id fallback）
# 非法 instance（尤其 INVALID=-1）立即 ZERO，避免纯展示 Tile3D 被误定位。
func get_hand_slot_global_center(tile_instance_id: int) -> Vector2:
	return get_hand_tile_render_info(tile_instance_id).get(
		"screen_center", Vector2.ZERO)


func get_hand_tile_render_info(tile_instance_id: int) -> Dictionary:
	if not Tile.is_valid_instance_id(tile_instance_id):
		return {}
	for n in _hand_tiles:
		if not (n is Tile3D):
			continue
		var t3d := n as Tile3D
		if t3d.tile_instance_id != tile_instance_id:
			continue
		return {
			"tile_instance_id": tile_instance_id,
			"tile_id": t3d.tile_id,
			"is_red_dora": t3d.is_red_dora,
			"screen_center": _tile_global_screen_center(t3d),
		}
	return {}


func get_river_last_global_center(seat_id: int) -> Vector2:
	if seat_id < 0 or seat_id >= _river_tiles.size() \
			or _river_tiles[seat_id].is_empty():
		return Vector2.ZERO
	return _tile_global_screen_center(_river_tiles[seat_id][-1] as Tile3D)


func _tile_global_screen_center(tile: Tile3D) -> Vector2:
	if tile == null:
		return Vector2.ZERO
	if _camera != null and _vp != null and _vp.size.x > 0 and _vp.size.y > 0:
		var vp_point: Vector2 = _camera.unproject_position(tile.global_position)
		var scale_x: float = size.x / float(_vp.size.x)
		var scale_y: float = size.y / float(_vp.size.y)
		return global_position + Vector2(vp_point.x * scale_x, vp_point.y * scale_y)
	return global_position + (size * 0.5 if size != Vector2.ZERO else Vector2.ONE)


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


func _begin_tile_reconcile() -> void:
	_desired_tile_keys.clear()
	_reconcile_active = true


func _finish_tile_reconcile() -> void:
	for key in _tile_registry.keys():
		if _desired_tile_keys.has(key):
			continue
		var stale = _tile_registry[key]
		if stale is Node and is_instance_valid(stale):
			(stale as Node).queue_free()
		_tile_registry.erase(key)
	_reconcile_active = false


func _obtain_tile(key: String) -> Tile3D:
	_desired_tile_keys[key] = true
	var tile := _tile_registry.get(key, null) as Tile3D
	if tile == null or not is_instance_valid(tile):
		tile = Tile3D.new()
		_world_root.add_child(tile)
		_tile_registry[key] = tile
	tile.set_meta("renderer_key", key)
	return tile


func _entity_key(region: String, seat_id: int, instance_id: int,
		slot_index: int, stable_owner: int = -1,
		force_occurrence: bool = false) -> String:
	if Tile.is_valid_instance_id(instance_id) and not force_occurrence:
		return "entity:%d" % instance_id
	var owner := stable_owner if stable_owner >= 0 else seat_id
	return "%s:%d:slot:%d" % [region, owner, slot_index]


func _prepare_tile(tile: Tile3D, tile_id: int, face_up: bool, red: bool,
		instance_id: int) -> void:
	tile.set_geometry_depth(Tile3D.APPROVED_TILE_D)
	# registry 会跨手牌、牌河与副露复用同一实体；区域布局应用目标 scale 前
	# 先归一化，避免鸣牌继承 1.28 手牌或 0.82 自家牌河的旧尺寸。
	tile.scale = Vector3.ONE
	if Tile.is_valid_instance_id(instance_id):
		tile.setup_entity(tile_id, face_up, red, instance_id)
	else:
		tile.setup(tile_id, face_up, red)
	tile.set_latest_discard(false)
	tile.set_win_tile(false)
	tile.set_hover_match(false)
	tile.set_dora(_current_dora_ids.has(tile_id))


func _all_entity_tiles() -> Array:
	var output: Array = []
	for value in _tile_registry.values():
		if value is Tile3D and is_instance_valid(value):
			output.append(value)
	return output


func _dora_ids_from_indicators(indicators: Array) -> Array:
	var result: Array = []
	for indicator in indicators:
		if indicator is Tile:
			result.append(DoraIndicator.dora_from_indicator((indicator as Tile).id))
	return result


func _apply_tile_dora_ids(dora_ids: Array) -> void:
	for tile in _all_entity_tiles():
		(tile as Tile3D).set_dora(dora_ids.has((tile as Tile3D).tile_id))


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
	# #375：权威分 BattleState.scores
	if state != null and seat_id < state.scores.size():
		return int(state.scores[seat_id])
	if state != null and state.seats.size() > seat_id:
		return int(state.seats[seat_id].points)
	return 25000


func _update_center_info(state: BattleState, hand_index: int) -> void:
	if _center_label == null:
		return
	var wall_n: int = state.wall.live_wall_size() if state.wall else 0
	var hn: int = state.hand_number if state.hand_number > 0 else hand_index + 1
	# 盘心只留极短两行；四方分在 SCORE_LABEL_R
	_center_label.text = "%s%d局\n本%d 余%d" % [
		_round_wind_char(state.round_wind), hn, state.honba, wall_n
	]
	for s in range(4):
		if s >= _center_side_labels.size() or s >= state.seats.size():
			continue
		var seat: Seat = state.seats[s]
		var lab: Label3D = _center_side_labels[s]
		var mark: String = "●" if s == state.current_seat else ""
		lab.text = "%s%s\n%d" % [mark, _wind_char(seat.seat_wind), _seat_points(state, s)]
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


func _make_wall_piece(source: Tile) -> Tile3D:
	var tile := Tile3D.new()
	tile.set_geometry_depth(Tile3D.APPROVED_TILE_D)
	tile.setup_entity(source.id, false, source.is_red_dora, source.instance_id)
	_world_root.add_child(tile)
	return tile


func _rebuild_live_wall(state: BattleState) -> void:
	_free_arr(_wall_tiles)
	if not SHOW_LIVE_WALL or state == null or state.wall == null or _wall_mesh == null:
		return
	# 68 墩只是固定物理容量。每张权威牌的绝对 Wall index 唯一映射到
	# slot/layer；发牌、摸牌与岭上只留下 draw order 缺口，绝不重排剩余牌。
	var authority_tiles: Array[Tile] = state.wall.authority_tiles()
	var visible_end: int = authority_tiles.size() - state.wall.rinshan_taken()
	var live_end: int = state.wall.live_end_index()
	var y0: float = TABLE_TOP_Y + Tile3D.APPROVED_TILE_D * 0.5
	for physical_index in range(state.wall.draw_index(), visible_end):
		var slot: int = physical_index / 2
		var layer: int = physical_index % 2
		var seat_id: int = slot / WALL_STACKS_PER_SIDE_MAX
		var local_index: int = slot % WALL_STACKS_PER_SIDE_MAX
		var t_along: float = (local_index - 8) * WALL_GAP
		var mi := _make_wall_piece(authority_tiles[physical_index])
		var pos: Vector3
		var yaw: float = 0.0
		match seat_id:
			0:
				pos = Vector3(t_along, y0 + layer * Tile3D.APPROVED_TILE_D, WALL_RADIUS)
				yaw = 0.0
			1:
				pos = Vector3(WALL_RADIUS, y0 + layer * Tile3D.APPROVED_TILE_D, -t_along)
				yaw = -90.0
			2:
				pos = Vector3(-t_along, y0 + layer * Tile3D.APPROVED_TILE_D, -WALL_RADIUS)
				yaw = 180.0
			3:
				pos = Vector3(-WALL_RADIUS, y0 + layer * Tile3D.APPROVED_TILE_D, t_along)
				yaw = 90.0
		mi.position = pos
		mi.rotation_degrees = Vector3(0, yaw, 0)
		mi.set_meta("wall_slot", slot)
		mi.set_meta("wall_layer", layer)
		mi.set_meta("wall_dead", physical_index >= live_end)
		_wall_tiles.append(mi)


func _rebuild_dead_wall(_state: BattleState) -> void:
	_free_arr(_dead_wall_tiles)
	# 王牌保留在外围固定牌山最后七墩，不再建立中央浮动短墙。


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


func _hand_world_extent(seat_id: int, count: int,
		has_drawn: bool = false) -> float:
	if count <= 0:
		return 0.0
	var scale_ := SELF_HAND_SCALE if seat_id == 0 else OPPONENT_HAND_SCALE
	var gap := (Tile3D.TILE_W + 0.004) * scale_
	var drawn_gap := 0.028 * scale_ if has_drawn and count > 1 else 0.0
	return Tile3D.TILE_W * scale_ + maxi(count - 1, 0) * gap + drawn_gap


func _meld_slots_extent(slots: Array) -> float:
	var extent := 0.0
	var count_on_axis := 0
	for slot_value in slots:
		var slot := slot_value as Dictionary
		if bool(slot.get("stacked_above", false)):
			continue
		extent += Tile3D.TILE_H if bool(slot.get("rotated", false)) \
			else Tile3D.TILE_W
		count_on_axis += 1
	return extent + maxi(count_on_axis - 1, 0) * 0.004


func _meld_world_extent(melds: Array, claimant: int) -> float:
	var extents: Array[float] = []
	for meld_value in melds:
		if meld_value is Meld:
			extents.append(_meld_slots_extent(
				MeldLayout.compute(meld_value as Meld, claimant)))
	var total := 0.0
	for extent in extents:
		total += extent
	return total + maxi(extents.size() - 1, 0) * 0.028


func _added_tile_for_meld(meld: Meld) -> Tile:
	if meld == null or meld.kind != Meld.Kind.ADDED_KAN \
			or not Tile.is_valid_instance_id(meld.added_tile_instance_id):
		return null
	for tile in meld.tiles:
		if tile != null and tile.instance_id == meld.added_tile_instance_id:
			return tile
	return null


func _hand_meld_center_offsets(seat_id: int, hand_extent: float,
		meld_extent: float) -> Dictionary:
	# TableLayout 使用 1600px raw stage 单位；3D 使用 2.4m 桌面单位。
	# 双向换算可复用同一 flex 顺序/gap，而不把 12px 误当成 12m。
	var units_per_world := TableLayout.TABLE_W / Table3DStage.TABLE_SIZE.x
	var layout_hand_extent := hand_extent * units_per_world
	var layout_meld_extent := meld_extent * units_per_world
	# 侧家手牌直立、其副露平放；透视投影后的 AABB 会沿主轴额外伸出。
	# 把一张牌高作为 flex 内的透明净空，并加在靠前盒子的尾端：既保留
	# TableLayout 的自身右侧顺序，也让实际 hand/meld 外沿仍围绕同一中心。
	if meld_extent > 0.0 and (seat_id == 1 or seat_id == 3):
		var projection_clearance := (Tile3D.TILE_H
			+ Tile3D.APPROVED_TILE_D * 0.5) * units_per_world
		if seat_id == 1:
			layout_meld_extent += projection_clearance
		else:
			layout_hand_extent += projection_clearance
	var flex := TableLayout.hand_meld_flex_layout(
		seat_id, layout_hand_extent, layout_meld_extent)
	var center := float(flex["combined_center"])
	return {
		"hand_center": (float(flex["hand_start"])
			+ hand_extent * units_per_world * 0.5 - center) / units_per_world,
		"meld_center": (float(flex["meld_start"])
			+ meld_extent * units_per_world * 0.5 - center) / units_per_world,
	}


## TableLayout 的 main axis：seat1/2 通过反序保证最终落在自身右侧。
func _layout_axis(seat_id: int) -> Vector3:
	match seat_id:
		0, 2: return Vector3.RIGHT
		1, 3: return Vector3.BACK
	return Vector3.RIGHT


func _rebuild_player_hand(seat: Seat, animate_draw: bool = false,
		melds: Array = []) -> void:
	if seat == null or seat.hand == null:
		_hand_tiles.clear()
		return
	_rebuild_player_hand_tiles(seat.hand.tiles(), seat.last_drawn_instance_id,
		animate_draw, melds, seat.seat_id)


func _rebuild_player_hand_tiles(source_tiles: Array, drawn_iid: int,
		animate_draw: bool, melds: Array, stable_owner: int) -> void:
	var own_reconcile := not _reconcile_active
	if own_reconcile:
		_begin_tile_reconcile()
	_hand_tiles.clear()
	# 排序键=(tile_id, original_index)，同值普通/赤牌禁止用 instance_id 改序。
	var sorted_entries: Array = []
	var drawn_tiles: Array = []
	var found_drawn := false
	for index in range(source_tiles.size()):
		var source := source_tiles[index] as Tile
		if source == null:
			continue
		if Tile.is_valid_instance_id(drawn_iid) \
				and source.instance_id == drawn_iid and not found_drawn:
			drawn_tiles.append(source)
			found_drawn = true
		else:
			sorted_entries.append({"tile": source, "original_index": index})
	if Tile.is_valid_instance_id(drawn_iid) and not found_drawn:
		sorted_entries.clear()
		drawn_tiles.clear()
		for index in range(source_tiles.size()):
			if source_tiles[index] is Tile:
				sorted_entries.append({
					"tile": source_tiles[index], "original_index": index})
	sorted_entries.sort_custom(func(a, b) -> bool:
		var first: Tile = a["tile"]
		var second: Tile = b["tile"]
		if first.id != second.id:
			return first.id < second.id
		return int(a["original_index"]) < int(b["original_index"]))
	var sorted_tiles: Array = []
	for entry in sorted_entries:
		sorted_tiles.append(entry["tile"])
	var show_tiles: Array = sorted_tiles + drawn_tiles
	if show_tiles.is_empty():
		if own_reconcile:
			_finish_tile_reconcile()
		return
	var has_drawn := not drawn_tiles.is_empty() and not sorted_tiles.is_empty()
	var hand_extent := _hand_world_extent(0, show_tiles.size(), has_drawn)
	var meld_extent := _meld_world_extent(melds, 0)
	var centers := _hand_meld_center_offsets(0, hand_extent, meld_extent)
	var y: float = TABLE_TOP_Y + Tile3D.TILE_H * 0.5
	var base_center := Vector3(0, y, HAND_Z) \
		+ _layout_axis(0) * float(centers["hand_center"])
	var player_basis := _player_hand_basis(base_center)
	var gap: float = (Tile3D.TILE_W + 0.004) * SELF_HAND_SCALE
	var drawn_gap: float = 0.028 * SELF_HAND_SCALE
	var offsets: Array[float] = []
	var cursor := 0.0
	for index in range(show_tiles.size()):
		if has_drawn and index == sorted_tiles.size():
			cursor += drawn_gap
		offsets.append(cursor)
		cursor += gap
	var offsets_center := (offsets[0] + offsets[-1]) * 0.5
	for index in range(show_tiles.size()):
		var source := show_tiles[index] as Tile
		var key := _entity_key("hand", 0, source.instance_id, index, stable_owner)
		var existed := _tile_registry.has(key)
		var tile := _obtain_tile(key)
		_prepare_tile(tile, source.id, true, source.is_red_dora, source.instance_id)
		tile.set_meta("render_region", "hand")
		tile.transform = Transform3D(
			player_basis.scaled(Vector3.ONE * SELF_HAND_SCALE),
			base_center + player_basis.x.normalized() \
				* (offsets[index] - offsets_center))
		# transform 重排会重置 position；用统一 base setter 恢复既有选中抬牌。
		tile.set_base_position(tile.position)
		tile.visible = _hands_visible
		tile.set_clickable(_hand_clickable)
		tile.set_dim(_hand_dim_active and not _hand_dim_allowed_instances.has(
			source.instance_id))
		tile.set_selected(_selected_hand_instance_ids.has(source.instance_id))
		if not tile.tile_clicked.is_connected(_on_tile_clicked):
			tile.tile_clicked.connect(_on_tile_clicked)
		if not tile.tile_flicked.is_connected(_on_tile_flicked):
			tile.tile_flicked.connect(_on_tile_flicked)
		if not tile.tile_hover.is_connected(_on_tile_hover):
			tile.tile_hover.connect(_on_tile_hover)
		if animate_draw and not existed and has_drawn \
				and index == sorted_tiles.size():
			tile.animate_draw_drop(0.12, 0.22)
		_hand_tiles.append(tile)
	if own_reconcile:
		_finish_tile_reconcile()


func _rebuild_river(seat_id: int, tiles: Array, riichi_idx: int, animate_last: bool = false) -> void:
	var own_reconcile := not _reconcile_active
	if own_reconcile:
		_begin_tile_reconcile()
	_river_tiles[seat_id].clear()
	var visible_count: int = mini(tiles.size(), 24) if tiles != null else 0
	var last_i: int = visible_count - 1
	for i in range(visible_count):
		var t = tiles[i]
		if t == null:
			continue
		var tid: int = t.id if t is Tile else int(t)
		var is_red: bool = (t is Tile and t.is_red_dora)
		var iid: int = (t as Tile).instance_id if t is Tile \
			else Tile.INVALID_INSTANCE_ID
		var key := _entity_key("river", seat_id, iid, i)
		var existed := _tile_registry.has(key)
		var tile := _obtain_tile(key)
		if t is Tile:
			_prepare_tile(tile, tid, true, is_red, iid)
		else:
			_prepare_tile(tile, tid, true, is_red, Tile.INVALID_INSTANCE_ID)
		tile.set_clickable(false)
		tile.set_selected(false)
		tile.set_dim(false)
		var col: int = i % 6
		var row: int = int(i / 6.0)
		var is_riichi := i == riichi_idx and riichi_idx >= 0
		var riichi_col := riichi_idx % 6 \
			if riichi_idx >= 0 and int(riichi_idx / 6.0) == row else -1
		var lr: Dictionary = _river_pose(
			seat_id, col, row, is_riichi, riichi_col)
		tile.scale = Vector3.ONE * float(lr.get("scale", 1.0))
		if animate_last and i == last_i:
			if not existed:
				var from: Vector3 = lr.pos + _seat_in_dir(seat_id) * 0.35 \
					+ Vector3(0, 0.12, 0)
				tile.position = from
				tile.rotation_degrees = lr.rot + Vector3(-40, 0, 0)
			tile.animate_to(lr.pos, lr.rot, 0.2)
			tile._base_y = lr.pos.y
			tile.set_meta("last_native_animation", "discard")
		else:
			tile.set_base_position(lr.pos)
			tile.rotation_degrees = lr.rot
		tile.set_latest_discard(i == last_i)
		tile.set_meta("render_region", "river")
		_river_tiles[seat_id].append(tile)
	if own_reconcile:
		_finish_tile_reconcile()


func _seat_in_dir(seat_id: int) -> Vector3:
	match seat_id:
		0: return Vector3(0, 0, 1)
		1: return Vector3(1, 0, 0)
		2: return Vector3(0, 0, -1)
		3: return Vector3(-1, 0, 0)
	return Vector3.ZERO


func _river_pose(seat_id: int, col: int, row: int, riichi: bool,
		riichi_col: int = -1) -> Dictionary:
	# 6 列；row 0 靠中心，向外涨，不压中心盘
	var use_player_overlay_safe_band := seat_id == 0 and is_tile_overlay()
	var tile_scale := SELF_RIVER_SCALE if use_player_overlay_safe_band else 1.0
	var gz: float = (Tile3D.TILE_H + 0.004) * tile_scale
	var y: float = TABLE_TOP_Y + Tile3D.APPROVED_TILE_D * 0.5
	var dx := _river_row_center_offset(col, tile_scale, riichi_col)
	var inner := SELF_RIVER_INNER if use_player_overlay_safe_band else RIVER_INNER
	var outward: float = inner + row * gz
	var pos: Vector3
	var yaw := 0.0
	var pitch := 0.0
	match seat_id:
		0:  # 自家：+Z
			pos = Vector3(dx, y, outward)
			if is_tile_overlay():
				pitch = OVERLAY_HORIZONTAL_RIVER_PITCH_DEGREES
		1:  # 右：+X
			pos = Vector3(outward, y, -dx)
			yaw = -90.0
		2:  # 对家：-Z
			pos = Vector3(-dx, y, -outward)
			yaw = 180.0
			if is_tile_overlay():
				pitch = -OVERLAY_HORIZONTAL_RIVER_PITCH_DEGREES
		3:  # 左：-X
			pos = Vector3(-outward, y, dx)
			yaw = 90.0
		_:
			pos = Vector3(dx, y, outward)
	if riichi:
		yaw += 90.0
	# 先建立整行共享的桌面倾斜，再在这个倾斜平面内旋转牌面朝向。
	# 直接写 Vector3(pitch, yaw, 0) 会按默认欧拉顺序让 yaw 旋转法线，
	# 因而只有立直横牌翘离桌面。
	var surface_basis := Basis(Vector3.RIGHT, deg_to_rad(pitch)) \
		* Basis(Vector3.UP, deg_to_rad(yaw))
	var rot := surface_basis.get_euler()
	rot = Vector3(rad_to_deg(rot.x), rad_to_deg(rot.y), rad_to_deg(rot.z))
	if not is_zero_approx(pitch):
		# 用最终 basis 的真实世界 Y 包围盒计算接触高度；普通牌、横牌和任意
		# 后续朝向都共用同一公式，不再猜测当前应取长边还是短边。
		var vertical_half := (
			absf(surface_basis.x.y) * Tile3D.TILE_W
			+ absf(surface_basis.y.y) * Tile3D.APPROVED_TILE_D
			+ absf(surface_basis.z.y) * Tile3D.TILE_H
		) * tile_scale * 0.5
		pos.y = TABLE_TOP_Y + vertical_half
	return {
		"pos": pos,
		"rot": rot,
		"basis": surface_basis,
		"yaw": yaw,
		"pitch": pitch,
		"scale": tile_scale,
	}


## 立直牌横置后沿河牌行方向占用 TILE_H，而普通牌只占 TILE_W。
## 整行按真实占宽重新居中，避免只旋转 mesh 导致左右各吃进相邻牌。
static func _river_row_center_offset(col: int, tile_scale: float,
		riichi_col: int = -1) -> float:
	assert(col >= 0 and col < 6)
	var gap := 0.004 * tile_scale
	var widths: Array[float] = []
	var total := gap * 5.0
	for index in range(6):
		var width := (Tile3D.TILE_H if index == riichi_col \
			else Tile3D.TILE_W) * tile_scale
		widths.append(width)
		total += width
	var cursor := -total * 0.5
	for index in range(6):
		var center := cursor + widths[index] * 0.5
		if index == col:
			return center
		cursor += widths[index] + gap
	return 0.0


func _hand_basis(seat_id: int) -> Basis:
	match seat_id:
		0: return Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
		1: return Basis(Vector3.FORWARD, Vector3.RIGHT, Vector3.DOWN)
		2: return Basis(Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN)
		3: return Basis(Vector3.BACK, Vector3.LEFT, Vector3.DOWN)
	return Basis.IDENTITY


## 混合桌的自家牌面正对主相机：保持牌宽水平，同时让牌面法线直接指向玩家。
## 完整 3D 实验桌继续使用围桌立牌姿态。
func _player_hand_basis(center: Vector3) -> Basis:
	if not is_tile_overlay() or _camera == null:
		return _hand_basis(0)
	var width_axis := Vector3.RIGHT
	var face_axis := _camera.global_position - center
	face_axis.x = 0.0
	if face_axis.length_squared() <= 0.000001:
		return _hand_basis(0)
	face_axis = face_axis.normalized()
	var down_axis := width_axis.cross(face_axis).normalized()
	return Basis(width_axis, face_axis, down_axis)


func _flat_hand_basis(seat_id: int) -> Basis:
	var x_axis := _hand_basis(seat_id).x.normalized()
	return Basis(x_axis, Vector3.UP, x_axis.cross(Vector3.UP).normalized())


func _rebuild_opponent_backs(seat_id: int, source: Variant,
		melds: Array = [], stable_owner: int = -1,
		reveal_face_up: bool = false,
		drawn_instance_id: int = Tile.INVALID_INSTANCE_ID,
		count_override: int = -1, has_drawn_override: bool = false,
		animate_reveal: bool = false, stable_slots: bool = false,
		lay_revealed_flat: bool = false) -> void:
	var own_reconcile := not _reconcile_active
	if own_reconcile:
		_begin_tile_reconcile()
	_opp_tiles[seat_id].clear()
	var source_tiles: Array = source.hand.tiles() if source is Seat \
		else (source as Array if typeof(source) == TYPE_ARRAY else [])
	var count: int = count_override if count_override >= 0 else (
		source.hand.size() if source is Seat else (
		source_tiles.size() if not source_tiles.is_empty() else int(source)))
	var n: int = clampi(count, 0, 14)
	if n == 0:
		if own_reconcile:
			_finish_tile_reconcile()
		return
	var gap: float = (Tile3D.TILE_W + 0.004) * OPPONENT_HAND_SCALE
	var use_flat_pose := reveal_face_up and lay_revealed_flat
	var y: float = TABLE_TOP_Y + (Tile3D.APPROVED_TILE_D * 0.5 \
		if use_flat_pose else Tile3D.TILE_H * 0.5)
	var drawn_index := -1
	if Tile.is_valid_instance_id(drawn_instance_id):
		for index in range(source_tiles.size()):
			if (source_tiles[index] as Tile).instance_id == drawn_instance_id:
				drawn_index = index
				break
	if drawn_index < 0 and has_drawn_override and n > 1:
		drawn_index = n - 1
	var has_drawn := drawn_index >= 0 and n > 1
	var hand_extent := _hand_world_extent(seat_id, n, has_drawn)
	var meld_extent := _meld_world_extent(melds, seat_id)
	var centers := _hand_meld_center_offsets(seat_id, hand_extent, meld_extent)
	var center := Table3DStage.rotate_from_south(
		Vector3(0, y, OPPONENT_HAND_RADIUS), seat_id) \
		+ _layout_axis(seat_id) * float(centers["hand_center"])
	var basis := (_flat_hand_basis(seat_id) if use_flat_pose \
		else _hand_basis(seat_id)).scaled(Vector3.ONE * OPPONENT_HAND_SCALE)
	var along := _hand_basis(seat_id).x.normalized()
	var offsets: Array[float] = []
	var offset_cursor := 0.0
	for index in range(n):
		if has_drawn and index == drawn_index:
			offset_cursor += 0.028 * OPPONENT_HAND_SCALE
		offsets.append(offset_cursor)
		offset_cursor += gap
	var offsets_center := (offsets[0] + offsets[-1]) * 0.5
	for i in range(n):
		var source_tile := source_tiles[i] as Tile if i < source_tiles.size() else null
		var iid: int = source_tile.instance_id if source_tile != null \
			else Tile.INVALID_INSTANCE_ID
		var key := _entity_key("hidden", seat_id,
			Tile.INVALID_INSTANCE_ID if stable_slots else iid, i, stable_owner)
		var existing := _tile_registry.get(key, null) as Tile3D
		var was_face_up := existing != null and existing.face_up \
			and existing.tile_id >= 0
		var tile := _obtain_tile(key)
		if reveal_face_up and source_tile != null:
			_prepare_tile(tile, source_tile.id, true,
				source_tile.is_red_dora, source_tile.instance_id)
		else:
			_prepare_tile(tile, -1, true, false, iid)
		var t: float = offsets[i] - offsets_center
		# t 已按 OPPONENT_HAND_SCALE 换算；basis 只负责 mesh 尺寸，位移轴
		# 必须归一化，避免暗手中心步距被重复缩放。
		tile.transform = Transform3D(basis, center + along * t)
		tile._base_y = y
		tile.visible = _hands_visible
		tile.set_clickable(false)
		tile.set_selected(false)
		tile.set_dim(false)
		tile.set_meta("render_region", "hand")
		if animate_reveal and reveal_face_up and source_tile != null \
				and not was_face_up:
			tile.animate_draw_drop(0.07 + minf(float(i), 6.0) * 0.004, 0.2)
		_opp_tiles[seat_id].append(tile)
	if own_reconcile:
		_finish_tile_reconcile()


func _rebuild_melds(seat_id: int, melds: Array,
		layout_claimant_absolute: int = -1,
		hand_extent: float = 0.0) -> void:
	var own_reconcile := not _reconcile_active
	if own_reconcile:
		_begin_tile_reconcile()
	_meld_tiles[seat_id].clear()
	if melds == null or melds.is_empty():
		if own_reconcile:
			_finish_tile_reconcile()
		return
	var claimant := layout_claimant_absolute if layout_claimant_absolute >= 0 \
		else seat_id
	var meld_extent := _meld_world_extent(melds, claimant)
	var centers := _hand_meld_center_offsets(seat_id, hand_extent, meld_extent)
	var flat_y: float = TABLE_TOP_Y + Tile3D.APPROVED_TILE_D * 0.5
	var radius := HAND_Z if seat_id == 0 else OPPONENT_HAND_RADIUS
	var meld_center := Table3DStage.rotate_from_south(
		Vector3(0, flat_y, radius), seat_id) \
		+ _layout_axis(seat_id) * float(centers["meld_center"])
	var along := _hand_basis(seat_id).x.normalized()
	var yaw: float = float([0.0, -90.0, 180.0, 90.0][seat_id])
	var overall_cursor := -meld_extent * 0.5
	var flat_slot_index := 0
	for meld_index in range(melds.size()):
		var meld := melds[meld_index] as Meld
		if meld == null:
			continue
		var slots := MeldLayout.compute(meld, claimant)
		var local_cursor := 0.0
		var stacked_anchor: Tile3D = null
		for slot_index in range(slots.size()):
			var slot := slots[slot_index] as Dictionary
			var stacked := bool(slot["stacked_above"])
			var added_tile: Tile = _added_tile_for_meld(meld) if stacked else null
			var iid := added_tile.instance_id if added_tile != null \
				else int(slot["tile_instance_id"])
			var render_tile_id := added_tile.id if added_tile != null \
				else int(slot["tile_id"])
			var render_red := added_tile.is_red_dora if added_tile != null \
				else bool(slot["is_red_dora"])
			var entity_key := "entity:%d" % iid
			# 规范 ADDED_KAN 的叠牌用真实 added identity，以便从手牌复用并飞入；
			# 只有旧 fixture 缺 added identity 时才保留 called tile 的视觉 occurrence。
			var force_occurrence := (stacked and added_tile == null) \
				or (Tile.is_valid_instance_id(iid) \
					and _desired_tile_keys.has(entity_key))
			var key := "meld:%d:%d:slot:%d" % [
				seat_id, meld.meld_id, slot_index] if force_occurrence \
				else _entity_key("meld", seat_id, iid, flat_slot_index)
			var existing := _tile_registry.get(key, null) as Tile3D
			var previous_region := String(existing.get_meta("render_region", "")) \
				if existing != null else ""
			var tile := _obtain_tile(key)
			_prepare_tile(tile, render_tile_id,
				not bool(slot["face_down"]), render_red, iid)
			tile.set_clickable(false)
			tile.set_selected(false)
			tile.set_dim(false)
			var rotated := bool(slot["rotated"])
			var target_position: Vector3
			var target_rotation: Vector3
			if stacked and stacked_anchor != null:
				target_position = stacked_anchor.get_meta(
					"layout_target_position", stacked_anchor.position) \
					+ Vector3(0, Tile3D.APPROVED_TILE_D, 0)
				target_rotation = stacked_anchor.get_meta(
					"layout_target_rotation", stacked_anchor.rotation_degrees)
			else:
				var footprint := Tile3D.TILE_H if rotated else Tile3D.TILE_W
				target_position = meld_center + along \
					* (overall_cursor + local_cursor + footprint * 0.5)
				target_rotation = Vector3(
					0, yaw + (90.0 if rotated else 0.0), 0)
				local_cursor += footprint + 0.004
				if rotated:
					stacked_anchor = tile
			var animate_transition: bool = existing != null \
				and not previous_region.is_empty() and previous_region != "meld"
			if animate_transition:
				tile.animate_to(target_position, target_rotation, 0.22)
				tile.set_meta("last_native_animation", "meld")
			else:
				tile.set_base_position(target_position)
				tile.rotation_degrees = target_rotation
			tile.set_meta("layout_target_position", target_position)
			tile.set_meta("layout_target_rotation", target_rotation)
			tile.set_meta("render_region", "meld")
			tile.set_meta("meld_id", meld.meld_id)
			tile.set_meta("meld_slot", slot_index)
			tile.set_meta("layout_slot_instance_id", int(slot["tile_instance_id"]))
			tile.set_meta("layout_claimant_absolute", claimant)
			_meld_tiles[seat_id].append(tile)
			flat_slot_index += 1
		overall_cursor += _meld_slots_extent(slots) + 0.028
	if own_reconcile:
		_finish_tile_reconcile()


func _rebuild_dora(state: BattleState) -> void:
	_free_arr(_dora_tiles)
	if state == null or state.dora_indicators == null:
		return
	var y: float = TABLE_TOP_Y + Tile3D.APPROVED_TILE_D * 0.5
	var i := 0
	for ti in state.dora_indicators.visible_tiles():
		if ti == null:
			continue
		var tile := Tile3D.new()
		_world_root.add_child(tile)
		tile.set_geometry_depth(Tile3D.APPROVED_TILE_D)
		tile.setup_entity(ti.id, true, ti.is_red_dora, ti.instance_id)
		# 略偏王牌区左侧，避免与 dead wall 重叠
		# 中心盘左侧，不与王牌/河重叠
		tile.set_base_position(Vector3(-0.10 + i * (Tile3D.TILE_W + 0.008), y, -0.02))
		tile.rotation_degrees = Vector3(0, 0, 0)
		_dora_tiles.append(tile)
		i += 1


func _on_tile_clicked(tile_instance_id: int) -> void:
	if not _is_hand_tile_actionable(tile_instance_id):
		return
	if _hand_activation_mode == HAND_ACTIVATION_CONFIRM_DISCARD:
		if _selected_hand_instance_ids == [tile_instance_id]:
			player_card_clicked.emit(tile_instance_id)
		else:
			set_selected_instances([tile_instance_id])
		return
	player_card_clicked.emit(tile_instance_id)


func _on_tile_flicked(tile_instance_id: int) -> void:
	# immediate 模式已在 pointer-down 提交；只让两段式弃牌消费上推，避免一次手势
	# 同时产生 click + flick 两条权威动作。
	if _hand_activation_mode == HAND_ACTIVATION_CONFIRM_DISCARD \
			and _is_hand_tile_actionable(tile_instance_id):
		player_card_clicked.emit(tile_instance_id)


func _is_hand_tile_actionable(tile_instance_id: int) -> bool:
	if not _hand_clickable or not Tile.is_valid_instance_id(tile_instance_id):
		return false
	for value in _hand_tiles:
		if value is Tile3D and (value as Tile3D).tile_instance_id == tile_instance_id:
			return not (value as Tile3D).is_dim()
	return false


func _on_tile_hover(tile_id: int, entered: bool) -> void:
	hand_tile_hover.emit(tile_id, entered)
