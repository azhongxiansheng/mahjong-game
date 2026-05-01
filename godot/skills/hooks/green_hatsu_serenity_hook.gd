# 发·禅意 — §8.1 增番系（M6 内容生产）
#
# v1: 持牌者（holder = 胡牌者）持发牌时自胡 → +1 番
# spec 原效果："任意人作三元牌一员胡牌时 +1 番"
# 与 white_haku_holy 同款 v1 简化（绑 HATSU 而不是 HAKU）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, 1)
