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


# 奖励窗等价触发单个已确定的角色技能；复用正常 dispatch 的 mutation 判定，
# 避免重新广播 GAME_BEGIN 而误触发同窗其他角色。
func emit_single_skill_event(
	event: BattleEvent,
	skill: SkillResource,
	beneficiary_seat: int
) -> SkillCtx:
	event.chain_id = _next_chain_id
	_next_chain_id += 1
	_state.event_chain_depth += 1
	var ctx := SkillCtx.new(_state, event)
	if _state.event_chain_depth > BattleState.MAX_EVENT_CHAIN_DEPTH:
		_state.event_chain_depth -= 1
		return ctx
	if skill == null or skill.consumed or skill.hook_script == null:
		_state.event_chain_depth -= 1
		return ctx
	var hook = skill.hook_script.new()
	if hook is SkillHook:
		_dispatch([{
			"skill": skill,
			"hook": hook,
			"beneficiary_seat": beneficiary_seat,
		}], event, ctx)
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
			# #379：从当前实际触发的 c.skill 直接归因，禁止事后按 skill_id 回扫首实例
			var sk: SkillResource = c.skill as SkillResource
			var item_iid := ""
			if sk != null and sk.params.has("item_instance_id"):
				item_iid = str(sk.params.get("item_instance_id", "")).strip_edges()
			var source_kind := "character"
			if sk != null:
				if sk.params.has("item_id") or not item_iid.is_empty() \
						or String(sk.id).begins_with("relic_"):
					var item_id_s := String(sk.params.get("item_id", ""))
					if String(sk.id).begins_with("relic_") \
							or item_id_s.begins_with("relic_"):
						source_kind = "relic"
					else:
						source_kind = "item"
			var triggered := {
				"skill_id": sk.id if sk != null else c.skill.id,
				"skill_name": sk.display_name if sk != null else c.skill.display_name,
				"beneficiary_seat": c.beneficiary_seat,
				"actor_seat": int(event.actor_seat),
				"is_ability": sk.is_ability if sk != null else c.skill.is_ability,
				"source_kind": source_kind,
			}
			if not item_iid.is_empty():
				triggered["item_instance_id"] = item_iid
			var seat := int(c.beneficiary_seat)
			var before_han: Dictionary = snap.han_deltas
			var han_delta := int(ctx.han_deltas.get(seat, 0)) \
				- int(before_han.get(seat, 0))
			if han_delta != 0:
				triggered["han_delta"] = han_delta
			if seat >= 0 and seat < _state.extra_dora_count.size():
				var before_dora: Array = snap.extra_dora
				var extra_dora_delta := int(_state.extra_dora_count[seat]) \
					- int(before_dora[seat])
				if extra_dora_delta != 0:
					triggered["extra_dora_delta"] = extra_dora_delta
				var before_red_dora: Array = snap.extra_red_dora
				var extra_red_dora_delta := int(_state.extra_red_dora_count[seat]) \
					- int(before_red_dora[seat])
				if extra_red_dora_delta != 0:
					triggered["extra_red_dora_delta"] = extra_red_dora_delta
			ctx.triggered_skills.append(triggered)
	ctx.current_skill = null

func _snapshot_before(ctx: SkillCtx) -> Dictionary:
	return {
		"han_deltas": ctx.han_deltas.duplicate(),
		"han_multipliers_size": ctx.han_multipliers.size(),
		"mangan_size": ctx.mangan_floor_seats.size(),
		"yakuman_size": ctx.yakuman_force_seats.size(),
		"revealed_count": _state.revealed_tiles.size(),
		"tenpai_wait_reveals": _state.tenpai_wait_reveals.duplicate(true),
		"haitei": _state.haitei_forced_seat,
		"furiten": _state.furiten_flags.duplicate(),
		"seat_furiten": _seat_furiten_snapshot(),
		"ron_cancelled": _state.ron_cancelled.duplicate(),
		"scores": _state.scores.duplicate(),
		"extra_dora": _state.extra_dora_count.duplicate(),
		"extra_red_dora": _state.extra_red_dora_count.duplicate(),
		"consumed": ctx.current_skill.consumed if ctx.current_skill else false,
	}

func _did_mutate(ctx: SkillCtx, snap: Dictionary) -> bool:
	if ctx.han_deltas != snap.han_deltas:
		return true
	if ctx.han_multipliers.size() != int(snap.han_multipliers_size):
		return true
	if ctx.mangan_floor_seats.size() != int(snap.mangan_size):
		return true
	if ctx.yakuman_force_seats.size() != int(snap.yakuman_size):
		return true
	if _state.revealed_tiles.size() != int(snap.revealed_count):
		return true
	if _state.tenpai_wait_reveals != snap.tenpai_wait_reveals:
		return true
	if _state.haitei_forced_seat != int(snap.haitei):
		return true
	if _state.furiten_flags != snap.furiten:
		return true
	if _seat_furiten_snapshot() != snap.seat_furiten:
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


func _seat_furiten_snapshot() -> Array:
	var out: Array = []
	for seat_value in _state.seats:
		var seat := seat_value as Seat
		if seat == null or seat.furiten == null:
			out.append([false, false])
		else:
			out.append([seat.furiten.permanent, seat.furiten.temporary])
	return out


## 角色：ab:<id>；道具多实例：ii:<item_instance_id>（最小改动，不破坏角色语义）。
func _ability_dedupe_key(skill: SkillResource) -> String:
	if skill == null:
		return "ab:"
	if skill.params.has("item_instance_id"):
		var iid := String(skill.params["item_instance_id"]).strip_edges()
		if not iid.is_empty():
			return "ii:" + iid
	return "ab:" + String(skill.id)
