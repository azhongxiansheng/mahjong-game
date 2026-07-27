# 连曜真 — 角色被动「叠曜连斩」
# ability_id: char_teru_passive_v1（语义冻结）
# 效果：owner 连续和牌时本次 +N 番（N=连胡次数）；他家和牌或流局清零。
extends SkillHook

func on_event(skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.type == &"WIN_DECLARED_PRE":
		if event.actor_seat == ctx.beneficiary_seat:
			var streak: int = int(skill.params.get("streak", 0)) + 1
			skill.params["streak"] = streak
			ctx.add_han(ctx.beneficiary_seat, streak)
		else:
			_reset_streak(skill)
	elif event.type == &"EXHAUSTIVE_DRAW" or event.type == &"ABORTIVE_DRAW":
		_reset_streak(skill)


func _reset_streak(skill: SkillResource) -> void:
	if int(skill.params.get("streak", 0)) == 0:
		return
	skill.params["streak"] = 0
