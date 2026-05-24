# 中·封印+ — 升级版
# 基础版取消 ron + 消耗 → 升级版取消 ron 不消耗（可反复触发）
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return
	ctx.cancel_ron(event.actor_seat)
