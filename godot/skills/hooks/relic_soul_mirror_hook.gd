# 魂镜 — 遗物（被动）
# WIN_DECLARED（结算后）：任一对手胡牌后，从其本次实际获得的点数（points_won）
# 转移 5% 给 owner，向下取整到 100；每件按原始本次得点独立计算
# （spec 2026-07-28 §4.1 / §2.3）。
extends SkillHook

const TRANSFER_FRACTION: float = 0.05

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat == ctx.beneficiary_seat:
		return
	var points_won: int = int(event.extra.get("points_won", 0))
	var amount: int = int(points_won * TRANSFER_FRACTION) / 100 * 100
	if amount <= 0:
		return
	ctx.transfer_points(event.actor_seat, ctx.beneficiary_seat, amount)
