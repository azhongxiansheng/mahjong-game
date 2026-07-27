extends GutTest

const Resolver := preload("res://battle/viewer_reveal_resolver.gd")


func _state() -> BattleState:
	return BattleState.for_east_round(340, 0, 1, 0, 0)


func _record(st: BattleState, holder_seat: int, viewer_seat: int,
		hand_index: int = 0) -> Dictionary:
	var tile: Tile = st.seats[holder_seat].hand._tiles[hand_index]
	var instance := TileInstance.make(tile, holder_seat)
	instance.holder_seat = holder_seat
	return {"tile": instance, "visible_to": [viewer_seat]}


func test_groups_only_authorized_live_tiles_by_holder_and_deduplicates() -> void:
	var st := _state()
	assert_not_null(st)
	var authorized := _record(st, 1, 0)
	st.revealed_tiles = [
		authorized,
		authorized.duplicate(),
		_record(st, 2, 3),
	]
	var grouped: Dictionary = Resolver.tiles_by_holder(st, 0)
	assert_eq(grouped.keys(), [1])
	assert_eq((grouped[1] as Array).size(), 1)
	var revealed := (grouped[1] as Array)[0] as TileInstance
	assert_eq(revealed.tile.instance_id,
		(authorized.tile as TileInstance).tile.instance_id)
	assert_true(Resolver.tiles_by_holder(st, 2).is_empty(),
		"非授权 viewer 不得看到任何对手牌")


func test_reveal_expires_when_exact_tile_leaves_holder_hand() -> void:
	var st := _state()
	var record := _record(st, 1, 0)
	st.revealed_tiles = [record]
	var instance := record.tile as TileInstance
	assert_false(Resolver.tiles_by_holder(st, 0).is_empty())
	assert_not_null(st.seats[1].hand.take_by_instance_id(instance.tile.instance_id))
	assert_true(Resolver.tiles_by_holder(st, 0).is_empty(),
		"已打出或离开手牌的实体必须立即失效")


func test_invalid_viewer_and_malformed_records_fail_closed() -> void:
	var st := _state()
	st.revealed_tiles = [
		{},
		{"tile": null, "visible_to": [0]},
		{"tile": _record(st, 1, 0).tile, "visible_to": "0"},
	]
	assert_true(Resolver.tiles_by_holder(st, -1).is_empty())
	assert_true(Resolver.tiles_by_holder(st, 4).is_empty())
	assert_true(Resolver.tiles_by_holder(st, 0).is_empty())
