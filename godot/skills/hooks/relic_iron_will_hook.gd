# 铁壁意志 — 遗物（被动）
# 被荣胡时对手 -1 番（永久生效，不消耗）
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return
	ctx.add_han(event.actor_seat, -1)
