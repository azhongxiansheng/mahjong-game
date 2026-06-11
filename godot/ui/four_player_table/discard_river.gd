class_name DiscardRiver extends Node2D

# 麻将王 — 单家弃牌河可视化(plan: 战斗节点真实可玩 / 牌河 + Dora 显示)。
#
# Node2D 旋转 0/-90/180/+90 让 face 朝桌心;内部用 TextureRect 子节点画每张
# 牌的 atlas 纹理(Node2D rotation 自动应用到 child Control)。
#
# 内部坐标:(0,0) 是 left-top 原点,6 张牌横向 +X 累积,行向 +Y 累积。
# Node2D rotation 把这套坐标转到桌面 4 边方向。
#
# 立直牌:`set_tiles(tiles, riichi_idx)` 把指定索引的弃牌旋转 90°
# (日麻标志记号),其后同一行的牌按"旋转后宽度 48"右移 16 px。
# 最近一张弃牌(列表末)用骨白细描边强调"这是本家最新弃"。

const TILE_W: int = 32
const TILE_H: int = 48
const TILE_GAP: int = 2
const TILES_PER_ROW: int = 6
# 立直牌旋转 90 后视觉宽度 = TILE_H = 48,比 TILE_W 多 16
const RIICHI_W_EXTRA: int = TILE_H - TILE_W

var _tiles: Array = []
var _riichi_index: int = -1
# T2:实宝牌 id 集合(FourPlayerTable 注入);上次渲染张数,只在真正新增
# 弃牌时播放入场 glow(全量 rebind 每事件都跑,不用计数会反复闪)。
var _dora_ids: Array = []
var _last_tile_count: int = 0


func set_dora_ids(ids: Array) -> void:
	_dora_ids = ids


# riichi_idx < 0 表示本家未立直;>= 0 表示该索引的弃牌为立直宣告牌。
func set_tiles(tiles: Array, riichi_idx: int = -1) -> void:
	_tiles = tiles
	_riichi_index = riichi_idx
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		child.queue_free()
	var extractor: Node = get_tree().root.get_node_or_null("TextureExtractor")
	if extractor == null:
		return
	var n: int = _tiles.size()
	# 每行独立累积 x,这样行末 wrap 后 x 重置;前一行的旋转不影响下一行。
	var x: float = 0.0
	var current_row: int = 0
	for i in range(n):
		var tile: Tile = _tiles[i]
		if tile == null:
			continue
		var row: int = i / TILES_PER_ROW
		if row != current_row:
			x = 0.0
			current_row = row
		var y: float = row * (TILE_H + TILE_GAP)
		var key: String = CardTileBack.tile_id_to_atlas_key(tile.id)
		if key == "":
			continue
		var tex: Texture2D = extractor.get_tile_texture(key)
		if tex == null:
			continue
		var is_riichi: bool = (i == _riichi_index)
		var is_last: bool = (i == n - 1)
		var is_new: bool = is_last and n > _last_tile_count
		_spawn_tile(tex, x, y, is_riichi, is_last, _dora_ids.has(tile.id), is_new)
		# 累 x:立直牌旋转后视觉 48 宽,普通 32 宽
		var slot_w: float = TILE_H if is_riichi else TILE_W
		x += slot_w + TILE_GAP
	_last_tile_count = n


func _spawn_tile(tex: Texture2D, x: float, y: float, is_riichi: bool,
		is_last: bool, is_dora: bool = false, is_new: bool = false) -> void:
	var tr := TextureRect.new()
	tr.size = Vector2(TILE_W, TILE_H)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture = tex
	tr.modulate = Color.WHITE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_riichi:
		# Control 用 pivot_offset + rotation_degrees 自转;pivot 设为左下角
		# 让旋转后牌顶左下落在原 (x, y+TILE_H) 处,占用 slot 宽 48 高 32。
		tr.pivot_offset = Vector2(0, TILE_H)
		tr.rotation_degrees = -90
		# 旋转后 tile 视觉:左下角在 (x, y+TILE_H);占 (x, y+TILE_H-48..y+TILE_H)
		# 高 = TILE_W=32,顶在 y+TILE_H-32 = y+16,需要把整个下移让顶在 y。
		tr.position = Vector2(x, y - (TILE_H - TILE_W))
	else:
		tr.position = Vector2(x, y)
	add_child(tr)
	var slot_size: Vector2 = Vector2(TILE_H, TILE_W) if is_riichi else Vector2(TILE_W, TILE_H)
	# T2:河中宝牌金色描边(扫光在 32×48 上太碎,静态金边已足够醒目)
	if is_dora:
		add_child(_make_border(tr.position, slot_size, Color(0.85, 0.71, 0.36, 0.9), 2))
	if is_last:
		# 最近一张弃牌:骨白描边 + 新增时入场 glow 衰减(对标 discard-glow)。
		var hl := _make_border(tr.position, slot_size, Color(1, 0.92, 0.55, 0.95), 2)
		add_child(hl)
		if is_new:
			# 入场:整张牌从 92% 缩放弹开 + 高亮层 alpha 衰减,1s 收敛
			tr.pivot_offset = slot_size / 2.0 if not is_riichi else tr.pivot_offset
			tr.scale = Vector2.ONE * 0.88
			var tw := create_tween().set_parallel(true)
			tw.tween_property(tr, "scale", Vector2.ONE, 0.22) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			hl.modulate = Color(1.6, 1.5, 1.2, 1.0)
			tw.tween_property(hl, "modulate", Color.WHITE, 1.0) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func _make_border(pos: Vector2, size_: Vector2, color: Color, width: int) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size_
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = color
	sb.border_width_left = width
	sb.border_width_right = width
	sb.border_width_top = width
	sb.border_width_bottom = width
	p.add_theme_stylebox_override("panel", sb)
	return p
