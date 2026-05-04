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

# M8.5：strategic context 注入（GameDriver / BattleNodeRunner 可选调用）。
# 默认为空 → AI 维持 M7 stateless 行为。设值后开启终局策略：
# 半庄南场尾盘 + 自家排名第 1 时不立直（防止立直棒丢失 + 振听被反超）。
var _cumulative_scores: Array[int] = []
var _hand_index: int = 0
var _total_hands: int = 0  # 0 = 未注入

func set_strategic_context(scores: Array, hand_index: int, total_hands: int) -> void:
	_cumulative_scores.clear()
	for s in scores:
		_cumulative_scores.append(int(s))
	_hand_index = hand_index
	_total_hands = total_hands

# 计 seat_id 当前累计分排名（1 最高，4 最低）。同分时 rank_for 不裁决
# （AI 决策侧不需要 sim 公平裁决；返最高 rank 是保守选择）。
# context 未注入时返 0 表示中性（不应触发任何 strategic 分支）。
func _rank_for(seat_id: int) -> int:
	if _cumulative_scores.is_empty():
		return 0
	if seat_id < 0 or seat_id >= _cumulative_scores.size():
		return 0
	var my_score: int = _cumulative_scores[seat_id]
	var rank := 1
	for i in range(_cumulative_scores.size()):
		if i == seat_id:
			continue
		if _cumulative_scores[i] > my_score:
			rank += 1
	return rank

# Endgame = 剩 ≤ 2 局（hand_index >= total_hands - 2）。
# 半庄战 8 局 → endgame 始于 hand_index=6（南 3）；
# 东风战 4 局 → endgame 始于 hand_index=2（东 3，合理终盘）。
func _is_endgame() -> bool:
	if _total_hands <= 0:
		return false
	return _hand_index >= _total_hands - 2

# 终局 + 自家第 1 → 跳过立直（保守）。其它情况按 M7 默认决策。
func _should_skip_riichi(seat_id: int) -> bool:
	if not _is_endgame():
		return false
	return _rank_for(seat_id) == 1

# M7：tenpai 时自动立直。判定走 RiichiValidator（门清 + 听牌 + 1000 点 +
# 牌墙剩 4）。本 AI 无策略，能立直就立直；M8+ 玩家 UI 替换为玩家选择。
# M8.5：终局领先时跳过立直（_should_skip_riichi）。
func decide_riichi(seat: Seat, wall_live_size: int) -> bool:
	if not RiichiValidator.can_declare_riichi(seat, wall_live_size):
		return false
	if _should_skip_riichi(seat.seat_id):
		return false
	return true

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
