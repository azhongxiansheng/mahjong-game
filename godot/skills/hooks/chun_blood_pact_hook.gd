# 中·血盟 — 牌技能（终局系）
# WIN_DECLARED: owner 胡牌时从其它三家各转 1000 点（共 3000）
extends SkillHook

const TRANSFER_PER_SEAT: int = 1000

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var owner: int = ctx.beneficiary_seat
	for i in range(4):
		if i == owner:
			continue
		ctx.transfer_points(i, owner, TRANSFER_PER_SEAT)
