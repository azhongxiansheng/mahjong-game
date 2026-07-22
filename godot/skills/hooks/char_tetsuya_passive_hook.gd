# 局进吾 — 角色被动「阶升必杀」
# ability_id: char_tetsuya_passive_v1（语义冻结）
# 效果：WIN_DECLARED_PRE 自胡时 +(1+wins)；params["wins"] 累计胜利次数。
extends SkillHook

func on_event(skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var wins: int = int(skill.params.get("wins", 0))
	ctx.add_han(ctx.beneficiary_seat, 1 + wins)
	skill.params["wins"] = wins + 1
