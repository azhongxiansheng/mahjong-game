# 测试用间谍钩子 — 通过静态字段在多个 hook 实例间共享配置和踪迹
extends SkillHook

static var trace: Array = []
static var error_on_skill_ids: Array = []
static var recurse_on_skill_ids: Array = []
static var recurse_scheduler: SkillScheduler = null
static var recurse_event_type: StringName = &""

static func reset() -> void:
	trace.clear()
	error_on_skill_ids = []
	recurse_on_skill_ids = []
	recurse_scheduler = null
	recurse_event_type = &""

func on_event(skill: SkillResource, event: BattleEvent, ctx: SkillCtx) -> void:
	trace.append({
		"skill_id": skill.id,
		"event_type": event.type,
		"depth_seen": ctx._state.event_chain_depth,
	})
	if error_on_skill_ids.has(skill.id):
		push_error("spy_hook intentional error from %s" % skill.id)
	if recurse_on_skill_ids.has(skill.id) and recurse_scheduler != null:
		recurse_scheduler.emit_event(BattleEvent.make(recurse_event_type, 0))
