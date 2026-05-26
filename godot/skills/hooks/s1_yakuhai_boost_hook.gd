# 1索·役牌加成 — 牌技能（增番系）
# WIN_DECLARED_PRE: owner 胡牌时 +1 番（役牌加成）
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, 1)
