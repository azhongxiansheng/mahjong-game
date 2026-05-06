extends Node2D

# F6 手测：在一行内画出 34 张牌的 atlas 正面 + 一行牌背色块对照。
# 用于验证 CardTileBack.set_face_up + TextureExtractor.get_tile_texture 链路。

const TILE_W: int = 80
const TILE_H: int = 120
const ROW_GAP: int = 24
const COL_GAP: int = 4
const MARGIN: int = 32

func _ready() -> void:
	_build_face_up_row()
	_build_back_row()
	_build_revealed_row()
	_build_title()

func _build_title() -> void:
	var lbl := Label.new()
	lbl.position = Vector2(MARGIN, 8)
	lbl.text = "CardTileBack 渲染冒烟：第1行=face_up(atlas)，第2行=牌背色块(seat 0..3)，第3行=revealed(半透明 atlas)"
	lbl.add_theme_font_size_override("font_size", 14)
	add_child(lbl)

func _build_face_up_row() -> void:
	var y: int = MARGIN
	var x: int = MARGIN
	for tid in range(34):
		var tile := CardTileBack.new()
		tile.position = Vector2(x, y)
		add_child(tile)
		tile.set_face_up(tid)
		x += TILE_W + COL_GAP

func _build_back_row() -> void:
	var y: int = MARGIN + TILE_H + ROW_GAP
	var x: int = MARGIN
	# 4 个 seat 颜色各画 6 张以对照
	for seat_id in range(4):
		for _i in range(6):
			var tile := CardTileBack.new()
			tile.position = Vector2(x, y)
			add_child(tile)
			tile.set_owner_seat(seat_id)
			x += TILE_W + COL_GAP

func _build_revealed_row() -> void:
	var y: int = MARGIN + (TILE_H + ROW_GAP) * 2
	var x: int = MARGIN
	# 透明牌：跟第 1 行同样的 34 张牌但半透明
	for tid in range(34):
		var tile := CardTileBack.new()
		tile.position = Vector2(x, y)
		add_child(tile)
		tile.set_tile_id(tid)
		tile.set_owner_seat(1)
		tile.set_revealed(true)
		x += TILE_W + COL_GAP
