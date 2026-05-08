extends Node2D

# 麻将王 — F6 手测：MeldArea 4 桌边 layout 视觉验证
#
# 跑法：editor 中打开 .tscn，按 F6
#
# 期待视觉：
#   底（玩家 seat 0）= PON 上家来（左旋转） + ANKAN（首尾盖牌）
#   右（seat 1）   = MINKAN 对家来（中旋转）
#   上（seat 2）   = CHI 上家来（左旋转）
#   左（seat 3）   = ADDED_KAN 上家来（旋转牌上方再叠 1 张）

const MeldAreaScene = preload("res://ui/four_player_table/meld_area.tscn")

func _ready() -> void:
	# 底（玩家 seat 0）
	_spawn(Vector2(640, 600), 0.0, _player_melds(), 0)
	# 右（seat 1）
	_spawn(Vector2(1100, 360), -90.0, _shimocha_melds(), 1)
	# 上（seat 2）
	_spawn(Vector2(640, 100), 180.0, _toimen_melds(), 2)
	# 左（seat 3）
	_spawn(Vector2(180, 360), 90.0, _kamicha_melds(), 3)

func _spawn(pos: Vector2, rot_deg: float, melds: Array, seat_id: int) -> void:
	var area: MeldArea = MeldAreaScene.instantiate()
	area.position = pos
	area.rotation_degrees = rot_deg
	add_child(area)
	area.set_melds(melds, seat_id)

func _player_melds() -> Array:
	# PON 上家来（W5）+ ANKAN（T9）
	var pon_tiles: Array[Tile] = [
		Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5),
	]
	var ankan_tiles: Array[Tile] = [
		Tile.new(TileId.T9), Tile.new(TileId.T9),
		Tile.new(TileId.T9), Tile.new(TileId.T9),
	]
	return [Meld.make_pon(pon_tiles, 3), Meld.make_ankan(ankan_tiles)]

func _shimocha_melds() -> Array:
	# MINKAN 对家来（HAKU）— claimant=1, toimen=3
	var tiles: Array[Tile] = [
		Tile.new(TileId.HAKU), Tile.new(TileId.HAKU),
		Tile.new(TileId.HAKU), Tile.new(TileId.HAKU),
	]
	return [Meld.make_minkan(tiles, 3)]

func _toimen_melds() -> Array:
	# CHI 上家来 — claimant=2, kamicha=1
	var tiles: Array[Tile] = [
		Tile.new(TileId.S2), Tile.new(TileId.S3), Tile.new(TileId.S4),
	]
	return [Meld.make_chi(tiles, 1)]

func _kamicha_melds() -> Array:
	# ADDED_KAN 上家来 — claimant=3, kamicha=2
	var tiles: Array[Tile] = [
		Tile.new(TileId.W7), Tile.new(TileId.W7),
		Tile.new(TileId.W7), Tile.new(TileId.W7),
	]
	return [Meld.make_added_kan(tiles, 2)]
