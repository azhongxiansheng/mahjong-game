# 5万·闪电 — §8.1 增番系
# owner 持此牌且自己胡牌 → +1 番（数值由 BalanceConstants 控制）
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var bonus: int = int(BalanceConstants.lookup(&"thunder_5w_han_bonus"))
	ctx.add_han(ctx.beneficiary_seat, bonus)
