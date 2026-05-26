# 龙印 — 遗物（被动）
# WIN_DECLARED_PRE: owner 胡牌时 +1 番（三元牌加成）（永久生效）
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, 1)
