# 可抽能力「底牌压制」— id: koromo_haitei_ability_v1（非角色被动）
extends SkillHook

const HAITEI_BONUS: int = 3

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.add_han(ctx.beneficiary_seat, HAITEI_BONUS)
	ctx.ensure_mangan_for_seat(ctx.beneficiary_seat)
