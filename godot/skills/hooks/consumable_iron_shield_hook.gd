# 铁盾 — 战斗消耗品
# 效果：本局 owner 被荣胡时取消第 1 次（同 boss1_iron_curtain 但为消耗品）
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	var discarder: int = int(event.extra.get("discarder_seat", -1))
	if discarder != ctx.beneficiary_seat:
		return
	ctx.cancel_ron(event.actor_seat)
	ctx.consume_self()
