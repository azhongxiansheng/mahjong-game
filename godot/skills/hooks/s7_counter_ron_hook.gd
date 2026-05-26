# 7索·反击 — 牌技能（抓马反向得分系）
# RON_DECLARED: owner 被荣胡时从胜者偷回 20% 得分
extends SkillHook

const STEAL_FRACTION: float = 0.20

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return
	ctx.steal_score(event.actor_seat, ctx.beneficiary_seat, STEAL_FRACTION)
