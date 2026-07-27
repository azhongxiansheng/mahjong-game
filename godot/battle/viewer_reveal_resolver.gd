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
		if not (instance_value is TileInstance):
			continue
		var instance := instance_value as TileInstance
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
		var live_instance := TileInstance.make(live_tile, holder)
		live_instance.holder_seat = holder
		if not grouped.has(holder):
			grouped[holder] = []
		(grouped[holder] as Array).append(live_instance)
	for holder_value in grouped.keys():
		(grouped[holder_value] as Array).sort_custom(_instance_before)
	return grouped


static func _contains_seat(values: Array, seat: int) -> bool:
	for value in values:
		if typeof(value) == TYPE_INT and int(value) == seat:
			return true
	return false


static func _instance_before(a: TileInstance, b: TileInstance) -> bool:
	return a.tile.instance_id < b.tile.instance_id
