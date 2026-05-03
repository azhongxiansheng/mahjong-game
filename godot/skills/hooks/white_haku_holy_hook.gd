# 白板·圣光 — §8.1 增番系（M6 内容生产示范实装）
#
# v1: 持牌者（holder = 胡牌者）持白板时自胡 → +1 番
# spec 原效果："任何人持此牌作三元牌一员胡牌时，番数 ×1.5"
# M7 平衡时升级为 multiply_han API + 三元牌成立检查（需扩 SkillCtx）。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	# holder_trigger 模式：beneficiary_seat 是 holder（持牌者）
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, int(BalanceConstants.lookup(&"white_haku_holy_han_bonus")))
