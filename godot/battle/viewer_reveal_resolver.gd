extends RefCounted

# 将权威 BattleState.revealed_tiles 投影为某一 viewer 当前仍可见的真实手牌实体。
# 本类不认识具体角色/能力，也不渲染 UI；服务端快照与本地牌桌共用同一过滤规则。


static func tiles_by_holder(state: BattleState, viewer_seat: int) -> Dictionary:
	var grouped: Dictionary = {}
	if state == null or viewer_seat < 0 or viewer_seat >= state.seats.size():
		return grouped
	var seen_instance_ids: Dictionary = {}
	for value in state.revealed_tiles:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = value
		var visible_to: Variant = record.get("visible_to", null)
		if typeof(visible_to) != TYPE_ARRAY or not _contains_seat(visible_to, viewer_seat):
			continue
		var instance_value: Variant = record.get("tile", null)
		if not (instance_value is TileSkillAnchor):
			continue
		var instance := instance_value as TileSkillAnchor
		if instance.tile == null or not Tile.is_valid_instance_id(instance.tile.instance_id):
			continue
		var holder := int(instance.holder_seat)
		if holder < 0 or holder >= state.seats.size() or holder == viewer_seat:
			continue
		var seat := state.seats[holder] as Seat
		if seat == null or seat.hand == null:
			continue
		var live_tile: Tile = seat.hand.find_by_instance_id(instance.tile.instance_id)
		if live_tile == null or live_tile.id != instance.tile.id \
				or live_tile.is_red_dora != instance.tile.is_red_dora:
			continue
		var iid := int(live_tile.instance_id)
		if seen_instance_ids.has(iid):
			continue
		seen_instance_ids[iid] = true
		var live_instance := TileSkillAnchor.make(live_tile, holder)
		live_instance.holder_seat = holder
		if not grouped.has(holder):
			grouped[holder] = []
		(grouped[holder] as Array).append(live_instance)
	for holder_value in grouped.keys():
		(grouped[holder_value] as Array).sort_custom(_instance_before)
	return grouped


# 返回仅授权给 viewer 且仍位于 live wall 顶部的预知实体。
# holder=-1 与手牌 reveal 共用 revealed_tiles，不引入角色专属状态或平行协议。
static func next_draw_for_viewer(
	state: BattleState, viewer_seat: int
) -> TileSkillAnchor:
	if state == null or state.wall == null or viewer_seat < 0 \
			or viewer_seat >= state.seats.size():
		return null
	var next_tile: Tile = state.wall.peek_next_draw()
	if next_tile == null:
		return null
	for value in state.revealed_tiles:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record := value as Dictionary
		var visible_to: Variant = record.get("visible_to", null)
		if typeof(visible_to) != TYPE_ARRAY or not _contains_seat(visible_to, viewer_seat):
			continue
		var instance_value: Variant = record.get("tile", null)
		if not (instance_value is TileSkillAnchor):
			continue
		var instance := instance_value as TileSkillAnchor
		if instance.holder_seat != -1 or instance.owner_seat != -1 \
				or instance.tile == null:
			continue
		if instance.tile.instance_id != next_tile.instance_id \
				or instance.tile.id != next_tile.id \
				or instance.tile.is_red_dora != next_tile.is_red_dora:
			continue
		var live := TileSkillAnchor.make(next_tile, instance.owner_seat)
		live.holder_seat = -1
		return live
	return null


# 返回仍连续位于 live wall 顶部、且明确授权给 viewer 的牌墙序列。
# 第一个未授权位置即截断，保证后续普通摸只消费、不补入原批次第四张。
static func wall_top_for_viewer(
	state: BattleState, viewer_seat: int, limit: int = 3
) -> Array:
	var out: Array = []
	if state == null or state.wall == null or viewer_seat < 0 \
			or viewer_seat >= state.seats.size() or limit <= 0:
		return out
	var top: Array[Tile] = state.wall.peek_top_n(limit)
	for tile in top:
		var revealed := false
		for value in state.revealed_tiles:
			if typeof(value) != TYPE_DICTIONARY:
				continue
			var record := value as Dictionary
			var visible_to: Variant = record.get("visible_to", null)
			if typeof(visible_to) != TYPE_ARRAY \
					or not _contains_seat(visible_to, viewer_seat):
				continue
			var instance_value: Variant = record.get("tile", null)
			if not (instance_value is TileSkillAnchor):
				continue
			var instance := instance_value as TileSkillAnchor
			if instance.holder_seat != -1 or instance.owner_seat != viewer_seat \
					or instance.tile == null:
				continue
			if instance.tile.instance_id == tile.instance_id \
					and instance.tile.id == tile.id \
					and instance.tile.is_red_dora == tile.is_red_dora:
				revealed = true
				break
		if not revealed:
			break
		var live := TileSkillAnchor.make(tile, viewer_seat)
		live.holder_seat = -1
		out.append(live)
	return out


static func _contains_seat(values: Array, seat: int) -> bool:
	for value in values:
		if typeof(value) == TYPE_INT and int(value) == seat:
			return true
	return false


static func _instance_before(a: TileSkillAnchor, b: TileSkillAnchor) -> bool:
	return a.tile.instance_id < b.tile.instance_id
