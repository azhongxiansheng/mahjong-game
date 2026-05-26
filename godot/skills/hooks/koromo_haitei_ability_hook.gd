# 衣・海底支配 — 能力版
# HAITEI / HOUTEI 自胡時 +3 番 + 満貫下限保証。
# 触発：HAITEI / HOUTEI + actor == beneficiary
extends SkillHook

const HAITEI_BONUS: int = 3

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, HAITEI_BONUS)
	ctx.ensure_mangan_for_seat(ctx.beneficiary_seat)
