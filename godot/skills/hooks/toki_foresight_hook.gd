# 可抽能力「巡初窥摸」— id: toki_foresight_v1（非角色被动）
extends SkillHook

const FORESIGHT_COST: int = 1000

func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	var owner: int = ctx.beneficiary_seat
	# Reveal next draw for all 4 seats to owner
	for seat in range(4):
		ctx.reveal_next_draw_for_seat(seat, owner)
	# Cost: transfer 1000 points from owner to next seat (v1 simplified cost sink)
	var sink_seat: int = (owner + 1) % 4
	ctx.transfer_points(owner, sink_seat, FORESIGHT_COST)
