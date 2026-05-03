# 发·吸魂 — §8.4 抓马反向得分系(holder 触发)
# 任意对手胡牌时,holder 反获得对手得分的 30%
# event.extra: {"points_won": int}
extends SkillHook

# FRACTION 已迁移到 BalanceConstants (&"soul_drain_fraction")。

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat == ctx.beneficiary_seat:
		return  # holder 自胡不触发
	var points_won: int = int(event.extra.get("points_won", 0))
	if points_won <= 0:
		return
	var fraction: float = BalanceConstants.get_number(&"soul_drain_fraction")
	var amount := int(points_won * fraction)
	ctx.transfer_points(event.actor_seat, ctx.beneficiary_seat, amount)
