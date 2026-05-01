class_name NodeResult extends RefCounted

# 麻将王 — 里程碑 4 第 1 步：节点结算（plan-4 D4）
#
# spec §7.1 排名 → hp_delta 映射；plan-4 D4 拍板金币奖励 30/15/5/0。
# v1 数值非架构性，里程碑 7 平衡时再调。

const HP_DELTA_BY_RANK: Array = [0, 0, 0, -1, -2]   # [-, rank1, rank2, rank3, rank4]
const GOLD_BY_RANK: Array = [0, 30, 15, 5, 0]
const CARD_REWARD_PER_NODE: int = 1

var rank: int = 1
var hp_delta: int = 0
var gold_reward: int = 0
var card_reward: int = 0
var final_scores: Array = []  # 4 家最终 cumulative_scores（来自 GameDriver）

func _init(p_rank: int = 1, p_final_scores: Array = []) -> void:
	rank = clampi(p_rank, 1, 4)
	hp_delta = HP_DELTA_BY_RANK[rank]
	gold_reward = GOLD_BY_RANK[rank]
	card_reward = CARD_REWARD_PER_NODE
	final_scores = p_final_scores

# 静态：从 4 家累计分推 viewer_seat 的排名（1=最高，4=最低）。
# 同分时 viewer 优先得高排名（v1 简化；spec §14 末段提到平衡留 M7）。
static func rank_for_seat(scores: Array, viewer_seat: int) -> int:
	if viewer_seat < 0 or viewer_seat >= scores.size():
		return 4
	var my_score: int = int(scores[viewer_seat])
	var rank := 1
	for i in range(scores.size()):
		if i == viewer_seat:
			continue
		if int(scores[i]) > my_score:
			rank += 1
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
