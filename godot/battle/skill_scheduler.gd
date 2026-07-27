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
	# 角色能力仍按 ability id 去重；同 item_id 多实例用 item_instance_id 区分（#253）。
	var seen_ability_keys: Dictionary = {}
	for entry in _registry.get_all_entries():
		var skill: SkillResource = entry.skill
		if skill.consumed:
			continue
		if entry.hook == null:
			continue
		if skill.is_ability:
			var dedupe_key: String = _ability_dedupe_key(skill)
			if seen_ability_keys.has(dedupe_key):
				continue
			var owner_hit := skill.owner_triggers.has(event.type)
			var holder_hit := skill.holder_triggers.has(event.type)
			if not owner_hit and not holder_hit:
				continue
			seen_ability_keys[dedupe_key] = true
			candidates.append({
				"group": _GROUP_OWNER,
				"skill": skill,
				"hook": entry.hook,
				"beneficiary_seat": entry.anchor,
				"reg_order": entry.reg_order,
			})
		else:
			var ti: TileSkillAnchor = entry.anchor
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
		var snap := _snapshot_before(ctx)
		c.hook.on_event(c.skill, event, ctx)
		if _did_mutate(ctx, snap):
			ctx.triggered_skills.append({
				"skill_id": c.skill.id,
				"skill_name": c.skill.display_name,
				"beneficiary_seat": c.beneficiary_seat,
			})
	ctx.current_skill = null

func _snapshot_before(ctx: SkillCtx) -> Dictionary:
	return {
		"han_deltas_size": ctx.han_deltas.size(),
		"han_multipliers_size": ctx.han_multipliers.size(),
		"mangan_size": ctx.mangan_floor_seats.size(),
		"yakuman_size": ctx.yakuman_force_seats.size(),
		"revealed_count": _state.revealed_tiles.size(),
		"haitei": _state.haitei_forced_seat,
		"furiten": _state.furiten_flags.duplicate(),
		"ron_cancelled": _state.ron_cancelled.duplicate(),
		"scores": _state.scores.duplicate(),
		"extra_dora": _state.extra_dora_count.duplicate(),
		"extra_red_dora": _state.extra_red_dora_count.duplicate(),
		"consumed": ctx.current_skill.consumed if ctx.current_skill else false,
	}

func _did_mutate(ctx: SkillCtx, snap: Dictionary) -> bool:
	if ctx.han_deltas.size() != int(snap.han_deltas_size):
		return true
	if ctx.han_multipliers.size() != int(snap.han_multipliers_size):
		return true
	if ctx.mangan_floor_seats.size() != int(snap.mangan_size):
		return true
	if ctx.yakuman_force_seats.size() != int(snap.yakuman_size):
		return true
	if _state.revealed_tiles.size() != int(snap.revealed_count):
		return true
	if _state.haitei_forced_seat != int(snap.haitei):
		return true
	if _state.furiten_flags != snap.furiten:
		return true
	if _state.ron_cancelled != snap.ron_cancelled:
		return true
	if _state.scores != snap.scores:
		return true
	if _state.extra_dora_count != snap.extra_dora:
		return true
	if _state.extra_red_dora_count != snap.extra_red_dora:
		return true
	if ctx.current_skill != null and ctx.current_skill.consumed and not snap.consumed:
		return true
	return false

func _dump_state() -> Dictionary:
	return {
		"event_chain_depth": _state.event_chain_depth,
		"scores": _state.scores.duplicate(),
		"furiten_flags": _state.furiten_flags.duplicate(),
		"ron_cancelled": _state.ron_cancelled.duplicate(),
		"haitei_forced_seat": _state.haitei_forced_seat,
	}


## 角色：ab:<id>；道具多实例：ii:<item_instance_id>（最小改动，不破坏角色语义）。
func _ability_dedupe_key(skill: SkillResource) -> String:
	if skill == null:
		return "ab:"
	if skill.params.has("item_instance_id"):
		var iid := String(skill.params["item_instance_id"]).strip_edges()
		if not iid.is_empty():
			return "ii:" + iid
	return "ab:" + String(skill.id)
