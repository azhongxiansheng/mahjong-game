# 原村 — 記憶力能力
# turn_count >= 6 になったら摸牌時に牌墙トップ 3 枚を reveal。
# 触発：TILE_DRAWN + actor == beneficiary + turn_count >= 6
extends SkillHook

const MEMORY_TURN_THRESHOLD: int = 6
const REVEAL_COUNT: int = 3

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	if ctx._state.turn_count < MEMORY_TURN_THRESHOLD:
		return
	ctx.reveal_wall_top_to(ctx.beneficiary_seat, REVEAL_COUNT)
