# 哲也 — 角色被動「玄人技」
# 原著：麻雀放浪記の凄腕玄人。イカサマと実力の融合。
# 効果：WIN_DECLARED_PRE 自胡時 +1 番（基本ボーナス）+ 累積ボーナス。
#       初回 +1、2 回目 +2、3 回目 +3 …（1 + wins_before）。
#       skill.params["wins"] で勝利回数を追跡。
extends SkillHook

func on_event(skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var wins: int = int(skill.params.get("wins", 0))
	ctx.add_han(ctx.beneficiary_seat, 1 + wins)
	skill.params["wins"] = wins + 1
