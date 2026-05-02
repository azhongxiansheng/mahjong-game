# 4 索·指示牌操纵 — §8.8 Dora 系（M6 内容生产）
#
# v1: owner 自胡 +2 番（模拟"立直胡牌时重选裏 Dora 指示，平均最优收益 ≈ 2 番"）
# spec 原效果："立直胡牌时重选裏 Dora 指示牌"
# v1 简化：用 add_han(+2) 表达"重选最优裏 dora 平均收益"；
# 真"重选裏 dora 指示"需 reroll_uradora ctx 扩展（M7）。
# v1 不区分立直 / 非立直；M7 扩 BattleState.riichi_declared[] 后再加判定。
extends SkillHook

const URADORA_HAN_BONUS: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, URADORA_HAN_BONUS)
