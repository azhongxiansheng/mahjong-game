# 中·替身 — §8.7 振听操控系（M6 内容生产）
#
# v1: owner 自胡时若处振听则清振听（"替身代承担振听"）
# spec 原效果："振听时指定一对手承担振听状态"
# v1 简化：只清 owner 自家振听；"指定对手承担"需 set_furiten(seat) ctx 扩展（M7）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	if not ctx.is_furiten(ctx.beneficiary_seat):
		return
	ctx.clear_furiten(ctx.beneficiary_seat)
