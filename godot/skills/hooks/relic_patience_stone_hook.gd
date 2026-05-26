# 忍石 — 遗物（被动）
# EXHAUSTIVE_DRAW: 流局时 owner 获得 +2000 点（永久生效，简化版不检查听牌）
extends SkillHook

const BONUS_POINTS: int = 2000

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	# 流局时给 owner +2000 点（从其它三家各扣一部分无法确定来源，
	# 简化为虚空生成：其它三家各扣 667 近似。
	# 更简单：直接用 transfer 无法确定谁出。最简实现：直接操 scores。）
	var owner: int = ctx.beneficiary_seat
	ctx._state.scores[owner] += BONUS_POINTS
