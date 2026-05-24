# 宫永咲 — 角色被动「嶺上の華」
# 原著：嶺上开花的天才，杠后必然胡牌。
# 效果：胡牌时额外 +2 Dora（模拟嶺上的强运加成）。
extends SkillHook

const BONUS_DORA: int = 2

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, BONUS_DORA)
