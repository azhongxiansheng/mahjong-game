class_name MeldArea extends Node2D

# 麻将王 — 副露日麻风格视觉渲染（单 seat 用）
#
# Node2D 旋转 0/-90/180/+90 让面朝桌心；4 桌边各 1 个实例。
# 内部按 MeldLayout.compute(...) 的 Slot 描述摆 TextureRect 子节点。
# 多组 meld 累积横排（最早的在最右；新加的在最左 — 标准日麻"副露往左推"）

const TILE_W: int = 32
const TILE_H: int = 48
const MELD_GAP: int = 8       # 多组 meld 之间间距

var _seat_id: int = -1
var _melds: Array = []        # Array[Meld]

# claimant_seat = self._seat_id；分开存便于后续 polling 模式
func set_melds(melds: Array, claimant_seat: int) -> void:
	_seat_id = claimant_seat
	_melds = melds
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return
	# 清空旧 children
	for child in get_children():
		child.queue_free()
	if _melds.is_empty():
		return
	var extractor: Node = get_tree().root.get_node_or_null("TextureExtractor")
	if extractor == null:
		return
	# 从右往左累积，最早 meld 在最右 (x=0)
	var x_cursor: float = 0.0
	for meld_idx in range(_melds.size()):
		var meld: Meld = _melds[meld_idx]
		var slots: Array = MeldLayout.compute(meld, _seat_id)
		x_cursor = _render_meld(slots, x_cursor, extractor)
		x_cursor -= MELD_GAP

# 在 x_start 起点（最右侧）从右往左渲染 1 组 meld；返新 x_cursor（更靠左）
# 整组 meld 占的最左 x 通过 return 报上层。
func _render_meld(slots: Array, x_start: float, extractor: Node) -> float:
	var x: float = x_start
	# 第一遍：从右往左摆"非 stacked_above"的牌，记每张占的 x 范围
	# 顺序：slots 是从左到右的逻辑顺序；视觉上 slots[last] 摆最右，slots[0] 摆最左
	var slot_x: Array = []  # 每个 slot 对应的左上 x（同 index 顺序）
	slot_x.resize(slots.size())
	for i in range(slots.size() - 1, -1, -1):
		var slot: Dictionary = slots[i]
		if bool(slot["stacked_above"]):
			slot_x[i] = 0.0  # placeholder；下面单独处理
			continue
		var w: float = TILE_H if bool(slot["rotated"]) else TILE_W
		x -= w
		slot_x[i] = x
		_spawn_tile(slot, x, 0.0, extractor)
	# 第二遍：处理 stacked_above 牌；锚定到 meld 内第 1 个 rotated slot 的 x，y 偏 -TILE_W
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		if not bool(slot["stacked_above"]):
			continue
		var anchor_x: float = _find_first_rotated_x(slots, slot_x)
		_spawn_tile(slot, anchor_x, -TILE_W, extractor)
	return x

# 找 slots 中首个 rotated（且非 stacked_above）的 x
static func _find_first_rotated_x(slots: Array, slot_x: Array) -> float:
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		if bool(slot["rotated"]) and not bool(slot["stacked_above"]):
			return slot_x[i]
	return 0.0

# 在 (x, y_offset) 摆 1 张 tile 子节点（face_down 走 ColorRect 占位）
func _spawn_tile(slot: Dictionary, x: float, y_offset: float, extractor: Node) -> void:
	if bool(slot["face_down"]):
		var bg := ColorRect.new()
		bg.size = Vector2(TILE_W, TILE_H)
		bg.position = Vector2(x, y_offset)
		bg.color = Color(0.15, 0.15, 0.20)
		add_child(bg)
		return
	var key: String = CardTileBack.tile_id_to_atlas_key(int(slot["tile_id"]))
	if key == "":
		return
	var tex: Texture2D = extractor.get_tile_texture(key)
	if tex == null:
		return
	var tex_rect := TextureRect.new()
	tex_rect.texture = tex
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	tex_rect.size = Vector2(TILE_W, TILE_H)
	if bool(slot["rotated"]):
		# 旋转 90°（CW）；pivot 居中防位移；旋转后实际占 TILE_H 横 × TILE_W 纵
		# 视觉对齐：让旋转后的牌左上角与 (x, y_offset) 一致 → position 偏移
		# rotation pivot 在 size / 2，旋转 90° 后 bbox 左上偏移 = (TILE_W - TILE_H)/2 横向 + (TILE_H - TILE_W)/2 纵向
		tex_rect.pivot_offset = Vector2(TILE_W / 2.0, TILE_H / 2.0)
		tex_rect.rotation_degrees = 90.0
		# 让旋转后视觉占满 [x, x + TILE_H]：position.x = x + (TILE_H - TILE_W) / 2
		# 旋转后纵向占 TILE_W 高（站立）；让顶端与正常 face-up 牌 y_offset 对齐
		tex_rect.position = Vector2(x + (TILE_H - TILE_W) / 2.0, y_offset + (TILE_H - TILE_W) / 2.0)
	else:
		tex_rect.position = Vector2(x, y_offset)
	add_child(tex_rect)
