# 速攻鬼 — 遗物（被动）
# WIN_DECLARED_PRE: owner 胡牌且 turn_count < 8 时 +1 番（永久生效）
extends SkillHook

const TURN_THRESHOLD: int = 8

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	if ctx._state.turn_count >= TURN_THRESHOLD:
		return
	ctx.add_han(ctx.beneficiary_seat, 1)
