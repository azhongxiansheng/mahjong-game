# 園城寺怜 — 先見能力
# GAME_BEGIN 時に全 4 席の次の摸牌を owner に reveal。
# コスト：owner から 1000 点を seat (owner+1)%4 に移動（v1 簡略化）。
# 触発：GAME_BEGIN
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
