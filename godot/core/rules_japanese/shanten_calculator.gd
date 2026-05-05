class_name ShantenCalculator

# 麻将王 — M10 Path A：向听数（shanten）计算器
#
# 给定一手 13 张（含或不含副露的等价 13 牌）— 返"距离听牌还差几张换"。
# 0 = tenpai（已听）；N = 还差 N 步。
#
# 三种和牌型分别算 shanten 取 min：
#   - standard：4 mentsu + 1 pair（含副露折抵）
#   - chiitoi：7 对子（仅 0 副露才合法）
#   - kokushi：13 幺九（仅 0 副露才合法）
#
# v1 用递归枚举 + 顺位分解；性能不极致但 13-14 牌 hand 单次 < 5 ms 足以
# AI 决策用。Phase 2 若需更快可换"花色 DP + 拼合表"。
#
# WaitCalculator.is_tenpai 保留作 yes/no 早退；本 calculator 在更早期阶段
# (shanten >= 1) 给 AI 选择"使 shanten 降到更小"的弃牌候选。

# ---- 公共入口 ----

# 计算 hand + called_melds 的最小向听数。
# 输入 hand 应为 13 张暗手牌（鸣牌后扣减后的剩余暗手）。
# called_melds 个数表示已副露的面子数（每个折抵 1 个 mentsu）。
static func calc(hand: Hand, called_melds: Array = []) -> int:
	var counts: Array[int] = _hand_to_counts(hand)
	var calls: int = called_melds.size()
	var standard: int = _calc_standard(counts, calls)
	if calls > 0:
		# 鸣牌后只能走 standard（chiitoi/kokushi 都需门前清）
		return standard
	var chiitoi: int = _calc_chiitoi(counts)
	var kokushi: int = _calc_kokushi(counts)
	return min(min(standard, chiitoi), kokushi)

# 仅算 standard（如调用方已知不可能 chiitoi/kokushi 时省一点）。
static func calc_standard(hand: Hand, called_melds: Array = []) -> int:
	var counts: Array[int] = _hand_to_counts(hand)
	return _calc_standard(counts, called_melds.size())

# ---- 内部 ----

static func _hand_to_counts(hand: Hand) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(34)
	counts.fill(0)
	for t in hand._tiles:
		counts[t.id] += 1
	return counts

# Chiitoi 公式：6 - pairs + max(0, 7 - kinds)
# 其中 pairs = count >= 2 的不同 tile 种类；kinds = count >= 1 的不同 tile 种类。
# 直觉：每对算 -1 step，但 kinds 不到 7 必须再凑新 tile（每差 1 种 +1 step）。
# 注意：刻子/杠也只按"1 对"贡献，多余张数算"无用"。
static func _calc_chiitoi(counts: Array[int]) -> int:
	var pairs: int = 0
	var kinds: int = 0
	for c in counts:
		if c >= 1: kinds += 1
		if c >= 2: pairs += 1
	var s: int = 6 - pairs
	if kinds < 7:
		s += 7 - kinds
	return s

# Kokushi 公式：13 - distinct_yaochu - (1 if 任一幺九成对 else 0)
const _YAOCHU_IDS: Array[int] = [
	TileId.W1, TileId.W9,
	TileId.T1, TileId.T9,
	TileId.S1, TileId.S9,
	TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
	TileId.HAKU, TileId.HATSU, TileId.CHUN,
]

static func _calc_kokushi(counts: Array[int]) -> int:
	var distinct: int = 0
	var has_pair: bool = false
	for tid in _YAOCHU_IDS:
		if counts[tid] >= 1: distinct += 1
		if counts[tid] >= 2: has_pair = true
	return 13 - distinct - (1 if has_pair else 0)

# Standard：尝试每种"对子选择"（无 / 每种 count>=2 的 tile 作雀头），
# 剩余手牌跑递归分解出最大 (mentsu, taatsu)；按公式算 shanten 取 min。
#
# 公式（已副露 c 面子时）：
#   shanten = 8 - 2*(c + mentsu) - taatsu - (1 if pair else 0)
#   约束：c + mentsu + taatsu ≤ (4 if pair else 5)
#   （pair 时正好 4 块 + 1 雀头；no pair 时最多 5 块用一块作雀头候选）
#   超额时 cap：taatsu = max_blocks - (c + mentsu)
static func _calc_standard(counts: Array[int], called: int) -> int:
	var best: int = 8 - 2 * called
	# M10 perf：memoization 缓存。同一 _calc_standard 调用内的 5 次（无对 + 4 种对子）
	# _max_blocks 共享 cache；同子结构（counts 后缀 + idx 起点）只算一次。
	# 实测 14 牌 hand 单次 calc 从 ~5 ms 降到 < 1 ms（5-10× speedup）。
	var cache: Dictionary = {}
	# 不选雀头
	var no_pair_blocks: Array = _max_blocks(counts.duplicate(), cache)
	best = min(best, _shanten_from_blocks(no_pair_blocks[0], no_pair_blocks[1], false, called))
	# 每种可选雀头
	for tid in range(34):
		if counts[tid] >= 2:
			counts[tid] -= 2
			var blocks: Array = _max_blocks(counts.duplicate(), cache)
			counts[tid] += 2
			best = min(best, _shanten_from_blocks(blocks[0], blocks[1], true, called))
	return best

static func _shanten_from_blocks(mentsu: int, taatsu: int, has_pair: bool, called: int) -> int:
	var total_mentsu: int = mentsu + called
	var max_blocks: int = 4 if has_pair else 5
	# cap：mentsu + taatsu 总块数不超 max_blocks（多余 taatsu 不再贡献）
	var blocks_used: int = min(total_mentsu + taatsu, max_blocks)
	# total_mentsu 已固定（called 是确定的，新 mentsu 也是已识别）
	# 多余 taatsu cap 掉
	var capped_taatsu: int = blocks_used - total_mentsu
	if capped_taatsu < 0:
		capped_taatsu = 0
	return 8 - 2 * total_mentsu - capped_taatsu - (1 if has_pair else 0)

# 递归分解：从 tile 0 起扫描，为每个非零 tile 尝试所有切法（mentsu / taatsu / 跳过），
# 取最大的 (2*mentsu + taatsu) 评分。
# 返 [max_mentsu_at_best, max_taatsu_at_best]
# cache: Dictionary（_calc_standard 一次性创建，跨 5 次 _max_blocks 共享）。
static func _max_blocks(counts: Array[int], cache: Dictionary) -> Array:
	# 找第一个非零起点
	var start: int = 0
	while start < 34 and counts[start] == 0:
		start += 1
	if start >= 34:
		return [0, 0]
	return _decompose(counts, start, cache)

# Cache key 编码：String 由 idx + counts[0..33] 数字串组合（每位 [0,4] 单 char 即可）。
# Godot Dictionary 用 String key 命中正确。
static func _cache_key(counts: Array[int], idx: int) -> String:
	# 形如 "12:0010040030..." — 长度固定 37（idx 2 + ":" + 34 digits）
	var s: String = str(idx) + ":"
	for c in counts:
		s += str(c)
	return s

static func _decompose(counts: Array[int], idx: int, cache: Dictionary) -> Array:
	# 跳过零计 tile 直到下一个非零或越界
	while idx < 34 and counts[idx] == 0:
		idx += 1
	if idx >= 34:
		return [0, 0]

	# memo 命中？
	var key: String = _cache_key(counts, idx)
	if cache.has(key):
		return cache[key]

	var best: Array = [0, 0]
	var best_score: int = -1
	var n_in_suit: int = TileId.number(idx)  # 1..9 数牌；字牌返 0
	var is_honor: bool = TileId.is_honor(idx)

	# 选项 1：刻子（同 tile × 3）
	if counts[idx] >= 3:
		counts[idx] -= 3
		var sub: Array = _decompose(counts, idx, cache)
		counts[idx] += 3
		var cand: Array = [sub[0] + 1, sub[1]]
		var sc: int = cand[0] * 2 + cand[1]
		if sc > best_score:
			best = cand
			best_score = sc

	# 选项 2：顺子（idx, idx+1, idx+2）— 仅数牌，n ≤ 7
	if not is_honor and n_in_suit <= 7 and counts[idx] >= 1 and counts[idx + 1] >= 1 and counts[idx + 2] >= 1:
		counts[idx] -= 1; counts[idx + 1] -= 1; counts[idx + 2] -= 1
		var sub2: Array = _decompose(counts, idx, cache)
		counts[idx] += 1; counts[idx + 1] += 1; counts[idx + 2] += 1
		var cand2: Array = [sub2[0] + 1, sub2[1]]
		var sc2: int = cand2[0] * 2 + cand2[1]
		if sc2 > best_score:
			best = cand2
			best_score = sc2

	# 选项 3a：对子搭子（同 tile × 2）— 这里"对子"作 taatsu 候选（升级雀头由外层 _calc_standard 处理）
	if counts[idx] >= 2:
		counts[idx] -= 2
		var sub3: Array = _decompose(counts, idx, cache)
		counts[idx] += 2
		var cand3: Array = [sub3[0], sub3[1] + 1]
		var sc3: int = cand3[0] * 2 + cand3[1]
		if sc3 > best_score:
			best = cand3
			best_score = sc3

	# 选项 3b：两面/边张搭子（idx, idx+1）— 仅数牌，n ≤ 8
	if not is_honor and n_in_suit <= 8 and counts[idx] >= 1 and counts[idx + 1] >= 1:
		counts[idx] -= 1; counts[idx + 1] -= 1
		var sub4: Array = _decompose(counts, idx, cache)
		counts[idx] += 1; counts[idx + 1] += 1
		var cand4: Array = [sub4[0], sub4[1] + 1]
		var sc4: int = cand4[0] * 2 + cand4[1]
		if sc4 > best_score:
			best = cand4
			best_score = sc4

	# 选项 3c：嵌张搭子（idx, idx+2）— 仅数牌，n ≤ 7
	if not is_honor and n_in_suit <= 7 and counts[idx] >= 1 and counts[idx + 2] >= 1:
		counts[idx] -= 1; counts[idx + 2] -= 1
		var sub5: Array = _decompose(counts, idx, cache)
		counts[idx] += 1; counts[idx + 2] += 1
		var cand5: Array = [sub5[0], sub5[1] + 1]
		var sc5: int = cand5[0] * 2 + cand5[1]
		if sc5 > best_score:
			best = cand5
			best_score = sc5

	# 选项 4：跳过 1 张（单骑游离张，不组任何块）
	counts[idx] -= 1
	var sub6: Array = _decompose(counts, idx, cache)
	counts[idx] += 1
	var sc6: int = sub6[0] * 2 + sub6[1]
	if sc6 > best_score:
		best = sub6
		best_score = sc6

	cache[key] = best
	return best
