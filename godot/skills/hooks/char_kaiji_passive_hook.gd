# 开司 — 角色被动「逆境覚醒」
# 原著：伊藤开司在极端逆境下才能爆发，靠拼命和直觉逆转。
# 效果：分数 < 15000 时胡牌 +2 番（逆境反击）。
extends SkillHook

const THRESHOLD: int = 15000
const BONUS_HAN: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	if ctx.get_score(ctx.beneficiary_seat) < THRESHOLD:
		ctx.add_han(ctx.beneficiary_seat, BONUS_HAN)
