extends SkillHook

const COLLAPSE_COUNT := 10


func on_event(_skill: SkillResource, _event: BattleEvent, ctx: SkillCtx) -> void:
	ctx.discard_wall_top(COLLAPSE_COUNT)
	ctx.consume_self()
