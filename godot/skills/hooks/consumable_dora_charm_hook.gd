# 宝牌护符 — 战斗消耗品
# 效果：owner 下次胡牌额外 +2 Dora（一次性；荣和/自摸均可；spec 2026-07-28 §3.1）
extends SkillHook

const DORA_BONUS: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, DORA_BONUS)
	ctx.consume_self()
