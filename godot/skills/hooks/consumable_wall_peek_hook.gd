# 千里眼 — 战斗消耗品
# 效果：查看当前牌墙接下来 3 张（仅 owner 可见；spec 2026-07-28 §3.1）
extends SkillHook

const PEEK_COUNT: int = 3

func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	ctx.reveal_wall_top_to(ctx.beneficiary_seat, PEEK_COUNT)
	ctx.consume_self()
