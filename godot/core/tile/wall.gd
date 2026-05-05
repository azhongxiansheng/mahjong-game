class_name Wall

# 0e 扩展：dead wall 切片 + 岭上摸取 + dora 指示牌探针。
# Dead wall 物理槽位约定（0..13 表示从 dead wall 末端倒数）：
#   位置 0..3  : 4 张岭上（take_rinshan 依次取 [end-1] [end-2] [end-3] [end-4]）
#   位置 4..8  : 5 张表 dora 指示牌（peek_dora_indicator(n) → [end-5-2n]）
#   位置 5..9  : 5 张裏 dora 指示牌（peek_uradora_indicator(n) → [end-6-2n]）
# 注：表/裏 dora 物理位置交错（标准日麻），开局翻 indicator(0)，每杠后翻 indicator(1) ...

var _tiles: Array[Tile] = []
var _draw_index: int = 0
var _dead_wall_size: int = 0
var _rinshan_taken: int = 0

static func new_full_set() -> Wall:
	var w := Wall.new()
	# 每种 TileId 4 张，5m/5p/5s 第一张标记为赤。
	# owner_seat 按 copy_index 分配：4 家各占 1 张副本（"卡组合并"语义占位 v1）。
	# M6 引入真正卡组系统时改为按玩家 deck 决定；UI 端 SeatPanel 手牌色块只关心
	# 这一字段，不依赖具体来源，因此后续替换不影响 UI 代码。
	for tid in TileId.ALL:
		for copy_index in range(4):
			var is_red := false
			if copy_index == 0 and (tid == TileId.W5 or tid == TileId.T5 or tid == TileId.S5):
				is_red = true
			w._tiles.append(Tile.new(tid, is_red, copy_index))
	return w

func size() -> int:
	# 0a 行为保持不变（未 reserve 时含 dead wall 区域）；0e 后调用方应用 live_wall_size 区分
	return _tiles.size() - _draw_index - _dead_wall_size

func remaining() -> int:
	# alias of size() for readability at call sites
	return size()

func live_wall_size() -> int:
	# 显式语义：可摸的 live wall 张数（排除 dead wall 与已摸）
	return size()

func shuffle(rng_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	# Fisher-Yates 在剩余未抽部分洗
	var i := _tiles.size() - 1
	while i > _draw_index:
		var j := _draw_index + rng.randi_range(0, i - _draw_index)
		var tmp := _tiles[i]
		_tiles[i] = _tiles[j]
		_tiles[j] = tmp
		i -= 1

func draw() -> Tile:
	# 不真的 pop：保留全部 136 张以便后续 dora 指示牌检查、王牌区拆分；
	# 用 _draw_index 推进，避免数组重排开销
	if size() == 0:
		return null
	var t := _tiles[_draw_index]
	_draw_index += 1
	return t

# ---- 0e: dead wall API ----

func reserve_dead_wall(count: int = 14) -> void:
	# 必须在 shuffle 后调用；此后 size()/draw() 自动避开 dead wall
	_dead_wall_size = count

func take_rinshan() -> Tile:
	# 从 dead wall 末端依次取岭上：第 1 次返 _tiles[-1]，第 2 次 _tiles[-2]，最多 4 次
	if _rinshan_taken >= 4:
		return null
	var idx: int = _tiles.size() - 1 - _rinshan_taken
	_rinshan_taken += 1
	return _tiles[idx]

func peek_dora_indicator(n: int) -> Tile:
	# 第 n 张表 dora 指示牌（0 = 开局翻，1..4 = 各杠后翻）
	if n < 0 or n >= 5:
		return null
	return _tiles[_tiles.size() - 5 - 2 * n]

func peek_uradora_indicator(n: int) -> Tile:
	# 第 n 张裏 dora 指示牌（与表 dora 物理槽交错）
	if n < 0 or n >= 5:
		return null
	return _tiles[_tiles.size() - 6 - 2 * n]

# ---- M10: 信息系 ctx 用 peek API（不推进 _draw_index） ----

# 下次摸牌：返将被 draw() 取的牌；牌墙空返 null。
func peek_next_draw() -> Tile:
	if size() == 0:
		return null
	return _tiles[_draw_index]

# 牌墙顶 n 张（按 draw 顺序）；牌墙剩余不足时返实际剩余张。
# 不修改 _draw_index — 仅 peek，调用者拿到的是 Tile 引用快照。
func peek_top_n(n: int) -> Array[Tile]:
	var result: Array[Tile] = []
	if n <= 0:
		return result
	var avail: int = mini(n, size())
	for i in range(avail):
		result.append(_tiles[_draw_index + i])
	return result
