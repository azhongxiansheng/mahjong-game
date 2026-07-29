class_name MeldArea extends Node2D

# 麻将王 — 副露日麻风格视觉渲染（单 seat 用）
#
# 逻辑排位仍使用各家的局部方向；生产渲染把每张牌四角逐点投影到桌面，
# 不再旋转或缩放整个副露区域。

const TILE_W: int = 34
const TILE_H: int = 45

var _seat_id: int = -1
var _layout_claimant: int = -1
var _melds: Array = []        # Array[Meld]
var _tile_nodes: Array = []   # [{id, node}] 同名高亮
var _hover_match_id: int = -1
var _projection_raw_host := Rect2()
var _uses_table_projection: bool = false


func set_seat_id(seat_id: int) -> void:
	assert(seat_id >= 0 and seat_id <= 3)
	_seat_id = seat_id

# screen_seat：桌面视觉方位；layout_claimant_absolute：MeldLayout 用的权威绝对席
# （与 meld.from_seat 同坐标系）。省略第三参时两者同为 screen_seat（练习场 seat0）。
func set_melds(melds: Array, screen_seat: int, layout_claimant_absolute: int = -1) -> void:
	_seat_id = screen_seat
	_layout_claimant = layout_claimant_absolute if layout_claimant_absolute >= 0 else screen_seat
	_melds = melds
	_rebuild()


func set_hover_match_id(tile_id: int) -> void:
	_hover_match_id = tile_id
	_apply_hover_match()


func clear_hover_match() -> void:
	_hover_match_id = -1
	_apply_hover_match()


func count_hover_matched() -> int:
	var n := 0
	for e in _tile_nodes:
		var tile_rect := e.get("node") as CanvasItem
		if tile_rect != null and is_instance_valid(tile_rect) \
				and bool(tile_rect.get_meta("hover_match", false)):
			n += 1
	return n


func _apply_hover_match() -> void:
	for e in _tile_nodes:
		var tile_rect := e.get("node") as CanvasItem
		if tile_rect == null or not is_instance_valid(tile_rect):
			continue
		var on: bool = _hover_match_id >= 0 and int(e.get("id", -2)) == _hover_match_id
		tile_rect.set_meta("hover_match", on)
		if on:
			tile_rect.modulate = Color(0.55, 0.75, 1.0, 1.0)
		elif bool(e.get("was_red_tint", false)):
			tile_rect.modulate = Color(1.0, 0.7, 0.7, 1.0)  # 旧粉红赤宝 fallback 已少用
		else:
			tile_rect.modulate = Color.WHITE

func _rebuild() -> void:
	if not is_inside_tree():
		return
	# 清空旧 children
	for child in get_children():
		child.queue_free()
	_tile_nodes.clear()
	if _melds.is_empty():
		return
	var extractor: Node = get_tree().root.get_node_or_null("TextureExtractor")
	if extractor == null:
		return
	var slot_groups: Array = []
	var widths: Array = []
	var layout_seat: int = _layout_claimant if _layout_claimant >= 0 else _seat_id
	for meld in _melds:
		var slots: Array = MeldLayout.compute(meld as Meld, layout_seat)
		slot_groups.append(slots)
		widths.append(float(_slot_layout(slots, _seat_id)["width"]))
	var origins: Array = _meld_origins(widths, _seat_id)
	for i in range(slot_groups.size()):
		_render_meld(slot_groups[i], float(origins[i]), extractor, i)
	_apply_hover_match()


# 返回 CSS `.melds` 的布局盒（不把 box-shadow 算进 getBoundingClientRect）。
# FourPlayerTable 用它做 hand + gap + meld 的同容器 reflow。
func get_layout_bounds() -> Rect2:
	if _melds.is_empty():
		return Rect2()
	var groups: Array = []
	var widths: Array = []
	var layout_seat2: int = _layout_claimant if _layout_claimant >= 0 else _seat_id
	for meld in _melds:
		var slots: Array = MeldLayout.compute(meld as Meld, layout_seat2)
		groups.append(slots)
		widths.append(float(_slot_layout(slots, _seat_id)["width"]))
	var origins := _meld_origins(widths, _seat_id)
	var result := Rect2()
	var has_rect := false
	for group_index in range(groups.size()):
		var slots: Array = groups[group_index]
		var positions: Array = _slot_layout(slots, _seat_id)["positions"]
		for slot_index in range(slots.size()):
			var slot_rect := Rect2(
				positions[slot_index] + Vector2(float(origins[group_index]), 0),
				_slot_size(slots[slot_index]),
			)
			result = result.merge(slot_rect) if has_rect else slot_rect
			has_rect = true
	return result


func apply_reference_layout(hand_main_extent: float = -1.0,
		has_drawn: bool = true) -> void:
	var local_bounds := get_layout_bounds()
	if local_bounds.size == Vector2.ZERO:
		return
	var base_local_width: float = 137.0 if _seat_id == 1 or _seat_id == 3 else 135.0
	var controlled_fixture: bool = hand_main_extent < 0.0
	var base_target: Rect2 = TableLayout.single_pon_rect(_seat_id) if controlled_fixture \
		else TableLayout.LEGAL_ONE_PON_POST_DRAW_MELD_RECTS[_seat_id]
	if not controlled_fixture and _seat_id == 3 and not has_drawn:
		base_target = TableLayout.LEGAL_LEFT_ONE_PON_POST_DISCARD_MELD_RECT
	# 只从公开单碰尺寸取得固定 CSS/project scale；更多组沿各 owner 的
	# row/column 方向增长，靠 hand 的一侧仍保持 flex gap 不变。
	if _seat_id == 1 or _seat_id == 3:
		scale = Vector2(
			base_target.size.y / base_local_width,
			base_target.size.x / float(TILE_H),
		)
	else:
		scale = Vector2(
			base_target.size.x / base_local_width,
			base_target.size.y / float(TILE_H),
		)
	var screen_size: Vector2 = Vector2(
		local_bounds.size.y * scale.y,
		local_bounds.size.x * scale.x,
	) if _seat_id == 1 or _seat_id == 3 else local_bounds.size * scale
	var target: Rect2 = base_target
	target.size = screen_size
	var extent_delta: float = local_bounds.size.x - base_local_width
	if not controlled_fixture:
		var reference_hand_extent: float = TableLayout.hand_main_extent(_seat_id, 10)
		var reference_outer: float = base_local_width + (
			TableLayout.SIDE_MELD_MAIN_OVERHANG
			if _seat_id == 1 or _seat_id == 3 else 0.0)
		var actual_outer: float = local_bounds.size.x + (
			TableLayout.SIDE_MELD_MAIN_OVERHANG
			if _seat_id == 1 or _seat_id == 3 else 0.0)
		var reference_flex: Dictionary = TableLayout.hand_meld_flex_layout(
			_seat_id, reference_hand_extent, reference_outer)
		var actual_flex: Dictionary = TableLayout.hand_meld_flex_layout(
			_seat_id, hand_main_extent, actual_outer)
		var meld_start_delta: float = float(actual_flex["meld_start"]) \
			- float(reference_flex["meld_start"])
		match _seat_id:
			0:
				target.position.x += meld_start_delta
				target.position.y = 778.0 + (92.0 - screen_size.y) * 0.5
			1:
				var reference_raw_y: float = 124.1875
				target.position.y = TableLayout.project_table_point(Vector2(
					TableLayout.PERSPECTIVE_ORIGIN.x,
					reference_raw_y + meld_start_delta)).y
			2:
				target.position.x += meld_start_delta * scale.x
			3:
				var reference_raw_y: float = 544.8125 if has_drawn else 551.3125
				target.position.y = TableLayout.project_table_point(Vector2(
					TableLayout.PERSPECTIVE_ORIGIN.x,
					reference_raw_y + meld_start_delta)).y
	else:
		match _seat_id:
			0:
				target = Rect2(
					Vector2(base_target.position.x - extent_delta * 0.5,
						TableLayout.hand_host_rect(0, true).get_center().y
							- screen_size.y * 0.5), screen_size)
			1:
				var raw_meld_end_y := 151.187 + local_bounds.size.x * 0.5
				var screen_meld_end_y := TableLayout.project_table_point(
					Vector2(TableLayout.PERSPECTIVE_ORIGIN.x, raw_meld_end_y)).y
				target = Rect2(
					Vector2(base_target.position.x, screen_meld_end_y - screen_size.y),
					screen_size)
			2:
				var near_edge_x: float = base_target.end.x + extent_delta * 0.5 \
					* 434.277 / 530.0
				target = Rect2(
					Vector2(near_edge_x - screen_size.x, base_target.position.y),
					screen_size)
			3:
				var reflow_shift := (local_bounds.size.x \
					+ TableLayout.SIDE_MELD_MAIN_OVERHANG \
					+ TableLayout.HAND_MELD_GAP) * 0.5
				var raw_meld_top_y := 687.817 - reflow_shift
				var screen_meld_top_y := TableLayout.project_table_point(
					Vector2(TableLayout.PERSPECTIVE_ORIGIN.x, raw_meld_top_y)).y
				target = Rect2(
					Vector2(base_target.end.x - screen_size.x, screen_meld_top_y),
					screen_size)
	_projection_raw_host = TableLayout.raw_host_for_projected_local_bounds(
		_seat_id, target, local_bounds)
	_uses_table_projection = true
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	_rebuild()


func get_screen_layout_bounds() -> Rect2:
	var local_bounds := get_layout_bounds()
	if local_bounds.size == Vector2.ZERO:
		return Rect2()
	if _uses_table_projection:
		var quad := TableLayout.project_seat_local_rect(
			_seat_id, _projection_raw_host, local_bounds)
		var projected_min: Vector2 = quad[0]
		var projected_max: Vector2 = quad[0]
		for point in quad:
			projected_min = projected_min.min(point)
			projected_max = projected_max.max(point)
		return Rect2(projected_min, projected_max - projected_min)
	var xf := get_global_transform()
	var points := [
		xf * local_bounds.position,
		xf * Vector2(local_bounds.end.x, local_bounds.position.y),
		xf * local_bounds.end,
		xf * Vector2(local_bounds.position.x, local_bounds.end.y),
	]
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point: Vector2 in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)


static func _intra_meld_gap(owner_seat: int) -> float:
	return 1.0


static func _between_meld_gap(owner_seat: int) -> float:
	return 6.0


static func _slot_size(slot: Dictionary) -> Vector2:
	return Vector2(TILE_H, TILE_W) if bool(slot["rotated"]) \
		else Vector2(TILE_W, TILE_H)


static func _called_local_rotation(owner_seat: int) -> float:
	return 90.0 if owner_seat == 1 else -90.0


static func _back_local_rotation(owner_seat: int) -> float:
	return 180.0 if owner_seat == 2 or owner_seat == 3 else 0.0


# 返回每个 Slot 的本地左上角。MeldArea 根旋转后：owner1 向上、owner2 向左、
# owner3 向下；owner0/1/3 的短边需反向偏 13px 才等价 CSS flex 对齐。
static func _slot_layout(slots: Array, owner_seat: int) -> Dictionary:
	var positions: Array = []
	positions.resize(slots.size())
	positions.fill(Vector2.ZERO)
	var main_indices: Array[int] = []
	var cross_size: float = 0.0
	for i in range(slots.size()):
		if bool((slots[i] as Dictionary)["stacked_above"]):
			continue
		main_indices.append(i)
		cross_size = maxf(cross_size, _slot_size(slots[i]).y)
	var x := 0.0
	var gap := _intra_meld_gap(owner_seat)
	for main_pos in range(main_indices.size()):
		var index: int = main_indices[main_pos]
		var size_ := _slot_size(slots[index])
		var y := 0.0 if owner_seat == 2 else cross_size - size_.y
		positions[index] = Vector2(x, y)
		x += size_.x
		if main_pos < main_indices.size() - 1:
			x += gap
	var anchor := Vector2.ZERO
	for index in main_indices:
		if bool((slots[index] as Dictionary)["rotated"]):
			anchor = positions[index]
			break
	var stack_offset := Vector2(0, TILE_W + 1.0) if owner_seat == 2 \
		else Vector2(0, -TILE_W - 1.0)
	for i in range(slots.size()):
		if bool((slots[i] as Dictionary)["stacked_above"]):
			positions[i] = anchor + stack_offset
	return {"positions": positions, "width": x, "cross_size": cross_size}


# owner0 的外层是 row-reverse；其余 owner 的 CSS 方向在根旋转后都等价于
# 本地从左到右。整体仍把右边界固定在 x=0，兼容现有 TableLayout 锚点。
static func _meld_origins(widths: Array, owner_seat: int) -> Array:
	var origins: Array = []
	if widths.is_empty():
		return origins
	var gap := _between_meld_gap(owner_seat)
	if owner_seat == 0:
		var reverse_cursor := 0.0
		for width in widths:
			reverse_cursor -= float(width)
			origins.append(reverse_cursor)
			reverse_cursor -= gap
		return origins
	var total := gap * float(widths.size() - 1)
	for width in widths:
		total += float(width)
	var cursor := -total
	for width in widths:
		origins.append(cursor)
		cursor += float(width) + gap
	return origins


func _render_meld(slots: Array, x_start: float, extractor: Node,
		meld_index: int = 0) -> void:
	var layout := _slot_layout(slots, _seat_id)
	var positions: Array = layout["positions"]
	for i in range(slots.size()):
		var pos: Vector2 = positions[i] + Vector2(x_start, 0)
		var is_stacked := bool((slots[i] as Dictionary)["stacked_above"])
		_spawn_tile(slots[i], pos.x, pos.y, extractor,
			is_stacked and (_seat_id == 0 or _seat_id == 2),
			_reference_z_index(_seat_id, meld_index, i))


# CSS 只为 owner-1 显式建立两层 stacking order：meld 组 8/6/4/2，
# 组内 child 4/3/2/1。十进制拼接保持同样的字典序。
static func _reference_z_index(owner_seat: int, meld_index: int,
		slot_index: int) -> int:
	if owner_seat != 1:
		return 0
	var meld_z := 8 - mini(meld_index, 3) * 2
	var slot_z := 4 - mini(slot_index, 3)
	return meld_z * 10 + slot_z

# 在 (x, y_offset) 摆 1 张 tile 子节点（face_down 走 ColorRect 占位）
func _spawn_tile(slot: Dictionary, x: float, y_offset: float, extractor: Node,
		suppress_flat_depth: bool = false, draw_z: int = 0) -> void:
	if _uses_table_projection:
		_spawn_projected_tile(slot, Vector2(x, y_offset), extractor,
			suppress_flat_depth, draw_z)
		return
	var first_child_index := get_child_count()
	if bool(slot["face_down"]):
		_add_depth_layers(Vector2(x, y_offset), Vector2(TILE_W, TILE_H), true,
			suppress_flat_depth)
		var bg := ColorRect.new()
		bg.name = "TileBackFace"
		bg.size = Vector2(TILE_W, TILE_H)
		bg.position = Vector2(x, y_offset)
		bg.pivot_offset = bg.size * 0.5
		bg.rotation_degrees = _back_local_rotation(_seat_id)
		bg.color = Color("2c5e3f")
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var back_gradient := TextureRect.new()
		back_gradient.name = "Gradient"
		back_gradient.size = bg.size
		back_gradient.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back_gradient.stretch_mode = TextureRect.STRETCH_SCALE
		back_gradient.texture = _gradient_texture(
			[Color("3a7a55"), Color("2c5e3f"), Color("2c5e3f")],
			[0.0, 0.14, 1.0], Vector2(0.5, 0.0), Vector2(0.5, 1.0),
			bg.size)
		back_gradient.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.add_child(back_gradient)
		add_child(bg)
		_set_new_children_z(first_child_index, draw_z)
		return
	var key: String = CardTileBack.tile_id_to_atlas_key(
		int(slot["tile_id"]), bool(slot.get("is_red_dora", false)))
	if key == "":
		return
	var tex: Texture2D = extractor.get_tile_texture(key)
	if tex == null:
		return
	var rotated_slot: bool = bool(slot["rotated"])
	var slot_pos := Vector2(x, y_offset)
	var slot_size := Vector2(TILE_H, TILE_W) if rotated_slot else Vector2(TILE_W, TILE_H)
	_add_depth_layers(slot_pos, slot_size, false, suppress_flat_depth)
	var tex_rect := TextureRect.new()
	tex_rect.texture = tex
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.size = Vector2(TILE_W, TILE_H)
	# 赤宝走 0m/0p/0s 真图，保持 WHITE modulate（项目硬约束）
	if bool(slot["rotated"]):
		# bundle 的最终方向按 owner 分支；pivot 居中，bbox 恒为 TILE_H × TILE_W。
		# 视觉对齐：让旋转后的牌左上角与 (x, y_offset) 一致 → position 偏移
		# rotation pivot 在 size / 2，旋转 90° 后 bbox 左上偏移 = (TILE_W - TILE_H)/2 横向 + (TILE_H - TILE_W)/2 纵向
		tex_rect.pivot_offset = Vector2(TILE_W / 2.0, TILE_H / 2.0)
		tex_rect.rotation_degrees = _called_local_rotation(_seat_id)
		# 让旋转后视觉占满 [x, x + TILE_H]：position.x = x + (TILE_H - TILE_W) / 2
		# 旋转后纵向占 TILE_W 高（站立）；让顶端与正常 face-up 牌 y_offset 对齐
		var half_delta := (TILE_H - TILE_W) / 2.0
		tex_rect.position = slot_pos + Vector2(half_delta, -half_delta)
	else:
		tex_rect.position = slot_pos
	add_child(tex_rect)
	# 同名高亮登记（face_down 不入列）
	_tile_nodes.append({
		"id": int(slot["tile_id"]),
		"node": tex_rect,
		"was_red_tint": false,
	})
	_set_new_children_z(first_child_index, draw_z)


func _spawn_projected_tile(slot: Dictionary, slot_position: Vector2,
		extractor: Node, suppress_depth: bool, draw_z: int) -> void:
	var rotated := bool(slot["rotated"])
	var slot_size := Vector2(TILE_H, TILE_W) if rotated \
		else Vector2(TILE_W, TILE_H)
	var quad := TableLayout.project_seat_local_rect(
		_seat_id, _projection_raw_host, Rect2(slot_position, slot_size))
	var face_down := bool(slot["face_down"])
	if not suppress_depth:
		add_child(_make_projected_layer(
			"TileShadow", quad,
			TableLayout.public_tile_depth_offset(
				_seat_id, TableLayout.PUBLIC_TILE_SHADOW_OFFSET),
			Color(0, 0, 0, 0.36), "shadow", draw_z))
		add_child(_make_projected_layer(
			"GreenSide", quad,
			TableLayout.public_tile_depth_offset(
				_seat_id, TableLayout.PUBLIC_TILE_GREEN_DEPTH),
			Color("d8d8ce") if face_down else Color("2c6b47"),
			"green", draw_z))
		add_child(_make_projected_layer(
			"WhiteSide", quad,
			TableLayout.public_tile_depth_offset(
				_seat_id, TableLayout.PUBLIC_TILE_WHITE_DEPTH),
			Color("2c5e3f") if face_down else Color("d8d8ce"),
			"white", draw_z))
	var face := Polygon2D.new()
	face.name = "TileBackFace" if face_down else "TileFace"
	face.polygon = quad
	face.z_index = draw_z
	if face_down:
		face.color = Color("2c5e3f")
		add_child(face)
		return
	var key: String = CardTileBack.tile_id_to_atlas_key(
		int(slot["tile_id"]), bool(slot.get("is_red_dora", false)))
	if key == "":
		return
	var texture: Texture2D = extractor.get_tile_texture(key)
	if texture == null:
		return
	var texture_size := texture.get_size()
	if rotated and _called_local_rotation(_seat_id) > 0.0:
		face.uv = PackedVector2Array([
			Vector2(0, texture_size.y), Vector2.ZERO,
			Vector2(texture_size.x, 0), texture_size,
		])
	elif rotated:
		face.uv = PackedVector2Array([
			Vector2(texture_size.x, 0), texture_size,
			Vector2(0, texture_size.y), Vector2.ZERO,
		])
	else:
		face.uv = PackedVector2Array([
			Vector2.ZERO, Vector2(texture_size.x, 0), texture_size,
			Vector2(0, texture_size.y),
		])
	face.texture = texture
	face.set_meta("tile_id", int(slot["tile_id"]))
	add_child(face)
	_tile_nodes.append({
		"id": int(slot["tile_id"]),
		"node": face,
		"was_red_tint": false,
	})


static func _make_projected_layer(node_name: String,
		quad: PackedVector2Array, offset: Vector2, color: Color,
		layer_kind: String, draw_z: int) -> Polygon2D:
	var layer := Polygon2D.new()
	layer.name = node_name
	layer.polygon = TableLayout.offset_polygon(quad, offset)
	layer.color = color
	layer.z_index = draw_z
	layer.set_meta("depth_layer", layer_kind)
	return layer


func _set_new_children_z(first_child_index: int, draw_z: int) -> void:
	for child_index in range(first_child_index, get_child_count()):
		var canvas_item := get_child(child_index) as CanvasItem
		if canvas_item != null:
			canvas_item.z_index = draw_z


# 上下家用 before/after，左右家严格翻译 tile__side clip-path Polygon2D。
func _add_depth_layers(pos: Vector2, size_: Vector2, face_down: bool,
		suppress_flat_depth: bool) -> void:
	if _seat_id == 1 or _seat_id == 3:
		var tile_shadow_offset := Vector2(1.5, 0) if _seat_id == 1 \
			else Vector2(-1.5, 0)
		add_child(_make_shadow("TileShadowSide", pos, size_, tile_shadow_offset, 3,
			Color("0000004d")))
		_add_side_polygon_layers(pos, size_, face_down)
		return
	var geometry := _depth_geometry(_seat_id, pos, size_)
	add_child(_make_shadow("TileShadowSoft", pos, size_, geometry["soft"], 4,
		Color(0, 0, 0, 0.12)))
	add_child(_make_shadow("TileShadowSharp", pos, size_, geometry["sharp"], 2,
		Color(0, 0, 0, 0.22)))
	if suppress_flat_depth:
		return
	var green_colors: Array
	var green_offsets: Array
	var white_colors: Array
	var white_offsets: Array
	if face_down:
		green_colors = [Color("cfd0c5"), Color("b7b8ad")]
		green_offsets = [0.0, 1.0]
		white_colors = [Color("2c5e3f"), Color("2c5e3f"), Color("27543a")]
		white_offsets = [0.0, 0.55, 1.0]
	else:
		green_colors = [Color("57a271"), Color("4c9564"), Color("3e8254")]
		green_offsets = [0.0, 0.6, 1.0]
		white_colors = [Color("e9e9e0"), Color("e9e9e0"),
			Color("bcbdb6"), Color("a2a39d")]
		white_offsets = [0.0, 0.43, 0.55, 1.0]
	_add_flat_side("GreenSide", geometry["green_pos"], geometry["green_size"],
		green_colors, green_offsets, _seat_id)
	_add_flat_side("WhiteSide", geometry["white_pos"], geometry["white_size"],
		white_colors, white_offsets, _seat_id)


static func _depth_geometry(seat_id: int, pos: Vector2, size_: Vector2) -> Dictionary:
	if seat_id == 2:
		# 根节点 180°：本地向上才会落在屏幕牌体下边。
		return {
			"green_pos": pos + Vector2(0, -2), "green_size": Vector2(size_.x, 2),
			"white_pos": pos + Vector2(0, -1), "white_size": Vector2(size_.x, 2),
			"sharp": Vector2(0, -2), "soft": Vector2(0, -3),
		}
	return {
		"green_pos": pos + Vector2(0, size_.y), "green_size": Vector2(size_.x, 2),
		"white_pos": pos + Vector2(0, size_.y - 1), "white_size": Vector2(size_.x, 2),
		"sharp": Vector2(0, 2), "soft": Vector2(0, 3),
	}


func _add_flat_side(node_name: String, pos: Vector2, size_: Vector2,
		colors: Array, offsets: Array, owner_seat: int) -> void:
	var side := ColorRect.new()
	side.name = node_name
	side.position = pos
	side.size = size_
	side.color = colors[0]
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var overlay := TextureRect.new()
	overlay.name = "Gradient"
	overlay.size = size_
	overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	overlay.stretch_mode = TextureRect.STRETCH_SCALE
	var fill_from := Vector2(0.5, 1.0) if owner_seat == 2 else Vector2(0.5, 0.0)
	var fill_to := Vector2(0.5, 0.0) if owner_seat == 2 else Vector2(0.5, 1.0)
	overlay.texture = _gradient_texture(colors, offsets, fill_from, fill_to,
		size_)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side.add_child(overlay)
	add_child(side)


static func _gradient_texture(colors: Array, offsets: Array, fill_from: Vector2,
		fill_to: Vector2, size_: Vector2) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray(colors)
	gradient.offsets = PackedFloat32Array(offsets)
	var texture := GradientTexture2D.new()
	texture.width = maxi(1, ceili(size_.x))
	texture.height = maxi(1, ceili(size_.y))
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = fill_from
	texture.fill_to = fill_to
	texture.gradient = gradient
	return texture


static func _local_to_screen(owner_seat: int, point: Vector2) -> Vector2:
	if owner_seat == 1:
		return Vector2(point.y, -point.x)
	return Vector2(-point.y, point.x)


static func _screen_to_local(owner_seat: int, point: Vector2) -> Vector2:
	if owner_seat == 1:
		return Vector2(-point.y, point.x)
	return Vector2(point.y, -point.x)


static func _screen_rect(owner_seat: int, pos: Vector2, size_: Vector2) -> Rect2:
	var points := [
		_local_to_screen(owner_seat, pos),
		_local_to_screen(owner_seat, pos + Vector2(size_.x, 0)),
		_local_to_screen(owner_seat, pos + size_),
		_local_to_screen(owner_seat, pos + Vector2(0, size_.y)),
	]
	var min_point: Vector2 = points[0]
	var max_point: Vector2 = points[0]
	for point in points:
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	return Rect2(min_point, max_point - min_point)


static func _side_screen_geometry(owner_seat: int, pos: Vector2,
		size_: Vector2) -> Dictionary:
	var tile_rect := _screen_rect(owner_seat, pos, size_)
	var is_left := owner_seat == 3
	var element_pos := tile_rect.position + Vector2(0.0 if is_left else -1.5, 1.0)
	var element_size := Vector2(tile_rect.size.x + 1.5, tile_rect.size.y + 2.0)
	var w := element_size.x
	var h := element_size.y
	var outer: PackedVector2Array
	if is_left:
		outer = PackedVector2Array([
			element_pos + Vector2(0, -2),
			element_pos + Vector2(w + 2, -2),
			element_pos + Vector2(w + 2, h + 2),
			element_pos + Vector2(2, h + 2),
			element_pos + Vector2(0, h - 3),
		])
	else:
		outer = PackedVector2Array([
			element_pos + Vector2(w, -2),
			element_pos + Vector2(-2, -2),
			element_pos + Vector2(-2, h + 2),
			element_pos + Vector2(w - 2, h + 2),
			element_pos + Vector2(w, h - 3),
		])
	var inner_left := element_pos.x if is_left else element_pos.x + 0.75
	var inner_right := element_pos.x + w - 0.75 if is_left else element_pos.x + w
	var inner_top := element_pos.y - 0.5
	var inner_bottom := element_pos.y + h - 1.2
	var inner_rect := PackedVector2Array([
		Vector2(inner_left, inner_top), Vector2(inner_right, inner_top),
		Vector2(inner_right, inner_bottom), Vector2(inner_left, inner_bottom),
	])
	var intersections := Geometry2D.intersect_polygons(outer, inner_rect)
	var inner: PackedVector2Array = inner_rect
	if not intersections.is_empty():
		inner = intersections[0]
	return {
		"outer_screen": outer,
		"inner_screen": inner,
		"element_rect": Rect2(element_pos, element_size),
		"is_left": is_left,
	}


static func _map_screen_polygon_to_local(owner_seat: int,
		points: PackedVector2Array) -> PackedVector2Array:
	var mapped := PackedVector2Array()
	for point in points:
		mapped.append(_screen_to_local(owner_seat, point))
	return mapped


func _add_side_polygon_layers(pos: Vector2, size_: Vector2,
		face_down: bool) -> void:
	var geometry := _side_screen_geometry(_seat_id, pos, size_)
	var outer_screen: PackedVector2Array = geometry["outer_screen"]
	var inner_screen: PackedVector2Array = geometry["inner_screen"]
	for shadow_spec in [
		{"name": "TileSideShadowSoft", "offset": 3.0, "blur": 4.0,
			"color": Color("0000002e")},
		{"name": "TileSideShadowSharp", "offset": 1.5, "blur": 2.0,
			"color": Color("00000059")},
	]:
		var shifted := PackedVector2Array()
		for point in outer_screen:
			shifted.append(point + Vector2(0, float(shadow_spec["offset"])))
		var shadow := Polygon2D.new()
		shadow.name = shadow_spec["name"]
		shadow.polygon = _map_screen_polygon_to_local(_seat_id, shifted)
		shadow.color = shadow_spec["color"]
		shadow.set_meta("css_offset_y", shadow_spec["offset"])
		shadow.set_meta("css_blur", shadow_spec["blur"])
		add_child(shadow)
	var is_left: bool = geometry["is_left"]
	var outer_colors: Array
	var outer_offsets: Array
	var inner_colors: Array
	var inner_offsets: Array
	if face_down:
		outer_colors = [Color("cfd0c5"), Color("c3c4b9"), Color("b6b7ac")]
		outer_offsets = [0.0, 0.6, 1.0]
		inner_colors = [Color("2c5e3f"), Color("2c5b3f")]
		inner_offsets = [0.0, 1.0]
	else:
		outer_colors = [Color("4c9564"), Color("4c9564"),
			Color("3f8055"), Color("357049")]
		outer_offsets = [0.0, 0.45, 0.75, 1.0]
		inner_colors = [Color("d8d8cd"), Color("c9cabf"), Color("b9baaf")]
		inner_offsets = [0.0, 0.55, 1.0]
	var element_rect: Rect2 = geometry["element_rect"]
	var fill_from_screen := element_rect.position + \
		(Vector2.ZERO if is_left else Vector2(element_rect.size.x, 0))
	var fill_to_screen := element_rect.position + \
		(element_rect.size if is_left else Vector2(0, element_rect.size.y))
	var fill_from_local := _screen_to_local(_seat_id, fill_from_screen)
	var fill_to_local := _screen_to_local(_seat_id, fill_to_screen)
	var outer := _make_gradient_polygon("TileSideOuter",
		_map_screen_polygon_to_local(_seat_id, outer_screen), outer_colors,
		outer_offsets, fill_from_local, fill_to_local)
	outer.set_meta("css_top", 1.0)
	outer.set_meta("css_bottom", -3.0)
	outer.set_meta("css_inline_overhang", -1.5)
	add_child(outer)
	var inner := _make_gradient_polygon("TileSideInner",
		_map_screen_polygon_to_local(_seat_id, inner_screen), inner_colors,
		inner_offsets, fill_from_local, fill_to_local)
	add_child(inner)
	var outline := Line2D.new()
	outline.name = "TileSideOutline"
	outline.width = 0.8
	outline.default_color = Color("1e282099")
	outline.set_meta("css_blur", 0.4)
	outline.points = outer.polygon
	outline.add_point(outer.polygon[0])
	add_child(outline)


static func _make_gradient_polygon(node_name: String,
		points: PackedVector2Array, colors: Array, offsets: Array,
		fill_from: Vector2, fill_to: Vector2) -> Polygon2D:
	var min_point: Vector2 = points[0]
	var max_point: Vector2 = points[0]
	for point in points:
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	var bounds := Rect2(min_point, max_point - min_point)
	var texture := _gradient_texture(colors, offsets,
		(fill_from - bounds.position) / bounds.size,
		(fill_to - bounds.position) / bounds.size, bounds.size)
	var polygon := Polygon2D.new()
	polygon.name = node_name
	polygon.polygon = points
	var uv := PackedVector2Array()
	var texture_size := Vector2(texture.width, texture.height)
	for point in points:
		uv.append((point - bounds.position) / bounds.size * texture_size)
	polygon.uv = uv
	polygon.texture = texture
	polygon.color = Color.WHITE
	return polygon


static func _make_shadow(node_name: String, pos: Vector2, size_: Vector2,
		offset: Vector2, blur_size: int, color: Color) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = pos
	panel.size = size_
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.shadow_color = color
	sb.shadow_size = blur_size
	sb.shadow_offset = offset
	panel.add_theme_stylebox_override("panel", sb)
	return panel
