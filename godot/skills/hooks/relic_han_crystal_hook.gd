# 番水晶 — 遗物（被动）
# WIN_DECLARED_PRE: owner 立直状态下胡牌时 +1 番（永久生效）
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var owner: int = ctx.beneficiary_seat
	if owner < 0 or owner >= ctx._state.seats.size():
		return
	var seat: Seat = ctx._state.seats[owner]
	if seat.riichi == null or not seat.riichi.declared:
		return
	ctx.add_han(owner, 1)
