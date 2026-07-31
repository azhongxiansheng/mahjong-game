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
	# 即时 hook 以 consume_self 表示成功；未消耗（前置条件不满足）视为拒绝，
	# 由调用方（ItemAuthority.use_item）保持实例 held、不发 APPLIED/CONSUMED。
	return skill.consumed
