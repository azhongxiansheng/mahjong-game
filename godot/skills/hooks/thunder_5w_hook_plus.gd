# 5万·闪电+ — 升级版
# 基础版番数 ×2（升级后效果翻倍）
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var base: int = int(BalanceConstants.lookup(&"thunder_5w_han_bonus"))
	ctx.add_han(ctx.beneficiary_seat, base * 2)
