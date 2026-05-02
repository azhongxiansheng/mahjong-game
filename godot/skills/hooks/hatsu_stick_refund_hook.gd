# 发·点棒返还 — §8.6 立直系（M6 内容生产）
#
# v1: owner 自胡 +1 番（模拟"立直棒返还 1000 ≈ 0.5 番收益放大为 1"）
# spec 原效果："owner 立直棒被取走时返 1000 点"
# v1 简化：用 add_han(+1) 表达稳定收益；真 transfer_points 需要知道立直
# 棒接收方，留 M7 在 stick_accounting 接驳后做。
extends SkillHook

const REFUND_HAN_BONUS: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, REFUND_HAN_BONUS)
