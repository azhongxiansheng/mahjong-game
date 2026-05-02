# 东风·王者气 — §8.1 增番系（M6 内容生产）
#
# v1: owner 是庄家且自胡 → +2 番
# spec 原效果：同上
# 庄家判定：event.extra["dealer_seat"]（由触发方填）；缺省 -1 不触发。
# 真实战 BattleEvent 的 emit 端会把 BattleState.dealer_seat 注入 extra，
# 同 discarder_seat 模式（seal_chun / iron_wall）。
extends SkillHook

const DYNASTY_HAN_BONUS: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var dealer: int = int(event.extra.get("dealer_seat", -1))
	if dealer != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, DYNASTY_HAN_BONUS)
