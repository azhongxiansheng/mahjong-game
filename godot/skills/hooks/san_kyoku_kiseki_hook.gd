# 三局一奇跡 — §8.10 #7 神级角色能力（M6 内容生产）
#
# v1: owner 自胡 +1 番（模拟"每 3 局起手 1 役牌刻 ≈ 平均每局 +1 番"）
# spec 原效果："每 3 局起手保证 1 役牌刻"
# v1 简化：用 add_han(+1) 表达"分摊到每局的平均收益"；真"起手强插刻
# 子"需 inject_meld_at_start ctx 扩展（M7）。
extends SkillHook

const KISEKI_HAN_BONUS: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, KISEKI_HAN_BONUS)
