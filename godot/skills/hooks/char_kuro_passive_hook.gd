# 宝络绯 — 角色被动「赤线缠宝」
# ability_id: char_kuro_passive_v1（语义冻结）
# 效果：WIN_DECLARED_PRE 自胡时 +2 extra Dora。
extends SkillHook

const EXTRA_DORA: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, EXTRA_DORA)
