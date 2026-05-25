# 7筒·一发延长 — 牌技能（立直系）
# WIN_DECLARED_PRE: owner 立直状态下胡牌时 +1 番
# （v1 简化：以立直状态代替严格一发判定）
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
