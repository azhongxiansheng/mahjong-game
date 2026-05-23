# 倍率券 — 战斗消耗品
# 效果：owner 下次胡牌番数 ×2（一次性）
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.multiply_han_for_seat(ctx.beneficiary_seat, 2.0)
	ctx.consume_self()
