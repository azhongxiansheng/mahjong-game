# 宝牌护符 — 战斗消耗品
# 效果：owner 下次胡牌额外 +3 Dora（一次性）
extends SkillHook

const DORA_BONUS: int = 3

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, DORA_BONUS)
	ctx.consume_self()
