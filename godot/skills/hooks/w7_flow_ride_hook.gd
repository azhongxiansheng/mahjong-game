# 7万·顺流 — 牌技能（信息系）
# TILE_DRAWN: owner 摸牌且 turn_count >= 3 时 reveal 牌墙顶 3 张
# （v1 简化：以 turn_count 代替"连续无鸣牌"判定）
extends SkillHook

const REVEAL_COUNT: int = 3
const MIN_TURNS: int = 3

func on_event(_skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	if event.actor_seat != ctx.beneficiary_seat:
		return
	if ctx._state.turn_count < MIN_TURNS:
		return
	ctx.reveal_wall_top_to(ctx.beneficiary_seat, REVEAL_COUNT)
