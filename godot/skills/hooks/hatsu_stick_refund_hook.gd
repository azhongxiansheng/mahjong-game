# 发·点棒返还 — §8.6 立直系
#
# v2: owner 自胡时额外获得 1000 点（模拟立直棒成本被 skill 吸收）。
# 用 transfer_points 从最末位对手转 1000 给 owner。
extends SkillHook

const REFUND_AMOUNT: int = 1000

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var lowest_seat: int = -1
	var lowest_score: int = 999999
	for i in range(4):
		if i == ctx.beneficiary_seat:
			continue
		var s: int = ctx.get_score(i)
		if s < lowest_score:
			lowest_score = s
			lowest_seat = i
	if lowest_seat >= 0:
		ctx.transfer_points(lowest_seat, ctx.beneficiary_seat, REFUND_AMOUNT)
