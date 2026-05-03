# 5筒·解除振听 — §8.6 立直系
# owner 立直后违反摸切发生振听时,可消耗此牌清除 FuritenState
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	if not ctx.is_furiten(ctx.beneficiary_seat):
		return  # 没振听不触发,避免无意义消耗
	ctx.clear_furiten(ctx.beneficiary_seat)
	ctx.consume_self()
