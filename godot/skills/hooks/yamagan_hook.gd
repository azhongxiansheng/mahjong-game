# 山眼 — §8.10 #3 史诗角色能力
# GAME_BEGIN 时 reveal 牌墙顶 10 张顺序给 owner。
extends SkillHook

const TOP_N: int = 10

func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	ctx.reveal_wall_top_to(ctx.beneficiary_seat, TOP_N)
