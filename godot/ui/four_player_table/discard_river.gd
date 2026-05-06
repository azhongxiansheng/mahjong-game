class_name DiscardRiver extends Node2D

# 麻将王 — 单家弃牌河可视化（plan: 战斗节点真实可玩 / 牌河 + Dora 显示）。
#
# Node2D 旋转 0/-90/180/+90 让 face 朝桌心；内部用 TextureRect 子节点画每张
# 牌的 atlas 纹理（Node2D rotation 自动应用到 child Control）。
#
# 内部坐标：(0,0) 是 left-top 原点，6 张牌横向 +X 累积，行向 +Y 累积。
# Node2D rotation 把这套坐标转到桌面 4 边方向。

const TILE_W: int = 32
const TILE_H: int = 48
const TILE_GAP: int = 2
const TILES_PER_ROW: int = 6
const RIVER_W: int = TILES_PER_ROW * TILE_W + (TILES_PER_ROW - 1) * TILE_GAP  # 202

var _tiles: Array = []

func set_tiles(tiles: Array) -> void:
	_tiles = tiles
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		child.queue_free()
	var extractor: Node = get_tree().root.get_node_or_null("TextureExtractor")
	if extractor == null:
		return
	for i in range(_tiles.size()):
		var tile: Tile = _tiles[i]
		if tile == null:
			continue
		var row: int = i / TILES_PER_ROW
		var col: int = i % TILES_PER_ROW
		var x := col * (TILE_W + TILE_GAP)
		var y := row * (TILE_H + TILE_GAP)
		var key: String = CardTileBack.tile_id_to_atlas_key(tile.id)
		if key == "":
			continue
		var tex: Texture2D = extractor.get_tile_texture(key)
		if tex == null:
			continue
		var tr := TextureRect.new()
		tr.position = Vector2(x, y)
		tr.size = Vector2(TILE_W, TILE_H)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.texture = tex
		tr.modulate = Color.WHITE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(tr)
