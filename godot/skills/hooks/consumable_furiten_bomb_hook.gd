# 振听炸弹 — 战斗消耗品
# WIN_DECLARED_PRE: 取消所有对手的荣胡（1 次性）
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat == ctx.beneficiary_seat:
		return  # owner 自己胡不阻止
	ctx.cancel_ron(event.actor_seat)
	ctx.consume_self()
