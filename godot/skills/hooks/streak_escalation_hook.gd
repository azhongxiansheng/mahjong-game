# 連勝エスカレーション — 能力
# WIN_DECLARED で勝利回数を追跡（skill.params["streak_count"]）。
# WIN_DECLARED_PRE で +streak_count 番を加算。
# EXHAUSTIVE_DRAW でリセット。
# 触発：WIN_DECLARED_PRE / WIN_DECLARED / EXHAUSTIVE_DRAW
extends SkillHook

func on_event(skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.type == &"WIN_DECLARED_PRE":
		if event.actor_seat == ctx.beneficiary_seat:
			var streak: int = int(skill.params.get("streak_count", 0))
			if streak > 0:
				ctx.add_han(ctx.beneficiary_seat, streak)
	elif event.type == &"WIN_DECLARED":
		if event.actor_seat == ctx.beneficiary_seat:
			var current: int = int(skill.params.get("streak_count", 0))
			skill.params["streak_count"] = current + 1
	elif event.type == &"EXHAUSTIVE_DRAW":
		skill.params["streak_count"] = 0
