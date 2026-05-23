# 招财猫 — 遗物（被动）
# 每次胡牌额外 +1 Dora（永久生效，不消耗）
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, 1)
