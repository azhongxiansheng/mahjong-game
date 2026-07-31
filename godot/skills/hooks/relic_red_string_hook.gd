# 红线 — 遗物（被动）
# WIN_DECLARED_PRE：owner 以门清手牌胡牌时 +1 赤 Dora（spec 2026-07-28 §4.1）。
# 副露手（含碰/吃/明杠/加杠）不触发；暗杠保持门清。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var owner: int = ctx.beneficiary_seat
	if owner < 0 or owner >= ctx._state.seats.size():
		return
	var seat: Seat = ctx._state.seats[owner]
	if not seat.is_concealed_hand():
		return
	ctx.mark_red_dora_for_seat(owner, 1)
