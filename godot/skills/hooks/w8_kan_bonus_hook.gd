# 8万·杠加成 — 牌技能（增番系）
# WIN_DECLARED_PRE: owner 胡牌时若有杠副露 +2 番
extends SkillHook

const KAN_HAN: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var owner: int = ctx.beneficiary_seat
	if owner < 0 or owner >= ctx._state.seats.size():
		return
	var seat: Seat = ctx._state.seats[owner]
	for m in seat.melds.all():
		if m.is_kan():
			ctx.add_han(owner, KAN_HAN)
			return
