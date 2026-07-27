# 林夜彻 — 角色被动「脊读鬼神」
# ability_id: char_akagi_passive_v1（语义冻结）
# 效果：每次己方摸牌后 reveal 下家 1 张手牌。
extends SkillHook

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	var target: int = (ctx.beneficiary_seat + 1) % 4
	ctx.reveal_random_from_seat(target, ctx.beneficiary_seat, true)
