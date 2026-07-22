# 连曜真 — 角色被动「叠曜连斩」
# ability_id: char_teru_passive_v1（语义冻结）
# 效果：每次胡牌 +N 番（N=同局连胡次数）；用 params["streak"] 计数。
extends SkillHook

func on_event(skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var streak: int = int(skill.params.get("streak", 0)) + 1
	skill.params["streak"] = streak
	ctx.add_han(ctx.beneficiary_seat, streak)
