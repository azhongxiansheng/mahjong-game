class_name ItemEffectRunner extends RefCounted


static func apply_immediate(
	definition: ItemDefinition,
	state: BattleState,
	seat: int
) -> bool:
	if definition == null \
			or definition.use_mode != ItemDefinition.UseMode.IMMEDIATE \
			or state == null \
			or state.wall == null:
		return false
	var skill := ItemSkillBuilder.build(definition)
	if skill == null or skill.hook_script == null or definition.triggers.is_empty():
		return false
	var hook = skill.hook_script.new()
	if not (hook is SkillHook):
		return false
	var event := BattleEvent.make(definition.triggers[0], seat, null, {})
	var ctx := SkillCtx.new(state, event)
	ctx.beneficiary_seat = seat
	ctx.current_skill = skill
	hook.on_event(skill, event, ctx)
	return true
