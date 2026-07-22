# 可抽能力「牌墙记忆」— id: mako_memory_v1
extends SkillHook

const MEMORY_TURN_THRESHOLD: int = 6
const REVEAL_COUNT: int = 3

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	if ctx._state.turn_count < MEMORY_TURN_THRESHOLD:
		return
	ctx.reveal_wall_top_to(ctx.beneficiary_seat, REVEAL_COUNT)
