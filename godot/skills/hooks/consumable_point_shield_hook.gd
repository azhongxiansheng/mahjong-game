# 点棒护盾 — 战斗消耗品
# RON_DECLARED: owner 被荣胡时偷回 50% 点数并消耗自身
extends SkillHook

const STEAL_FRACTION: float = 0.50

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return
	ctx.steal_score(event.actor_seat, ctx.beneficiary_seat, STEAL_FRACTION)
	ctx.consume_self()
