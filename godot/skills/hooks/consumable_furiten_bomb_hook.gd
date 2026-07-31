# 振听炸弹 — 战斗消耗品
# RON_DECLARED：取消下一名对手声明的荣和，然后消耗（spec 2026-07-28 §3.1）。
# 不要求该荣和来自 owner 的舍牌；对自摸无效（自摸不发 RON_DECLARED）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat == ctx.beneficiary_seat:
		return  # owner 自己胡不阻止
	ctx.cancel_ron(event.actor_seat)
	ctx.consume_self()
