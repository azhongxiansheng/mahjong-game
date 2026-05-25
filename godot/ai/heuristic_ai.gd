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

# Endgame = 剩 ≤ N 局（hand_index >= total_hands - N），N 来自 BalanceConstants。
# baseline 8 (PR #90) 显示 N=2 让玩家也跳过立直 → 攻击不足；M9 收窄到 N=1：
# 仅最后一局收紧（半庄南 4 / 东风战东 4），前一局正常立直。
func _is_endgame() -> bool:
	if _total_hands <= 0:
		return false
	var remaining_threshold: int = int(BalanceConstants.lookup(&"endgame_skip_riichi_remaining_hands"))
	return _hand_index >= _total_hands - remaining_threshold

# 显著领先时与第 2 名的点数差。context 未注入返 0。
func _lead_over_second(seat_id: int) -> int:
	if _cumulative_scores.is_empty():
		return 0
	if seat_id < 0 or seat_id >= _cumulative_scores.size():
		return 0
	if _rank_for(seat_id) != 1:
		return 0  # 不是第 1 → 无领先意义
	var my_score: int = _cumulative_scores[seat_id]
	var second_best: int = -2147483648
	for i in range(_cumulative_scores.size()):
		if i == seat_id:
			continue
		if _cumulative_scores[i] > second_best:
			second_best = _cumulative_scores[i]
	return my_score - second_best

# 终局 + 自家第 1 + **显著领先** → 跳过立直。
# M8.5 v1 在"任何领先即跳"过于激进 — baseline 7 让 AI 间不对称扩大
# （seat 1 领先后保护点数 → 强者越强，spread 翻倍）。M9 假设 P：仅当
# 领先 ≥ BalanceConstants.endgame_skip_riichi_lead_gap（默认 12000，
# 半庄子家满贯）才跳过；微弱领先仍立直让 spread 不无脑扩大。
func _should_skip_riichi(seat_id: int) -> bool:
	if not _is_endgame():
		return false
	if _rank_for(seat_id) != 1:
		return false
	var gap: int = _lead_over_second(seat_id)
	var threshold: int = int(BalanceConstants.lookup(&"endgame_skip_riichi_lead_gap"))
	return gap >= threshold

# M7：tenpai 时自动立直。判定走 RiichiValidator（门清 + 听牌 + 1000 点 +
# 牌墙剩 4）。本 AI 无策略，能立直就立直；M8+ 玩家 UI 替换为玩家选择。
# M8.5：终局领先时跳过立直（_should_skip_riichi）。
func decide_riichi(seat: Seat, wall_live_size: int) -> bool:
	if not RiichiValidator.can_declare_riichi(seat, wall_live_size):
		return false
	if _should_skip_riichi(seat.seat_id):
		return false
	return true

# M10 Path A：shanten-aware discard 开关。默认 false 保 M7 行为 / 旧测兼容；
# sim CLI / 想跑 shanten AI 的调用方设 true 后启用 ShantenCalculator 选弃牌。
var use_shanten_aware_discard: bool = false

func decide_discard(seat: Seat) -> Tile:
	var hand_tiles: Array = seat.hand._tiles
	if hand_tiles.is_empty():
		return null
	# M10：当开启 shanten-aware 且 hand 处于"刚抽完"等待弃牌的状态（14 张 / 暗 +
	# 副露 = 14 等价），用 shanten 选弃牌；其他场景（hand 不饱满 / 关闭开关）走
	# 原 retention 启发式。
	if use_shanten_aware_discard and _is_post_draw_state(seat):
		var shanten_pick: Tile = _decide_discard_shanten(seat)
		if shanten_pick != null:
			return shanten_pick
	return _decide_discard_retention(hand_tiles)

# 13 暗 - 3*melds 是均衡态；+1 = 刚抽完待弃。
static func _is_post_draw_state(seat: Seat) -> bool:
	var hand_size: int = seat.hand._tiles.size()
	var meld_count: int = seat.melds.size() if seat.melds != null else 0
	return hand_size == 14 - 3 * meld_count

# M7 旧 retention 启发式（保留作 fallback / 小手测兼容）。
static func _decide_discard_retention(hand_tiles: Array) -> Tile:
	var counts: Dictionary = {}
	for t in hand_tiles:
		counts[t.id] = int(counts.get(t.id, 0)) + 1
	var best_idx: int = 0
	var best_score: int = 999
	for i in range(hand_tiles.size()):
		var t: Tile = hand_tiles[i]
		var score: int = _retention_score(t, counts)
		if score < best_score:
			best_score = score
			best_idx = i
	return hand_tiles[best_idx]

# Shanten-aware：尝试弃每张 → 计 13-暗剩手 shanten → pref 最小 shanten；
# 同 shanten 时 tie-break 用 retention（弃孤立 / 字牌 / 单张）。
# 注：shanten 越小越接近 tenpai；弃 = 暂从 hand 抽走 1 张算剩 13 张的 shanten。
func _decide_discard_shanten(seat: Seat) -> Tile:
	var hand_tiles: Array = seat.hand._tiles
	var melds: Array = seat.melds
	# 预算 retention 分（fallback / tie-break）
	var counts: Dictionary = {}
	for t in hand_tiles:
		counts[t.id] = int(counts.get(t.id, 0)) + 1
	# 对每个 tile_id 候选弃：移除一张后算 shanten；记最小 shanten 与 retention
	var best_idx: int = 0
	var best_shanten: int = 99
	var best_retention: int = 999  # 同 shanten 时取 retention 最小（最该弃）
	# 同 tile_id 重复出现时只算一次 shanten；选其中第一张的索引
	var seen: Dictionary = {}
	for i in range(hand_tiles.size()):
		var t: Tile = hand_tiles[i]
		if seen.has(t.id):
			continue
		seen[t.id] = true
		# 构造"弃这张后"的 13 暗 hand
		var hand_minus: Hand = _hand_minus_first(hand_tiles, t.id)
		var s: int = ShantenCalculator.calc(hand_minus, melds)
		var retention: int = _retention_score(t, counts)
		if s < best_shanten or (s == best_shanten and retention < best_retention):
			best_shanten = s
			best_retention = retention
			best_idx = i
	return hand_tiles[best_idx]

static func _hand_minus_first(hand_tiles: Array, tile_id: int) -> Hand:
	var h := Hand.new()
	var skipped: bool = false
	for t in hand_tiles:
		if not skipped and t.id == tile_id:
			skipped = true
			continue
		h.add(Tile.new(t.id, t.is_red_dora, t.owner_seat))
	return h

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

# ---- Self-kan decision (Task 3: claim window plan) ----
#
# After AI draws, check if ankan or added_kan is possible.
# Returns: {"kind": "ankan"|"added_kan", "tile_id": int} or {} (pass).
# Riichi blocks ankan (standard rules: riichi player cannot declare ankan
# unless it doesn't change wait shape — simplified here to "never ankan
# during riichi" which is the conservative/common interpretation).
func decide_self_kan(seat: Seat) -> Dictionary:
	# Ankan: 4 copies of any tile in hand (blocked during riichi)
	if not seat.riichi.declared:
		var ankan_ids: Array = ClaimValidator.ankan_candidates(seat.hand)
		if not ankan_ids.is_empty():
			return {"kind": "ankan", "tile_id": ankan_ids[0]}
	# Added kan: existing PON + 4th tile in hand
	for m in seat.melds:
		if m.kind == Meld.Kind.PON:
			var tid: int = m.tiles[0].id
			if seat.hand.count_of(tid) >= 1:
				return {"kind": "added_kan", "tile_id": tid}
	return {}

# ---- Claim decision (Task 4: claim window plan) ----
#
# When an opponent discards, decide whether to pon/minkan/chi.
# Takes Seat directly (BattleController has state access, passes the seat).
# Returns: {"kind": "pon"|"minkan"|"chi", ...} or {} (pass).
# Heuristic: always pon/minkan if possible (greedy); chi skipped for now
# (chi requires being shimocha and has more complex decision logic).
func decide_claim_for_seat(seat: Seat, discarded_id: int, discarder: int) -> Dictionary:
	if seat.seat_id == discarder:
		return {}
	# Minkan: 3 copies in hand
	if ClaimValidator.can_minkan(seat.seat_id, discarder, seat.hand, discarded_id):
		return {"kind": "minkan"}
	# Pon: 2 copies in hand
	if ClaimValidator.can_pon(seat.seat_id, discarder, seat.hand, discarded_id):
		return {"kind": "pon"}
	# Chi skipped for v1 heuristic (requires being shimocha + complex choice)
	return {}
