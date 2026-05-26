# 5筒·双摸 — 牌技能（增番系）
# WIN_DECLARED_PRE: owner 胡牌时 +1 番（v1 简化双摸为番数加成）
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, 1)
