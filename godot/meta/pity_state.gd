class_name PityState extends RefCounted

# 麻将王 — 里程碑 5 第 1 步：抽卡保底状态（spec §9.2 + plan-5 D3）
#
# 节点单抽：连续 8 次无史诗+ → 下一抽必史诗+。状态跨 Run 可持久化（M5 第 2
# 步 SaveSystem 实装；本步仅数据 + GUT 单测）。

const NODE_SINGLE_PITY_THRESHOLD: int = 8

var node_single_no_epic_streak: int = 0  # 节点单抽连续 N 次未出史诗+

# 调用方在每次"节点单抽 + 出卡 + 知道 rarity"后调一次。
func record_draw(rarity: int) -> void:
	if Rarity.is_epic_or_above(rarity):
		node_single_no_epic_streak = 0
	else:
		node_single_no_epic_streak += 1

# 是否处于"下一抽必史诗+"状态
func node_single_pity_active() -> bool:
	return node_single_no_epic_streak >= NODE_SINGLE_PITY_THRESHOLD

# Run 重置时调（开始新 Run 时清状态；M5 第 2 步元进度可选择跨 Run 保留）
func reset() -> void:
	node_single_no_epic_streak = 0
