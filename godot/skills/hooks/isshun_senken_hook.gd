# 一巡先見 — §8.10 #4 神级角色能力
# owner DRAW 时 reveal 牌墙下次摸的牌给自己。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.reveal_next_draw_for_seat(ctx.beneficiary_seat, ctx.beneficiary_seat)
