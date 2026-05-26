# 久・悪待ちマスター — 能力
# 非標準待ち（単騎/嵌張/シャンポン）の達人。
# v1 簡略化：任意の自胡で +2 番（悪待ち熟練を表現）。
# 触発：WIN_DECLARED_PRE + actor == beneficiary
extends SkillHook

const BAD_WAIT_BONUS: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, BAD_WAIT_BONUS)
