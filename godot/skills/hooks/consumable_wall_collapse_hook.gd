# 牌墙崩塌 — 战斗消耗品
# 效果：从活牌墙顶移除 6 张（spec 2026-07-28 §3.1）。
# 不得令活牌墙少于 14 张；条件不足时拒绝且不消耗（不调 consume_self）。
extends SkillHook

const COLLAPSE_COUNT := 6
const MIN_LIVE_WALL_AFTER := 14


func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	var wall: Wall = ctx._state.wall
	if wall == null or wall.live_wall_size() - COLLAPSE_COUNT < MIN_LIVE_WALL_AFTER:
		return
	ctx.discard_wall_top(COLLAPSE_COUNT)
	ctx.consume_self()
