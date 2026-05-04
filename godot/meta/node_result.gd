class_name NodeResult extends RefCounted

# 麻将王 — 里程碑 4 第 1 步：节点结算（plan-4 D4）
#
# spec §7.1 排名 → hp_delta 映射；plan-4 D4 拍板金币奖励 30/15/5/0。
# M7：数值改为运行时从 BalanceConstants 取（plan-7 D2 集中表），让 D6 调参 PR
# 改 BalanceConstants 即生效，无需改 NodeResult。
#
# 历史背景：本类原 hardcode `const HP_DELTA_BY_RANK = [0,0,0,-1,-2]`（5 元素含
# rank 0 占位）；BalanceConstants 平行存了 `node_rank_hp_delta = [0,0,-1,-2]`
# （4 元素，0-indexed = rank 1）。两份定义 drift → 任何 BalanceConstants tune
# 不实际生效。本 commit 把 NodeResult 切到 BalanceConstants 单源。

const CARD_REWARD_PER_NODE: int = 1

var rank: int = 1
var hp_delta: int = 0
var gold_reward: int = 0
var card_reward: int = 0
var final_scores: Array = []  # 4 家最终 cumulative_scores（来自 GameDriver）

func _init(p_rank: int = 1, p_final_scores: Array = []) -> void:
	rank = clampi(p_rank, 1, 4)
	hp_delta = _hp_delta_for_rank(rank)
	gold_reward = _gold_for_rank(rank)
	card_reward = CARD_REWARD_PER_NODE
	final_scores = p_final_scores

# 取 BalanceConstants 的 4 元素数组并把 rank（1..4）映射到 0..3 索引。
static func _hp_delta_for_rank(r: int) -> int:
	var arr: Array = BalanceConstants.get_array(&"node_rank_hp_delta")
	return int(arr[clampi(r, 1, 4) - 1])

static func _gold_for_rank(r: int) -> int:
	var arr: Array = BalanceConstants.get_array(&"node_rank_gold_reward")
	return int(arr[clampi(r, 1, 4) - 1])

# 静态：从 4 家累计分推 viewer_seat 的排名（1=最高，4=最低）。
#
# 同分裁决：
# - 默认（tiebreak_seed = 0）：viewer 永远赢同分（v1 行为，向后兼容）
# - 公平模式（tiebreak_seed > 0）：用 seed 决定性 shuffle 同分群再分配
#   排名。让 simulation 等批量场景不被 "viewer 永远 rank 1 in tie" 偏置干扰
#   —— baseline 1-4 累积观察：纯流局对局 4 家恒同分 25000，旧逻辑下
#   viewer 永远 rank 1 → 玩家几乎不可能扣血（rank 1-2 都 0 hp_delta）。
#
# 调用方在 simulation 应传与节点关联的 seed（如 node_seed 派生）；
# 实际游戏 UI 路径暂用默认参数（保留 viewer 友好的 v1 行为，避免改变玩家体验）。
static func rank_for_seat(scores: Array, viewer_seat: int, tiebreak_seed: int = 0) -> int:
	if viewer_seat < 0 or viewer_seat >= scores.size():
		return 4
	var my_score: int = int(scores[viewer_seat])
	var rank := 1
	var ties: Array[int] = []  # 与 viewer 同分的 seat_id 列表（不含 viewer）
	for i in range(scores.size()):
		if i == viewer_seat:
			continue
		var s: int = int(scores[i])
		if s > my_score:
			rank += 1
		elif s == my_score:
			ties.append(i)
	if tiebreak_seed > 0 and not ties.is_empty():
		# Fisher-Yates shuffle [viewer + ties]，viewer 在 shuffled 中的位置
		# = 同分群里第几名（0-based 偏移加到 base rank）
		var pool: Array[int] = ties.duplicate()
		pool.append(viewer_seat)
		var rng := RandomNumberGenerator.new()
		rng.seed = tiebreak_seed
		for i in range(pool.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp: int = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
		rank += pool.find(viewer_seat)
	return rank

# 占位节点（CAMP / SHOP / EVENT）的"无对战"结算。
# 不掉血、不给金币、不给抽卡（这些资源由占位场景内部 hook 给，M5 实装）。
static func from_placeholder() -> NodeResult:
	var r := NodeResult.new(2)
	r.gold_reward = 0
	r.card_reward = 0
	return r

# ---- 序列化（M5 SaveSystem） ----

func to_dict() -> Dictionary:
	return {
		"rank": rank,
		"hp_delta": hp_delta,
		"gold_reward": gold_reward,
		"card_reward": card_reward,
		"final_scores": final_scores.duplicate(),
	}

static func from_dict(d: Dictionary) -> NodeResult:
	if d == null or d.is_empty():
		return null
	var r := NodeResult.new(int(d.get("rank", 1)), d.get("final_scores", []).duplicate())
	# 反序列化时尊重原 hp_delta / gold_reward（rank 派生的可能与历史不一致）
	r.hp_delta = int(d.get("hp_delta", r.hp_delta))
	r.gold_reward = int(d.get("gold_reward", r.gold_reward))
	r.card_reward = int(d.get("card_reward", r.card_reward))
	return r
