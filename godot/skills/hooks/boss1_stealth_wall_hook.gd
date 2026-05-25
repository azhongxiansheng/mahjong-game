# 章 1 Boss 変種 — ステルス壁（防御テーマ v2）
# Boss 自胡時 +1 番（ステルス弃牌の優位性を簡略化表現）。
# 触発：WIN_DECLARED_PRE + actor == beneficiary（boss seat）
extends SkillHook

const STEALTH_BONUS: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, STEALTH_BONUS)
