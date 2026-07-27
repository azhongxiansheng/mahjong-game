# 局进吾 — 角色被动「阶升必杀」
# ability_id: char_tetsuya_passive_v1（语义冻结）
# 效果：整场已武装的 owner 和牌依次 +1/+2/+3…；其他终局不重置。
extends SkillHook

func on_event(skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.type != &"WIN_DECLARED_PRE" \
			or event.actor_seat != ctx.beneficiary_seat:
		return
	var wins: int = int(skill.params.get("wins", 0))
	ctx.add_han(ctx.beneficiary_seat, 1 + wins)
	skill.params["wins"] = wins + 1
