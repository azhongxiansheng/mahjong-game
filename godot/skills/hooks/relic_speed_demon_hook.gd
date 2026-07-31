# 速攻鬼 — 遗物（被动）
# WIN_DECLARED_PRE：owner 在自己完成第 6 次舍牌前胡牌 +1 番。
# 使用个人舍牌数（含被鸣走的舍牌），不使用全局巡数（spec 2026-07-28 §4.1）。
extends SkillHook

const DISCARD_THRESHOLD: int = 6

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	if ctx.personal_discard_count(ctx.beneficiary_seat) >= DISCARD_THRESHOLD:
		return
	ctx.add_han(ctx.beneficiary_seat, 1)
