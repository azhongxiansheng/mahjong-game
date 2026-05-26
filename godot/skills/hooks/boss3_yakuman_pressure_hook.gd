# 章 3 Boss 変種 — 役満プレッシャー
# Boss 自胡時 +4 番（常時）。2 回に 1 回は force_yakuman_for_seat で役満化。
# skill.params["pressure_count"] で回数追跡。
# 触発：WIN_DECLARED_PRE + actor == beneficiary（boss seat）
extends SkillHook

const PRESSURE_HAN_BONUS: int = 4

func on_event(skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var count: int = int(skill.params.get("pressure_count", 0)) + 1
	skill.params["pressure_count"] = count
	ctx.add_han(ctx.beneficiary_seat, PRESSURE_HAN_BONUS)
	# Every 2nd activation: force yakuman
	if count % 2 == 0:
		ctx.force_yakuman_for_seat(ctx.beneficiary_seat)
