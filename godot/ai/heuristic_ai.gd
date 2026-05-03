class_name HeuristicAi extends SimpleAi

# 麻将王 — M7 平衡迭代：稍微聪明一点的弃牌 AI（启动启发式）。
#
# 目标：让 SimpleAi 100% 流局的 baseline 变得更现实。SimpleAi 全随机弃手牌
# 导致对家几乎从不到 tenpai，整套 RON / WIN_DECLARED_PRE / 技能系统在 sim
# 里没有数据点。
#
# 启发式：discard 最"孤立"的牌（同色 ±2 范围内邻居最少 + 自身重复数最少）。
# 这是一个 well-known low-bar 麻将 AI 启发，足以让 hand 缓慢趋向 tenpai。
#
# 仍是 stateless 决策（无 ukeire / shanten 计算），代价 O(N²)（N = hand 大小
# ≈ 14），无 wait_calculator 调用，比真 shanten AI 便宜 100×。
#
# 不接 立直 / 鸣牌 / 主动宣告（同 SimpleAi）—— 那些等真 player UI / agent。

# 同色牌 id 范围（一坨 9 个）—— 用于 distance 检查
const _SUITED_RANGES: Array = [
	# 万 W1..W9
	[TileId.W1, TileId.W9],
	# 筒 T1..T9
	[TileId.T1, TileId.T9],
	# 索 S1..S9
	[TileId.S1, TileId.S9],
]

func _init(seed_arg: int = 0) -> void:
	super(seed_arg)

func decide_discard(seat: Seat) -> Tile:
	var hand_tiles: Array = seat.hand._tiles
	if hand_tiles.is_empty():
		return null
	# 1) 计 hand 中每个 tile_id 的出现次数（用于"同 id 重复"加分 = 不弃）
	var counts: Dictionary = {}
	for t in hand_tiles:
		counts[t.id] = int(counts.get(t.id, 0)) + 1

	# 2) 给每张牌算"保留分"：高分 = 越值得保留 → 不弃；低分 = 弃。
	var best_idx: int = 0
	var best_score: int = 999
	for i in range(hand_tiles.size()):
		var t: Tile = hand_tiles[i]
		var score: int = _retention_score(t, counts)
		if score < best_score:
			best_score = score
			best_idx = i
	return hand_tiles[best_idx]

# 越大 = 越值得留。tie-break：第一个最低分的丢。
static func _retention_score(t: Tile, counts: Dictionary) -> int:
	var score: int = 0
	# 重复数：每多 1 张同 id 加 3 分（pair/triplet 强）
	var dup: int = int(counts.get(t.id, 0))
	score += (dup - 1) * 3  # 单张 = 0 分；对子 = 3；刻子 = 6
	# 同色邻居（数牌专属，字牌跳过）
	var rng: Array = _suited_range_for(t.id)
	if not rng.is_empty():
		# 同色 ±2 范围内的"是否存在邻居"（不重复计自身 dup）
		var lo: int = max(rng[0], t.id - 2)
		var hi: int = min(rng[1], t.id + 2)
		for nid in range(lo, hi + 1):
			if nid == t.id:
				continue
			if counts.has(nid):
				score += 2  # 邻居一张加 2 分
	# 字牌没有邻居 → 单张字牌天然孤立 → 自然先弃
	return score

static func _suited_range_for(tile_id: int) -> Array:
	for rng in _SUITED_RANGES:
		if tile_id >= rng[0] and tile_id <= rng[1]:
			return rng
	return []
