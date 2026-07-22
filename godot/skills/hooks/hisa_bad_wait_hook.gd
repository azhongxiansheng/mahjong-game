# 恶听熟手 — 可抽能力（id: hisa_bad_wait_v1）
# 非标准听牌（单骑/嵌张/双碰）的熟练表现。
# v1 简化：任意自胡 +2 番。
# 触发：WIN_DECLARED_PRE + actor == beneficiary
extends SkillHook

const BAD_WAIT_BONUS: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, BAD_WAIT_BONUS)
