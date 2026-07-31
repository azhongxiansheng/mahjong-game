# 点棒护盾 — 战斗消耗品
# WIN_DECLARED（结算后）：owner 放铳正常结算后，从和牌者本次荣和净得点
# （payout 各付家之和，不含立直棒）返还 30% 给 owner，向下取整到 100，然后消耗。
# 他家放铳与自摸不触发、不消耗（spec 2026-07-28 §3.1 / §2.3）。
extends SkillHook

const REFUND_FRACTION: float = 0.30

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if bool(event.extra.get("is_tsumo", false)):
		return
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return
	var winner: int = event.actor_seat
	if winner == ctx.beneficiary_seat:
		return
	var net: int = 0
	var payout: Dictionary = event.extra.get("payout", {})
	for v in payout.values():
		net += int(v)
	var refund: int = int(net * REFUND_FRACTION) / 100 * 100
	if refund > 0:
		ctx.transfer_points(winner, ctx.beneficiary_seat, refund)
	ctx.consume_self()
