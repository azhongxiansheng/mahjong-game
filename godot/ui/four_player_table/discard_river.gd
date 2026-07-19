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
# (日麻标志记号),其后同一行的牌按"旋转后宽度"右移。
# 最近一张弃牌(列表末)用骨白细描边强调"这是本家最新弃"。
#
# T5(spec 2026-06-11 G5-b)增量渲染:bind_battle_state 每个 BC 事件都全量
# 调 set_tiles,旧实现每次 queue_free 重建全部子节点 → 新弃牌的入场动画在
# 下一事件(往往 <0.4s)就被销毁打断。现在 diff:
#   前缀不变 + riichi 不回溯 + dora 集不变 → 只 append 新增牌(动画存活);
#   否则(鸣牌取走 / 回放 / dora 翻新)→ 全量 rebuild(安全兜底)。

# T3e 布局收敛(spec 2026-06-11 §2.4):河牌 38×50,与参考作一致。
const TILE_W: int = 38
const TILE_H: int = 50
const TILE_GAP: int = 2
const TILES_PER_ROW: int = 6
# 立直牌旋转 90 后视觉宽度 = TILE_H,比 TILE_W 多 12
const RIICHI_W_EXTRA: int = TILE_H - TILE_W

var _tiles: Array = []
var _riichi_index: int = -1
# T2:实宝牌 id 集合(FourPlayerTable 注入)
var _dora_ids: Array = []

# ---- 增量渲染簿记 ----
# 已渲染牌的 id 序列(含 null 占位,与 _tiles 索引对齐)
var _rendered_ids: Array = []
var _rendered_riichi: int = -1
var _rendered_dora_key: String = ""
# 排版游标(append 从此续排)
var _cursor_x: float = 0.0
var _cursor_row: int = 0
# 「最新弃牌」高亮节点(append 时旧的要撤掉)
var _last_highlight: Panel = null
# 雀魂式同名高亮：tile_id → TextureRect 列表
var _tile_nodes: Array = []  # Array[{id:int, node:TextureRect}]
var _last_tile_local_center: Vector2 = Vector2.ZERO
var _hover_match_id: int = -1


func set_dora_ids(ids: Array) -> void:
	_dora_ids = ids


func count_hover_matched() -> int:
	var n := 0
	for e in _tile_nodes:
		var tr: TextureRect = e.get("node")
		if tr != null and is_instance_valid(tr) and bool(tr.get_meta("hover_match", false)):
			n += 1
	return n


func set_hover_match_id(tile_id: int) -> void:
	_hover_match_id = tile_id
	_apply_hover_match()


func clear_hover_match() -> void:
	_hover_match_id = -1
	_apply_hover_match()


func _apply_hover_match() -> void:
	for e in _tile_nodes:
		var tr: TextureRect = e.get("node")
		if tr == null or not is_instance_valid(tr):
			continue
		var match_id: int = int(e.get("id", -2))
		var on: bool = _hover_match_id >= 0 and match_id == _hover_match_id
		tr.set_meta("hover_match", on)
		# 蓝半透明蒙版感：不改 WHITE 主体，用 modulate 叠蓝（河牌非 atlas WHITE 硬约束同牌桌 face）
		if on:
			tr.modulate = Color(0.55, 0.75, 1.0, 1.0)
		else:
			tr.modulate = Color.WHITE


func get_last_tile_local_center() -> Vector2:
	return _last_tile_local_center


# riichi_idx < 0 表示本家未立直;>= 0 表示该索引的弃牌为立直宣告牌。
func set_tiles(tiles: Array, riichi_idx: int = -1) -> void:
	_tiles = tiles
	_riichi_index = riichi_idx
	if not is_inside_tree():
		return
	if _can_append(tiles, riichi_idx):
		_append_from(_rendered_ids.size())
	else:
		_rebuild()


# 增量条件:新列表只在尾部增长、已渲染前缀的 id 逐一相同、
# riichi 标记不落在已渲染区(新弃牌当立直牌 OK)、dora 集合没变。
func _can_append(tiles: Array, riichi_idx: int) -> bool:
	var prev_n: int = _rendered_ids.size()
	if tiles.size() < prev_n:
		return false
	if riichi_idx != _rendered_riichi and riichi_idx < prev_n:
		return false  # 立直标记回溯到旧牌(回放等)→ 全量
	if _dora_key() != _rendered_dora_key:
		return false  # 杠翻新 dora,旧牌的金边需要重算
	# 前缀逐一比对(等长时同样要查 — 同一帧内"被鸣走+新弃"会出现
	# 等长但末尾不同的批处理边界)
	for i in range(prev_n):
		var tid: int = _tiles_id_at(tiles, i)
		if tid != int(_rendered_ids[i]):
			return false
	return true


static func _tiles_id_at(tiles: Array, i: int) -> int:
	var t = tiles[i]
	return t.id if t != null else -1


func _dora_key() -> String:
	var ids := _dora_ids.duplicate()
	ids.sort()
	return ",".join(ids.map(func(v): return str(v)))


# 从 start 起把 _tiles 的新增部分续排进河(保留既有子节点与动画)。
func _append_from(start: int) -> void:
	var extractor: Node = get_tree().root.get_node_or_null("TextureExtractor")
	if extractor == null:
		return
	var n: int = _tiles.size()
	for i in range(start, n):
		var tile: Tile = _tiles[i]
		_rendered_ids.append(_tiles_id_at(_tiles, i))
		if tile == null:
			continue
		var row: int = i / TILES_PER_ROW
		if row != _cursor_row:
			_cursor_x = 0.0
			_cursor_row = row
		var key: String = CardTileBack.tile_id_to_atlas_key(tile.id, tile.is_red_dora)
		if key == "":
			continue
		var tex: Texture2D = extractor.get_tile_texture(key)
		if tex == null:
			continue
		var is_riichi: bool = (i == _riichi_index)
		var is_last: bool = (i == n - 1)
		# 撤旧高亮(它属于上一张"最新弃")
		if is_last and _last_highlight and is_instance_valid(_last_highlight):
			_last_highlight.queue_free()
			_last_highlight = null
		_spawn_tile(tex, _cursor_x, _cursor_row * (TILE_H + TILE_GAP),
			is_riichi, is_last, _dora_ids.has(tile.id), true, tile.id)
		var slot_w: float = TILE_H if is_riichi else TILE_W
		_cursor_x += slot_w + TILE_GAP
	_rendered_riichi = _riichi_index
	_rendered_dora_key = _dora_key()
	_apply_hover_match()


# 全量重建(初始 / 鸣牌取走 / 立直回溯 / dora 翻新的兜底路径,无入场动画)。
func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_rendered_ids = []
	_rendered_riichi = -1
	_rendered_dora_key = ""
	_cursor_x = 0.0
	_cursor_row = 0
	_last_highlight = null
	_tile_nodes.clear()
	var extractor: Node = get_tree().root.get_node_or_null("TextureExtractor")
	if extractor == null:
		return
	var n: int = _tiles.size()
	for i in range(n):
		var tile: Tile = _tiles[i]
		_rendered_ids.append(_tiles_id_at(_tiles, i))
		if tile == null:
			continue
		var row: int = i / TILES_PER_ROW
		if row != _cursor_row:
			_cursor_x = 0.0
			_cursor_row = row
		var key: String = CardTileBack.tile_id_to_atlas_key(tile.id, tile.is_red_dora)
		if key == "":
			continue
		var tex: Texture2D = extractor.get_tile_texture(key)
		if tex == null:
			continue
		var is_riichi: bool = (i == _riichi_index)
		var is_last: bool = (i == n - 1)
		_spawn_tile(tex, _cursor_x, _cursor_row * (TILE_H + TILE_GAP),
			is_riichi, is_last, _dora_ids.has(tile.id), false, tile.id)
		var slot_w: float = TILE_H if is_riichi else TILE_W
		_cursor_x += slot_w + TILE_GAP
	_rendered_riichi = _riichi_index
	_rendered_dora_key = _dora_key()
	_apply_hover_match()


func _spawn_tile(tex: Texture2D, x: float, y: float, is_riichi: bool,
		is_last: bool, is_dora: bool = false, is_new: bool = false,
		tile_id: int = -1) -> void:
	# 投影垫底(StyleBox shadow 画在自身 rect 之外、其余子节点之下)
	var shadow := Panel.new()
	var shadow_sb := StyleBoxFlat.new()
	shadow_sb.bg_color = Color(0, 0, 0, 0)
	shadow_sb.shadow_color = Color(0, 0, 0, 0.32)
	shadow_sb.shadow_size = 4
	shadow_sb.shadow_offset = Vector2(0, 3)
	shadow.add_theme_stylebox_override("panel", shadow_sb)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.size = Vector2(TILE_W, TILE_H)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture = tex
	tr.modulate = Color.WHITE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_meta("tile_id", tile_id)
	if is_riichi:
		# Control 用 pivot_offset + rotation_degrees 自转;pivot 设为左下角
		# 让旋转后牌顶左下落在原 (x, y+TILE_H) 处。
		tr.pivot_offset = Vector2(0, TILE_H)
		tr.rotation_degrees = -90
		tr.position = Vector2(x, y - (TILE_H - TILE_W))
	else:
		tr.position = Vector2(x, y)
	var slot_size: Vector2 = Vector2(TILE_H, TILE_W) if is_riichi else Vector2(TILE_W, TILE_H)
	shadow.position = Vector2(x, y) if not is_riichi else tr.position
	shadow.size = slot_size
	add_child(shadow)
	add_child(tr)
	_tile_nodes.append({"id": tile_id, "node": tr})
	_last_tile_local_center = tr.position + slot_size * 0.5
	# T2:河中宝牌金色描边
	if is_dora:
		add_child(_make_border(tr.position, slot_size, Color(0.85, 0.71, 0.36, 0.9), 2))
	if is_last:
		# 最近一张弃牌:骨白描边 + 新增时入场动画(增量渲染下不再被打断)
		var hl := _make_border(tr.position, slot_size, Color(1, 0.92, 0.55, 0.95), 2)
		add_child(hl)
		_last_highlight = hl
		if is_new:
			# 入场:从该家手方向(local -Y 上方)落下 + 弹缩 + 高亮衰减
			if not is_riichi:
				tr.pivot_offset = slot_size / 2.0
			tr.scale = Vector2.ONE * 0.85
			var land_y: float = tr.position.y
			tr.position.y = land_y - 14.0
			var tw := create_tween().set_parallel(true)
			tw.tween_property(tr, "scale", Vector2.ONE, 0.2) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(tr, "position:y", land_y, 0.18) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
