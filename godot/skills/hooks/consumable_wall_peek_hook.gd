# 千里眼 — 战斗消耗品
# 效果：开局时 reveal 牌墙顶 5 张给 owner（一次性）
extends SkillHook

const PEEK_COUNT: int = 5

func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	ctx.reveal_wall_top_to(ctx.beneficiary_seat, PEEK_COUNT)
	ctx.consume_self()
