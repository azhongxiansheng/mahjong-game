# 红线 — 遗物（被动）
# WIN_DECLARED_PRE: owner 胡牌时 +1 赤 Dora（永久生效）
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.mark_red_dora_for_seat(ctx.beneficiary_seat, 1)
