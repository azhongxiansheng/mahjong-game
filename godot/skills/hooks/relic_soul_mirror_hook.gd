# 魂镜 — 遗物（被动）
# 对手每次胡牌时从对手转 10% 得分给 owner（永久生效）
extends SkillHook

const STEAL_FRACTION: float = 0.10

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat == ctx.beneficiary_seat:
		return
	ctx.steal_score(event.actor_seat, ctx.beneficiary_seat, STEAL_FRACTION)
