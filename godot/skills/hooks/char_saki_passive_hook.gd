# 华岭澄 — 角色被动「宝华绽放」
# ability_id: char_saki_passive_v1（语义冻结）
# 效果：胡牌时额外 +2 Dora。
extends SkillHook

const BONUS_DORA: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, BONUS_DORA)
