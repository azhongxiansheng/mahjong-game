# 可抽能力「宝牌吸引」— id: kuro_dora_love_v1（非角色被动）
extends SkillHook

const WIN_EXTRA_DORA: int = 2
const REVEAL_EXTRA_DORA: int = 1

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.type == &"WIN_DECLARED_PRE":
		if event.actor_seat == ctx.beneficiary_seat:
			ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, WIN_EXTRA_DORA)
	elif event.type == &"DORA_REVEALED":
		ctx.mark_extra_dora_for_seat(ctx.beneficiary_seat, REVEAL_EXTRA_DORA)
