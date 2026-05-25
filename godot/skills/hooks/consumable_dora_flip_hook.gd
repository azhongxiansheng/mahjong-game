# 翻宝牌 — 战斗消耗品
# TILE_DRAWN: owner 摸牌时额外 +1 Dora 并消耗自身
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, 1)
	ctx.consume_self()
