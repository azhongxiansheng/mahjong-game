# 纪枢 — 角色被动「概率圣裁」
# ability_id: char_nodoka_passive_v1（语义冻结）
# 效果 1：WIN_DECLARED_PRE 自胡时 +1 番。
# 效果 2：HAND_FORMED（对手听牌）时，对手手牌 1 枚 reveal 给 owner。
extends SkillHook

const DIGITAL_BONUS: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.type == &"WIN_DECLARED_PRE":
		if event.actor_seat == ctx.beneficiary_seat:
			ctx.add_han(ctx.beneficiary_seat, DIGITAL_BONUS)
	elif event.type == &"HAND_FORMED":
		if event.actor_seat != ctx.beneficiary_seat:
			ctx.reveal_random_from_seat(event.actor_seat, ctx.beneficiary_seat)
