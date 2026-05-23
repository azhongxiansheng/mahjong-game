# 4 索·指示牌操纵 — §8.8 Dora 系
#
# v2: mark_extra_dora_for_seat 语义升级。owner 自胡时额外获得 dora 计数，
# 等价于"重选裏 Dora 指示牌后平均最优收益"。数值由 BalanceConstants 控制。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, int(BalanceConstants.lookup(&"sou4_uradora_han_bonus")))
