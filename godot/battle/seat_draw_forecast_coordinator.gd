extends RefCounted

# 先示的权威四席条件预测。记录仍走 BattleState.revealed_tiles：
# holder=-1 表示牌墙实体，owner_seat=预测目标席；#344 单张预知保持 owner=-1。

const SKILL_ID := &"char_toki_passive_v1"
const PARAM_ACTIVE := "seat_draw_forecast_active"
const PARAM_HAND_SEQ := "seat_draw_forecast_hand_seq"
const PARAM_VIEWER := "seat_draw_forecast_viewer"
const PARAM_PENDING := "seat_draw_forecast_pending"
const RECORD_KIND_KEY := "projection_kind"
const PROJECTION_KIND := "viewer_seat_draw_forecast@1"


static func activate(state: BattleState, skill: SkillResource, viewer_seat: int) -> bool:
	if state == null or state.wall == null or skill == null \
			or skill.id != SKILL_ID or viewer_seat < 0 or viewer_seat > 3:
		return false
	if bool(skill.params.get(PARAM_ACTIVE, false)) \
			and int(skill.params.get(PARAM_HAND_SEQ, -1)) == state.hand_seq:
		return false
	skill.params[PARAM_ACTIVE] = true
	skill.params["_registry_linger_while_param"] = PARAM_ACTIVE
	skill.params[PARAM_HAND_SEQ] = state.hand_seq
	skill.params[PARAM_VIEWER] = viewer_seat
	skill.params[PARAM_PENDING] = [0, 1, 2, 3]
	var count := recompute(state, skill)
	if count <= 0:
		skill.params[PARAM_ACTIVE] = false
		skill.params[PARAM_PENDING] = []
	return count > 0


static func recompute(state: BattleState, skill: SkillResource) -> int:
	if not _is_active_for_state(state, skill):
		return 0
	var viewer := int(skill.params.get(PARAM_VIEWER, -1))
	_remove_records_for_viewer(state, viewer)
	var pending: Array = _pending_seats(skill)
	if pending.is_empty() or state.wall.live_wall_size() <= 0:
		return 0
	var start_seat := _next_normal_draw_seat(state)
	if start_seat < 0:
		return 0
	var top: Array[Tile] = state.wall.peek_top_n(4)
	var count := 0
	for offset in range(top.size()):
		var target := (start_seat + offset) % 4
		if not pending.has(target):
			continue
		var tile := top[offset] as Tile
		var anchor := TileSkillAnchor.make(tile, target)
		anchor.holder_seat = -1
		state.revealed_tiles.append({
			"tile": anchor,
			"visible_to": [viewer],
			RECORD_KIND_KEY: PROJECTION_KIND,
		})
		count += 1
	return count


static func consume_actual_draw(
	state: BattleState,
	registry: SkillRegistry,
	target_seat: int,
	instance_id: int
) -> bool:
	# 普通 live draw：牌已进入手牌，不能再经只返回 live-wall 实例的公开 resolver。
	# 仅权威原始记录中的 target + exact iid 同时命中后才允许消费 pending。
	if state == null or target_seat < 0 or target_seat > 3 \
			or not Tile.is_instance_id_in_hand_seq(instance_id, state.hand_seq):
		return false
	var matched := false
	for skill in _active_skills(registry, state):
		var pending := _pending_seats(skill)
		if not pending.has(target_seat):
			continue
		var viewer := int(skill.params.get(PARAM_VIEWER, -1))
		if not _has_exact_forecast_record(
			state, viewer, target_seat, instance_id):
			continue
		matched = true
		pending.erase(target_seat)
		skill.params[PARAM_PENDING] = pending
		if pending.is_empty():
			_remove_records_for_viewer(state, viewer)
			skill.params[PARAM_ACTIVE] = false
		else:
			recompute(state, skill)
	return matched


static func branch_committed(
	state: BattleState,
	registry: SkillRegistry,
	rinshan_draw_seat: int = -1,
	rinshan_instance_id: int = Tile.INVALID_INSTANCE_ID
) -> void:
	# 岭上是鸣杠提交后的独立实际摸牌，不与旧 live-wall 预测做 iid 匹配。
	# 验证真实补牌事实后显式消费 actor，再按改变后的 live path 重算其余席。
	var actual_rinshan := _is_actual_rinshan_draw(
		state, rinshan_draw_seat, rinshan_instance_id)
	for skill in _active_skills(registry, state):
		var viewer := int(skill.params.get(PARAM_VIEWER, -1))
		_remove_records_for_viewer(state, viewer)
		var pending := _pending_seats(skill)
		if actual_rinshan and pending.has(rinshan_draw_seat):
			pending.erase(rinshan_draw_seat)
			skill.params[PARAM_PENDING] = pending
		if pending.is_empty():
			skill.params[PARAM_ACTIVE] = false
		else:
			recompute(state, skill)


static func suspend_for_unresolved_branch(
	state: BattleState, registry: SkillRegistry
) -> void:
	for skill in _active_skills(registry, state):
		_remove_records_for_viewer(state, int(skill.params.get(PARAM_VIEWER, -1)))


static func clear_all(state: BattleState, registry: SkillRegistry) -> void:
	if state == null:
		return
	for skill in _active_skills(registry, state):
		var viewer := int(skill.params.get(PARAM_VIEWER, -1))
		_remove_records_for_viewer(state, viewer)
		skill.params[PARAM_ACTIVE] = false
		skill.params[PARAM_PENDING] = []


static func predictions_for_viewer(state: BattleState, viewer_seat: int) -> Array:
	var out: Array = []
	if state == null or state.wall == null or viewer_seat < 0 or viewer_seat > 3:
		return out
	for value in state.revealed_tiles:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record := value as Dictionary
		if not is_forecast_record(record):
			continue
		var visible_to: Variant = record.get("visible_to", null)
		if typeof(visible_to) != TYPE_ARRAY or not (visible_to as Array).has(viewer_seat):
			continue
		var anchor := record.get("tile", null) as TileSkillAnchor
		if not _is_forecast_anchor(anchor):
			continue
		if not _is_live_wall_tile(state.wall, anchor.tile.instance_id):
			continue
		out.append({"target_seat": anchor.owner_seat, "tile": anchor})
	return out


static func _active_skills(registry: SkillRegistry, state: BattleState) -> Array:
	var out: Array = []
	if registry == null or state == null:
		return out
	for entry in registry.get_all_entries():
		var skill := entry.skill as SkillResource
		if _is_active_for_state(state, skill):
			out.append(skill)
	return out


static func _is_active_for_state(state: BattleState, skill: SkillResource) -> bool:
	return state != null and skill != null and skill.id == SKILL_ID \
		and bool(skill.params.get(PARAM_ACTIVE, false)) \
		and int(skill.params.get(PARAM_HAND_SEQ, -1)) == state.hand_seq \
		and int(skill.params.get(PARAM_VIEWER, -1)) in range(4)


static func _pending_seats(skill: SkillResource) -> Array:
	var value: Variant = skill.params.get(PARAM_PENDING, [])
	if typeof(value) != TYPE_ARRAY:
		return []
	var out: Array = []
	for seat in value as Array:
		if typeof(seat) == TYPE_INT and int(seat) in range(4) and not out.has(int(seat)):
			out.append(int(seat))
	return out


static func _next_normal_draw_seat(state: BattleState) -> int:
	match state.phase:
		BattlePhase.Kind.DRAW:
			return state.current_seat
		BattlePhase.Kind.DISCARD, BattlePhase.Kind.CLAIM:
			return (state.current_seat + 1) % 4
	return -1


static func _remove_records_for_viewer(state: BattleState, viewer_seat: int) -> void:
	for index in range(state.revealed_tiles.size() - 1, -1, -1):
		var value: Variant = state.revealed_tiles[index]
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record := value as Dictionary
		if not is_forecast_record(record):
			continue
		var visible_to: Variant = record.get("visible_to", null)
		if typeof(visible_to) != TYPE_ARRAY or not (visible_to as Array).has(viewer_seat):
			continue
		state.revealed_tiles.remove_at(index)


static func is_forecast_record(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var record := value as Dictionary
	return record.get(RECORD_KIND_KEY, "") == PROJECTION_KIND \
		and _is_forecast_anchor(record.get("tile", null) as TileSkillAnchor)


static func _has_exact_forecast_record(
	state: BattleState, viewer_seat: int, target_seat: int, instance_id: int
) -> bool:
	for value in state.revealed_tiles:
		if not is_forecast_record(value):
			continue
		var record := value as Dictionary
		var visible_to: Variant = record.get("visible_to", null)
		if typeof(visible_to) != TYPE_ARRAY \
				or not (visible_to as Array).has(viewer_seat):
			continue
		var anchor := record.get("tile", null) as TileSkillAnchor
		if anchor.owner_seat == target_seat \
				and anchor.tile.instance_id == instance_id:
			return true
	return false


static func _is_actual_rinshan_draw(
	state: BattleState, seat_index: int, instance_id: int
) -> bool:
	if state == null or seat_index < 0 or seat_index >= state.seats.size() \
			or not Tile.is_instance_id_in_hand_seq(instance_id, state.hand_seq):
		return false
	var seat := state.seats[seat_index] as Seat
	return seat != null and seat.last_draw_is_rinshan \
		and seat.last_drawn_instance_id == instance_id


static func _is_forecast_anchor(anchor: TileSkillAnchor) -> bool:
	return anchor != null and anchor.tile != null and anchor.holder_seat == -1 \
		and anchor.owner_seat >= 0 and anchor.owner_seat <= 3


static func _is_live_wall_tile(wall: Wall, instance_id: int) -> bool:
	for index in range(wall.draw_index(), wall.live_end_index()):
		var tile := wall.authority_tile_at(index)
		if tile != null and tile.instance_id == instance_id:
			return true
	return false
