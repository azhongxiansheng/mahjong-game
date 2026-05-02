# 流局誘導 — §8.10 #6 史诗角色能力（M6 内容生产）
#
# v1: owner 自胡 +1 番（模拟"主动流局保住已有点数"的等价收益）
# spec 原效果："巡数 ≥ 12 后弃牌可强制流局"
# v1 简化：用 add_han(+1) 表达"局面控制收益"；真"强制流局"需
# turn_engine.force_ryukyoku ctx 扩展（M7）。
extends SkillHook

const YUDOU_HAN_BONUS: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, YUDOU_HAN_BONUS)
