class_name Wall

var _tiles: Array[Tile] = []
var _draw_index: int = 0

static func new_full_set() -> Wall:
	var w := Wall.new()
	# 每种 TileId 4 张，5m/5p/5s 第一张标记为赤
	for tid in TileId.ALL:
		for copy_index in range(4):
			var is_red := false
			if copy_index == 0 and (tid == TileId.W5 or tid == TileId.T5 or tid == TileId.S5):
				is_red = true
			w._tiles.append(Tile.new(tid, is_red))
	return w

func size() -> int:
	return _tiles.size() - _draw_index

func remaining() -> int:
	return size()

func shuffle(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# Fisher-Yates 在剩余未抽部分洗
	var i := _tiles.size() - 1
	while i > _draw_index:
		var j := _draw_index + rng.randi_range(0, i - _draw_index)
		var tmp := _tiles[i]
		_tiles[i] = _tiles[j]
		_tiles[j] = tmp
		i -= 1

func draw() -> Tile:
	if size() == 0:
		return null
	var t := _tiles[_draw_index]
	_draw_index += 1
	return t
