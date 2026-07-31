# 倍率券 — 战斗消耗品
# 效果：owner 下次合法胡牌结算前总番 ×2；由此额外获得的番至多 3，役满不放大
# （上限与役满豁免由 BattleController._apply_han_multiplier 应用；spec 2026-07-28 §3.1）
extends SkillHook

const EXTRA_HAN_CAP: int = 3

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.multiply_han_for_seat(ctx.beneficiary_seat, 2.0, EXTRA_HAN_CAP)
	ctx.consume_self()
