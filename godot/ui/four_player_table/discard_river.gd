class_name DiscardRiverView extends Node2D

# 公开参考 bundle `tV` / `.river` 的 Godot 等价实现。
#
# - 固定 300×144 容器与 4 行；前 3 行各 6 张，第 4 行吸收溢出。
# - wonDiscardIndices 先按原索引跳过，再用 visibleCount 压紧排位。
# - 每张牌用 whole TileRoot 执行同参数二阶 spring 入场。
# - keyed 前缀只 append，保留旧节点与正在运行的动画。
# - `_spawn_tile` 仅保留为既有几何测试的直接渲染入口；生产路径均走 TileRoot。

const RIVER_W: int = 300
const RIVER_H: int = 144
const ROW_COUNT: int = 4
const ROW_H: int = 45
const TILES_PER_ROW: int = 6

# 原创紧凑公开牌尺寸：牌河与副露共用比例，避免中心区形成厚重牌墙。
const TILE_W: int = 34
const TILE_H: int = 45
const TILE_GAP: int = 3
const RIICHI_W_EXTRA: int = TILE_H - TILE_W

# Framer Motion bundle 原参数：type=spring, stiffness=360, damping=22, mass=.7。
const SPRING_STIFFNESS: float = 360.0
const SPRING_DAMPING: float = 22.0
const SPRING_MASS: float = 0.7
const ENTER_OFFSET_Y: float = 16.0
const LATEST_GLOW_DURATION: float = 1.0

var _tiles: Array = []
var _riichi_index: int = -1
var _won_discard_indices: Array = []
var _seat_id: int = 0
var _dora_ids: Array = []

# 增量渲染簿记。_rendered_ids 始终与源 tiles 原索引对齐，包含被 won 跳过的牌。
var _rendered_ids: Array = []
var _rendered_riichi: int = -1
var _rendered_dora_key: String = ""
var _rendered_won_key: String = ""
var _cursor_x: float = 0.0
var _cursor_row: int = 0
var _visible_count: int = 0

var _last_highlight: CanvasItem = null
var _tile_nodes: Array = [] # Array[{id:int, node:CanvasItem}]
var _tile_roots: Array = []
var _last_tile_local_center: Vector2 = Vector2.ZERO
var _hover_match_id: int = -1

var _container: Control = null
var _rows: Array = []
var _enter_animations: Array = []


func _ready() -> void:
	_ensure_structure()
	_cursor_x = _left_padding()
	set_process(false)
	if not _tiles.is_empty() and _rendered_ids.is_empty():
		_rebuild()


func set_seat_id(seat_id: int) -> void:
	assert(seat_id >= 0 and seat_id <= 3)
	if _seat_id == seat_id:
		return
	_seat_id = seat_id
	if is_inside_tree():
		_ensure_structure()
		_update_row_positions()
		if not _rendered_ids.is_empty():
			_rebuild()
		else:
			_cursor_x = _left_padding()


func set_dora_ids(ids: Array) -> void:
	_dora_ids = ids
	if is_inside_tree() and not _rendered_ids.is_empty():
		_reconcile_dora_borders()


func count_hover_matched() -> int:
	var count := 0
	for entry in _tile_nodes:
		var face := entry.get("node") as CanvasItem
		if face != null and is_instance_valid(face) \
				and bool(face.get_meta("hover_match", false)):
			count += 1
	return count


func set_hover_match_id(tile_id: int) -> void:
	_hover_match_id = tile_id
	_apply_hover_match()


func clear_hover_match() -> void:
	_hover_match_id = -1
	_apply_hover_match()


func _apply_hover_match() -> void:
	for entry in _tile_nodes:
		var face := entry.get("node") as CanvasItem
		if face == null or not is_instance_valid(face):
			continue
		var match_id: int = int(entry.get("id", -2))
		var on: bool = _hover_match_id >= 0 and match_id == _hover_match_id
		face.set_meta("hover_match", on)
		face.modulate = Color(0.55, 0.75, 1.0, 1.0) if on else Color.WHITE


func get_last_tile_local_center() -> Vector2:
	return _last_tile_local_center


# won_indices 对齐公开组件的可选 wonDiscardIndices；riichi/latest 仍按源原索引判断。
func set_tiles(tiles: Array, riichi_idx: int = -1, won_indices: Array = []) -> void:
	_tiles = tiles
	_riichi_index = riichi_idx
	_won_discard_indices = won_indices.duplicate()
	if not is_inside_tree():
		return
	_ensure_structure()
	if _can_append(tiles, riichi_idx):
		_append_from(_rendered_ids.size())
	else:
		_rebuild()


# 新列表只在尾部增长、前缀/立直/won 集不破坏旧可见节点时才 append。
# dora 是现有 keyed 牌面的视觉属性，原位更新金边，不得触发 remount。
func _can_append(tiles: Array, riichi_idx: int) -> bool:
	var previous_count: int = _rendered_ids.size()
	if tiles.size() < previous_count:
		return false
	if riichi_idx != _rendered_riichi and riichi_idx < previous_count:
		return false
	if _won_key() != _rendered_won_key:
		return false
	for i in range(previous_count):
		if _tiles_id_at(tiles, i) != int(_rendered_ids[i]):
			return false
	return true


static func _tiles_id_at(tiles: Array, index: int) -> int:
	var tile = tiles[index]
	return tile.id if tile != null else -1


func _dora_key() -> String:
	var ids := _dora_ids.duplicate()
	ids.sort()
	return ",".join(ids.map(func(value): return str(value)))


func _won_key() -> String:
	var indices := _won_discard_indices.duplicate()
	indices.sort()
	return ",".join(indices.map(func(value): return str(value)))


func _is_won_index(index: int) -> bool:
	return _won_discard_indices.has(index)


func _append_from(start: int) -> void:
	var extractor: Node = get_tree().root.get_node_or_null("TextureExtractor")
	if extractor == null:
		return
	if start < _tiles.size():
		_clear_latest_glow()
	for original_index in range(start, _tiles.size()):
		var tile: Tile = _tiles[original_index]
		_rendered_ids.append(_tiles_id_at(_tiles, original_index))
		if _is_won_index(original_index) or tile == null:
			continue
		var key: String = CardTileBack.tile_id_to_atlas_key(tile.id, tile.is_red_dora)
		if key == "":
			continue
		var texture: Texture2D = extractor.get_tile_texture(key)
		if texture == null:
			continue
		var is_riichi: bool = original_index == _riichi_index
		var is_latest: bool = original_index == _tiles.size() - 1
		_spawn_rendered_tile(texture, original_index, _visible_count, is_riichi,
			is_latest, _dora_ids.has(tile.id), tile.id)
		_visible_count += 1
	_rendered_riichi = _riichi_index
	_rendered_dora_key = _dora_key()
	_rendered_won_key = _won_key()
	_apply_hover_match()


func _rebuild() -> void:
	_clear_rendered_tiles()
	_rendered_ids = []
	_rendered_riichi = -1
	_rendered_dora_key = ""
	_rendered_won_key = ""
	_cursor_x = _left_padding()
	_cursor_row = 0
	_visible_count = 0
	_last_tile_local_center = Vector2.ZERO
	_append_from(0)


func _reconcile_dora_borders() -> void:
	for root_value in _tile_roots:
		var root := root_value as Node2D
		if root == null or not is_instance_valid(root):
			continue
		var face := root.get_node_or_null("TileFace") as CanvasItem
		if face == null:
			continue
		var should_show: bool = _dora_ids.has(int(face.get_meta("tile_id", -1)))
		var border := root.get_node_or_null("DoraBorder") as CanvasItem
		if should_show and border == null:
			border = _make_projected_border(
				root.get_meta("projected_quad") as PackedVector2Array,
				Color(0.85, 0.71, 0.36, 0.9), 2.0)
			border.name = "DoraBorder"
			root.add_child(border)
		elif not should_show and border != null:
			root.remove_child(border)
			border.queue_free()
	_rendered_dora_key = _dora_key()


func _clear_rendered_tiles() -> void:
	_clear_latest_glow()
	_enter_animations.clear()
	for root in _tile_roots:
		if root == null or not is_instance_valid(root):
			continue
		var node := root as Node
		node.queue_free()
	_tile_roots.clear()
	_tile_nodes.clear()
	set_process(false)


func _ensure_structure() -> void:
	if _container != null and is_instance_valid(_container):
		return
	_container = Control.new()
	_container.name = "RiverContainer"
	_container.size = Vector2(RIVER_W, RIVER_H)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.clip_contents = false
	add_child(_container)
	_rows.clear()
	for row_index in range(ROW_COUNT):
		var row := Control.new()
		row.name = "RiverRow_%d" % row_index
		row.size = Vector2(RIVER_W, ROW_H)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.clip_contents = false
		_container.add_child(row)
		_rows.append(row)
	_update_row_positions()


func _update_row_positions() -> void:
	for row_index in range(_rows.size()):
		var row := _rows[row_index] as Control
		row.position = Vector2(0, row_index * (ROW_H + _row_gap()))


func _row_gap() -> float:
	return 4.0


func _tile_gap() -> float:
	return float(TILE_GAP)


func _left_padding() -> float:
	var row_width := TILES_PER_ROW * TILE_W + (TILES_PER_ROW - 1) * TILE_GAP
	return (RIVER_W - row_width) * 0.5


func _spawn_rendered_tile(texture: Texture2D, original_index: int,
		visible_index: int, is_riichi: bool, is_latest: bool,
		is_dora: bool, tile_id: int) -> void:
	var row_index: int = mini(floori(float(visible_index) / TILES_PER_ROW), ROW_COUNT - 1)
	if row_index != _cursor_row:
		_cursor_row = row_index
		_cursor_x = _left_padding()
	var column: int = visible_index - row_index * TILES_PER_ROW
	var slot_size := Vector2(TILE_H, TILE_W) if is_riichi else Vector2(TILE_W, TILE_H)
	var row_position := Vector2(_cursor_x, (ROW_H - slot_size.y) * 0.5)
	var river_position := Vector2(row_position.x,
		row_index * (ROW_H + _row_gap()) + row_position.y)

	var root := Node2D.new()
	root.name = "TileRoot_%d" % original_index
	root.set_meta("original_index", original_index)
	root.set_meta("visible_index", visible_index)
	root.set_meta("row", row_index)
	root.set_meta("column", column)
	root.set_meta("row_position", row_position)
	root.set_meta("river_position", river_position)
	root.set_meta("slot_size", slot_size)
	root.set_meta("is_riichi", is_riichi)
	root.set_meta("is_latest", is_latest)
	_container.add_child(root)
	_tile_roots.append(root)

	_spawn_projected_tile_contents(root, river_position, slot_size, texture, is_riichi,
		is_latest, is_dora, tile_id)
	var quad := root.get_meta("projected_quad") as PackedVector2Array
	_last_tile_local_center = (quad[0] + quad[1] + quad[2] + quad[3]) * 0.25
	_start_enter_spring(root, Vector2.ZERO)
	_cursor_x += slot_size.x + _tile_gap()


# 既有伪 3D 几何测试会直接调用；生产渲染不走这个兼容入口。
func _spawn_tile(texture: Texture2D, x: float, y: float, is_riichi: bool,
		is_last: bool, is_dora: bool = false, _is_new: bool = false,
		tile_id: int = -1) -> void:
	var slot_size := Vector2(TILE_H, TILE_W) if is_riichi else Vector2(TILE_W, TILE_H)
	var slot_position := Vector2(x, y)
	_spawn_tile_contents(self, slot_position, slot_size, texture, is_riichi,
		is_last, is_dora, tile_id)
	_last_tile_local_center = slot_position + slot_size * 0.5


func _spawn_tile_contents(parent: Node, slot_position: Vector2, slot_size: Vector2,
		texture: Texture2D, is_riichi: bool, is_last: bool,
		is_dora: bool, tile_id: int) -> void:
	_add_depth_layers_to(parent, slot_position, slot_size)
	var face := TextureRect.new()
	face.name = "TileFace"
	face.size = Vector2(TILE_W, TILE_H)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_SCALE
	face.texture = texture
	face.modulate = Color.WHITE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_meta("tile_id", tile_id)
	if is_riichi:
		face.pivot_offset = Vector2(TILE_W, TILE_H) * 0.5
		face.rotation_degrees = -90
		var half_delta := (TILE_H - TILE_W) * 0.5
		face.position = slot_position + Vector2(half_delta, -half_delta)
	else:
		face.position = slot_position
	parent.add_child(face)
	_tile_nodes.append({"id": tile_id, "node": face})
	if is_dora:
		var dora_border := _make_border(slot_position, slot_size,
			Color(0.85, 0.71, 0.36, 0.9), 2)
		dora_border.name = "DoraBorder"
		parent.add_child(dora_border)
	if is_last:
		var glow := _make_latest_glow(slot_position, slot_size)
		parent.add_child(glow)
		_last_highlight = glow
		_play_latest_glow(glow)


func _spawn_projected_tile_contents(parent: Node2D, river_position: Vector2,
		slot_size: Vector2, texture: Texture2D, is_riichi: bool,
		is_last: bool, is_dora: bool, tile_id: int) -> void:
	var quad := TableLayout.project_seat_local_rect(
		_seat_id, TableLayout.river_raw_rect(_seat_id),
		Rect2(river_position, slot_size))
	parent.set_meta("projected_quad", quad)
	var shadow_quad := PackedVector2Array()
	for point in quad:
		shadow_quad.append(point + Vector2(0, 2.5))
	var shadow := Polygon2D.new()
	shadow.name = "TileShadow"
	shadow.polygon = shadow_quad
	shadow.color = Color(0, 0, 0, 0.24)
	parent.add_child(shadow)
	var thickness := Polygon2D.new()
	thickness.name = "TileThickness"
	thickness.polygon = PackedVector2Array([
		quad[3], quad[2], quad[2] + Vector2(0, 1.8),
		quad[3] + Vector2(0, 1.8),
	])
	thickness.color = Color("d8ded5")
	parent.add_child(thickness)
	var face := Polygon2D.new()
	face.name = "TileFace"
	face.polygon = quad
	var texture_size := texture.get_size()
	face.uv = PackedVector2Array([
		Vector2(texture_size.x, 0), Vector2(texture_size.x, texture_size.y),
		Vector2(0, texture_size.y), Vector2.ZERO,
	]) if is_riichi else PackedVector2Array([
		Vector2.ZERO, Vector2(texture_size.x, 0), texture_size,
		Vector2(0, texture_size.y),
	])
	face.texture = texture
	face.set_meta("tile_id", tile_id)
	parent.add_child(face)
	_tile_nodes.append({"id": tile_id, "node": face})
	if is_dora:
		var border := _make_projected_border(
			quad, Color(0.85, 0.71, 0.36, 0.9), 2.0)
		border.name = "DoraBorder"
		parent.add_child(border)
	if is_last:
		var glow := Polygon2D.new()
		glow.name = "LatestGlow"
		glow.polygon = quad
		glow.color = Color("d9b65b66")
		glow.set_meta("duration_seconds", LATEST_GLOW_DURATION)
		parent.add_child(glow)
		_last_highlight = glow
		_play_latest_glow(glow)


static func _make_projected_border(quad: PackedVector2Array, color: Color,
		width: float) -> Line2D:
	var border := Line2D.new()
	border.points = quad
	border.closed = true
	border.default_color = color
	border.width = width
	border.antialiased = true
	return border


func _clear_latest_glow() -> void:
	if _last_highlight != null and is_instance_valid(_last_highlight):
		_last_highlight.queue_free()
	_last_highlight = null


static func _make_latest_glow(position_: Vector2, size_: Vector2) -> Panel:
	var glow := Panel.new()
	glow.name = "LatestGlow"
	glow.position = position_
	glow.size = size_
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_meta("duration_seconds", LATEST_GLOW_DURATION)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.shadow_color = Color("d9b65b99")
	style.shadow_size = 12
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	glow.add_theme_stylebox_override("panel", style)
	return glow


func _play_latest_glow(glow: CanvasItem) -> void:
	var tween := glow.create_tween()
	# CSS discard-glow 的 0% → 60% → 100%，总长严格 1s；结束删除节点。
	tween.tween_property(glow, "modulate", Color(1, 1, 1, 0.30), 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(glow, "modulate", Color(1, 1, 1, 0), 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		if _last_highlight == glow:
			_last_highlight = null
		if is_instance_valid(glow):
			glow.queue_free()
	)


func _start_enter_spring(root: Node2D, rest_position: Vector2) -> void:
	root.position = rest_position + Vector2(0, ENTER_OFFSET_Y)
	root.modulate = Color(1, 1, 1, 0)
	_enter_animations.append({
		"node": root,
		"rest_position": rest_position,
		"elapsed": 0.0,
	})
	set_process(true)


func _process(delta: float) -> void:
	for index in range(_enter_animations.size() - 1, -1, -1):
		var state: Dictionary = _enter_animations[index]
		var root := state.get("node") as Node2D
		if root == null or not is_instance_valid(root):
			_enter_animations.remove_at(index)
			continue
		var elapsed: float = float(state.get("elapsed", 0.0)) + delta
		state["elapsed"] = elapsed
		_enter_animations[index] = state
		var y_sample := _spring_sample(ENTER_OFFSET_Y, 0.0, elapsed)
		var opacity_sample := _spring_sample(0.0, 1.0, elapsed)
		var rest_position := state.get("rest_position") as Vector2
		root.position = rest_position + Vector2(0, float(y_sample["value"]))
		root.modulate.a = clampf(float(opacity_sample["value"]), 0.0, 1.0)
		if absf(float(y_sample["value"])) < 0.01 \
				and absf(float(y_sample["velocity"])) < 0.01:
			root.position = rest_position
			root.modulate.a = 1.0
			_enter_animations.remove_at(index)
	if _enter_animations.is_empty():
		set_process(false)


# m*x'' + c*x' + k*(x-target)=0 的欠阻尼解析解；避免用 Godot 预设曲线近似参数。
static func _spring_sample(initial: float, target: float, elapsed: float) -> Dictionary:
	var alpha := SPRING_DAMPING / (2.0 * SPRING_MASS)
	var omega_zero_sq := SPRING_STIFFNESS / SPRING_MASS
	var omega := sqrt(omega_zero_sq - alpha * alpha)
	var displacement := initial - target
	var decay := exp(-alpha * elapsed)
	var phase := omega * elapsed
	var value := target + decay * displacement * (
		cos(phase) + alpha / omega * sin(phase))
	var velocity := -decay * displacement * omega_zero_sq / omega * sin(phase)
	return {"value": value, "velocity": velocity}


# 公开牌平放桌面，只保留 2px 牌体和轻微接触阴影。
func _add_depth_layers_to(parent: Node, position_: Vector2, size_: Vector2) -> void:
	var geometry := _depth_geometry(_seat_id, position_, size_)
	parent.add_child(_make_shadow("TileShadowSoft", position_, size_,
		geometry["soft"], 4, Color(0, 0, 0, 0.12)))
	parent.add_child(_make_shadow("TileShadowSharp", position_, size_,
		geometry["sharp"], 2, Color(0, 0, 0, 0.22)))
	parent.add_child(_make_side("GreenSide", geometry["green_pos"],
		geometry["green_size"], false, _seat_id))
	parent.add_child(_make_side("WhiteSide", geometry["white_pos"],
		geometry["white_size"], true, _seat_id))


static func _make_side(node_name: String, position_: Vector2, size_: Vector2,
		is_white: bool, seat_id: int) -> ColorRect:
	var side := ColorRect.new()
	side.name = node_name
	side.position = position_
	side.size = size_
	side.color = Color("e9e9e0") if is_white else Color("4c9564")
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient_layer := TextureRect.new()
	gradient_layer.name = "SideGradient"
	gradient_layer.size = size_
	gradient_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gradient_layer.stretch_mode = TextureRect.STRETCH_SCALE
	gradient_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gradient_layer.texture = _make_side_gradient(size_, is_white, seat_id)
	side.add_child(gradient_layer)
	return side


static func _make_side_gradient(size_: Vector2, is_white: bool,
		seat_id: int) -> GradientTexture2D:
	var spec := _side_gradient_spec(is_white, seat_id)
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	gradient.interpolation_color_space = Gradient.GRADIENT_COLOR_SPACE_SRGB
	gradient.offsets = spec["offsets"]
	gradient.colors = spec["colors"]
	var texture := GradientTexture2D.new()
	texture.width = maxi(1, ceili(size_.x))
	texture.height = maxi(1, ceili(size_.y))
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = spec["from"]
	texture.fill_to = spec["to"]
	texture.gradient = gradient
	return texture


static func _side_gradient_spec(is_white: bool, seat_id: int) -> Dictionary:
	var from := Vector2(0, 0)
	var to := Vector2(0, 1)
	if seat_id == 1: # right: CSS 270deg
		from = Vector2(1, 0)
		to = Vector2(0, 0)
	elif seat_id == 3: # left: CSS 90deg
		to = Vector2(1, 0)
	if seat_id == 2: # top 使用 CSS 中反序且不同 stop 的专用渐变
		if is_white:
			return {
				"from": from, "to": to,
				"offsets": PackedFloat32Array([0.0, 0.45, 0.57, 1.0]),
				"colors": PackedColorArray([
					Color("a2a39d"), Color("bcbdb6"),
					Color("e9e9e0"), Color("e9e9e0")]),
			}
		return {
			"from": from, "to": to,
			"offsets": PackedFloat32Array([0.0, 0.40, 1.0]),
			"colors": PackedColorArray([
				Color("3e8254"), Color("4c9564"), Color("57a271")]),
		}
	if is_white:
		return {
			"from": from, "to": to,
			"offsets": PackedFloat32Array([0.0, 0.43, 0.55, 1.0]),
			"colors": PackedColorArray([
				Color("e9e9e0"), Color("e9e9e0"),
				Color("bcbdb6"), Color("a2a39d")]),
		}
	return {
		"from": from, "to": to,
		"offsets": PackedFloat32Array([0.0, 0.60, 1.0]),
		"colors": PackedColorArray([
			Color("57a271"), Color("4c9564"), Color("3e8254")]),
	}


static func _depth_geometry(seat_id: int, position_: Vector2,
		size_: Vector2) -> Dictionary:
	match seat_id:
		1: # 右家：侧面在左
			return {
				"green_pos": position_ + Vector2(-2, 0),
				"green_size": Vector2(2, size_.y),
				"white_pos": position_ + Vector2(-1, 0),
				"white_size": Vector2(2, size_.y),
				"sharp": Vector2(-2, 0), "soft": Vector2(-3, 0),
			}
		2: # 上家：侧面在上
			return {
				"green_pos": position_ + Vector2(0, -2),
				"green_size": Vector2(size_.x, 2),
				"white_pos": position_ + Vector2(0, -1),
				"white_size": Vector2(size_.x, 2),
				"sharp": Vector2(0, -2), "soft": Vector2(0, -3),
			}
		3: # 左家：侧面在右
			return {
				"green_pos": position_ + Vector2(size_.x, 0),
				"green_size": Vector2(2, size_.y),
				"white_pos": position_ + Vector2(size_.x - 1, 0),
				"white_size": Vector2(2, size_.y),
				"sharp": Vector2(2, 0), "soft": Vector2(3, 0),
			}
	return { # 自家：侧面在下
		"green_pos": position_ + Vector2(0, size_.y),
		"green_size": Vector2(size_.x, 2),
		"white_pos": position_ + Vector2(0, size_.y - 1),
		"white_size": Vector2(size_.x, 2),
		"sharp": Vector2(0, 2), "soft": Vector2(0, 3),
	}


static func _make_shadow(node_name: String, position_: Vector2,
		size_: Vector2, offset: Vector2, blur_size: int, color: Color) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = position_
	panel.size = size_
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.shadow_color = color
	style.shadow_size = blur_size
	style.shadow_offset = offset
	panel.add_theme_stylebox_override("panel", style)
	return panel


static func _make_border(position_: Vector2, size_: Vector2, color: Color,
		width: int) -> Panel:
	var border := Panel.new()
	border.position = position_
	border.size = size_
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = color
	style.border_width_left = width
	style.border_width_right = width
	style.border_width_top = width
	style.border_width_bottom = width
	border.add_theme_stylebox_override("panel", style)
	return border
