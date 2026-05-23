class_name SkillScheduler

const _GROUP_OWNER := 0
const _GROUP_HOLDER := 1

var _registry: SkillRegistry
var _state: BattleState
var _next_chain_id: int = 1

func _init(p_registry: SkillRegistry, p_state: BattleState) -> void:
	_registry = p_registry
	_state = p_state

func emit_event(event: BattleEvent) -> SkillCtx:
	event.chain_id = _next_chain_id
	_next_chain_id += 1
	_state.event_chain_depth += 1
	if _state.event_chain_depth > BattleState.MAX_EVENT_CHAIN_DEPTH:
		push_warning(
			"SkillScheduler: event_chain_depth %d exceeds MAX %d — aborting %s, dump=%s" % [
				_state.event_chain_depth,
				BattleState.MAX_EVENT_CHAIN_DEPTH,
				event.type,
				_dump_state(),
			]
		)
		_state.event_chain_depth -= 1
		return SkillCtx.new(_state, event)
	var ctx := SkillCtx.new(_state, event)
	var candidates := _collect(event)
	_sort(candidates)
	_dispatch(candidates, event, ctx)
	_state.event_chain_depth -= 1
	return ctx

func _collect(event: BattleEvent) -> Array:
	var candidates: Array = []
	var seen_ability_ids: Dictionary = {}
	for entry in _registry.get_all_entries():
		var skill: SkillResource = entry.skill
		if skill.consumed:
			continue
		if entry.hook == null:
			continue
		if skill.is_ability:
			if seen_ability_ids.has(skill.id):
				continue
			var owner_hit := skill.owner_triggers.has(event.type)
			var holder_hit := skill.holder_triggers.has(event.type)
			if not owner_hit and not holder_hit:
				continue
			seen_ability_ids[skill.id] = true
			candidates.append({
				"group": _GROUP_OWNER,
				"skill": skill,
				"hook": entry.hook,
				"beneficiary_seat": entry.anchor,
				"reg_order": entry.reg_order,
			})
		else:
			var ti: TileInstance = entry.anchor
			if skill.owner_triggers.has(event.type):
				candidates.append({
					"group": _GROUP_OWNER,
					"skill": skill,
					"hook": entry.hook,
					"beneficiary_seat": ti.owner_seat,
					"reg_order": entry.reg_order,
				})
			if skill.holder_triggers.has(event.type) and ti.holder_seat >= 0:
				candidates.append({
					"group": _GROUP_HOLDER,
					"skill": skill,
					"hook": entry.hook,
					"beneficiary_seat": ti.holder_seat,
					"reg_order": entry.reg_order,
				})
	return candidates

func _sort(candidates: Array) -> void:
	candidates.sort_custom(func(a, b):
		if a.group != b.group:
			return a.group < b.group
		var ar: int = a.skill.rarity
		var br: int = b.skill.rarity
		if ar != br:
			return ar > br
		return a.reg_order < b.reg_order
	)

func _dispatch(candidates: Array, event: BattleEvent, ctx: SkillCtx) -> void:
	for c in candidates:
		if c.skill.consumed:
			continue
		ctx.beneficiary_seat = c.beneficiary_seat
		ctx.current_skill = c.skill
		c.hook.on_event(c.skill, event, ctx)
		ctx.triggered_skills.append({
			"skill_id": c.skill.id,
			"skill_name": c.skill.display_name,
			"beneficiary_seat": c.beneficiary_seat,
		})
	ctx.current_skill = null

func _dump_state() -> Dictionary:
	return {
		"event_chain_depth": _state.event_chain_depth,
		"scores": _state.scores.duplicate(),
		"furiten_flags": _state.furiten_flags.duplicate(),
		"ron_cancelled": _state.ron_cancelled.duplicate(),
		"haitei_forced_seat": _state.haitei_forced_seat,
	}
