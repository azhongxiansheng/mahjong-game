# 逆转王冠 — 遗物（被动）
# WIN_DECLARED_PRE: owner 四家最低分时胡牌 +2 番（永久生效）
extends SkillHook

const COMEBACK_HAN: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var owner: int = ctx.beneficiary_seat
	var owner_score: int = ctx._state.scores[owner]
	for i in range(4):
		if i == owner:
			continue
		if ctx._state.scores[i] < owner_score:
			return  # 有人比 owner 低，不是最低
	# owner 是最低（含并列最低也触发）
	ctx.add_han(owner, COMEBACK_HAN)
