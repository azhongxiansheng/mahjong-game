# 忍石 — 遗物（被动）
# EXHAUSTIVE_DRAW：荒牌流局时，owner 听牌则额外获得 1000 点（外部注入，
# HandSettlement 记 EXTERNAL adjustment）；未听牌不触发；途中流局（ABORTIVE_DRAW）
# 不在触发器内（spec 2026-07-28 §4.1）。
extends SkillHook

const BONUS_POINTS: int = 1000

func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	var owner: int = ctx.beneficiary_seat
	if owner < 0 or owner >= ctx._state.seats.size():
		return
	var seat: Seat = ctx._state.seats[owner]
	if seat.hand.size() != 13:
		return
	if WaitCalculator.wait_tiles(seat.hand, seat.melds.all()).is_empty():
		return
	ctx._state.scores[owner] += BONUS_POINTS
