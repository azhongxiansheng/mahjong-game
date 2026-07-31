# 逆转王冠 — 遗物（被动）
# WIN_DECLARED_PRE：owner 胡牌声明时，严格全场最低分 +2 番；并列最低 +1 番
# （比较结算前分数；spec 2026-07-28 §4.1）。
extends SkillHook

const STRICT_LOWEST_HAN: int = 2
const TIED_LOWEST_HAN: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var owner: int = ctx.beneficiary_seat
	var owner_score: int = ctx._state.scores[owner]
	var strictly_lowest := true
	for i in range(4):
		if i == owner:
			continue
		if ctx._state.scores[i] < owner_score:
			return  # 有人比 owner 低，不触发
		if ctx._state.scores[i] == owner_score:
			strictly_lowest = false
	ctx.add_han(owner, STRICT_LOWEST_HAN if strictly_lowest else TIED_LOWEST_HAN)
