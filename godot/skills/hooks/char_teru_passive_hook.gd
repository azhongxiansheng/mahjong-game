# 宫永照 — 角色被动「照魔鏡」
# 原著：连续和了时每次 han 累积增加（无上限）。
# 效果：每次胡牌 +1 番，且 bonus 不重置（同局内持续累积）。
# 用 SkillResource.params["streak"] 存计数器。
extends SkillHook

func on_event(skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var streak: int = int(skill.params.get("streak", 0)) + 1
	skill.params["streak"] = streak
	ctx.add_han(ctx.beneficiary_seat, streak)
