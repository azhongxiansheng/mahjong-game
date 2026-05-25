# 燕返し — 一回限りの伝説能力
# WIN_DECLARED_PRE 自胡時 +3 番、使用後に consume_self で消滅。
# 触発：WIN_DECLARED_PRE + actor == beneficiary
extends SkillHook

const TSUBAME_BONUS: int = 3

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, TSUBAME_BONUS)
	ctx.consume_self()
