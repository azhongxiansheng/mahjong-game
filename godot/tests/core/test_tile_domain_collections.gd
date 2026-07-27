extends GutTest


func _tile(tid: int, iid: int) -> Tile:
	return Tile.new(tid, false, Tile.NO_OWNER, iid)


func test_hand_exposes_snapshot_without_leaking_internal_array() -> void:
	var hand := Hand.new()
	assert_true(hand.add(_tile(TileId.W1, 1)))
	var snapshot: Array[Tile] = hand.tiles()
	snapshot.clear()
	assert_eq(hand.size(), 1)
	assert_eq(hand.tile_at(0).instance_id, 1)
	assert_same(hand.first(), hand.tile_at(0))


func test_discard_river_claims_exact_last_tile_and_owns_riichi_marker() -> void:
	var river := DiscardRiver.new()
	assert_true(river.append_discard(_tile(TileId.W1, 10)))
	assert_true(river.append_discard(_tile(TileId.W2, 11), true))
	assert_eq(river.riichi_discard_index(), 1)
	assert_null(river.claim_last(10), "只能鸣取河末的精确实体")
	assert_eq(river.size(), 2, "失败必须零修改")
	assert_eq(river.claim_last(11).instance_id, 11)
	assert_eq(river.riichi_discard_index(), -1)
	assert_true(river.contains_tile_id(TileId.W1))


func test_meld_collection_allocates_stable_ids_and_promotes_pon() -> void:
	var melds := MeldCollection.new(2)
	var called := _tile(TileId.W5, 20)
	var pon: Meld = melds.add_pon([
		called, _tile(TileId.W5, 21), _tile(TileId.W5, 22)
	], 1, called)
	assert_not_null(pon)
	assert_eq(pon.meld_id, 2)
	assert_eq(melds.size(), 1)
	assert_same(melds.find_by_id(2), pon)
	assert_true(melds.promote_pon(2, _tile(TileId.W5, 23)))
	assert_eq(pon.kind, Meld.Kind.ADDED_KAN)
	var copy: Array[Meld] = melds.all()
	copy.clear()
	assert_eq(melds.size(), 1)


func test_dora_indicator_pair_is_atomic_and_capped_at_five() -> void:
	var dora := DoraIndicators.new()
	for i in range(5):
		assert_true(dora.reveal_pair(_tile(TileId.W1 + i, 30 + i),
			_tile(TileId.T1 + i, 40 + i)))
	assert_eq(dora.visible_count(), 5)
	assert_false(dora.reveal_pair(_tile(TileId.W9, 50), _tile(TileId.T9, 51)))
	assert_eq(dora.visible_count(), 5)
	var visible: Array[Tile] = dora.visible_tiles()
	visible.clear()
	assert_eq(dora.visible_count(), 5)
	var duplicate := DoraIndicators.new()
	var same := _tile(TileId.W1, 90)
	assert_false(duplicate.reveal_pair(same, same), "表里指示牌不能是同一实体")
	assert_eq(duplicate.visible_count(), 0)


func test_wall_authority_snapshot_does_not_expose_internal_array() -> void:
	var wall := Wall.new_full_set(3)
	var all_tiles: Array[Tile] = wall.authority_tiles()
	assert_eq(all_tiles.size(), 136)
	all_tiles.clear()
	assert_eq(wall.authority_tiles().size(), 136)
	assert_false(wall.restore_authority_state(
		wall.authority_tiles(), 0, 0, 1), "未预留王牌时不能已有岭上消耗")
	assert_eq(wall.rinshan_taken(), 0, "失败必须零修改")


func test_tile_definition_validation_covers_constructor_invariants() -> void:
	assert_true(Tile.is_valid_definition(TileId.W5, true, 0, 1))
	assert_false(Tile.is_valid_definition(99, false, 0, 1), "非法牌种")
	assert_false(Tile.is_valid_definition(TileId.W1, true, 0, 1), "非五牌不能是赤牌")
	assert_false(Tile.is_valid_definition(TileId.W1, false, 4, 1), "owner 越界")
	assert_false(Tile.is_valid_definition(TileId.W1, false, 0, -2), "实体 ID 非法")


func test_meld_collection_rejects_wrong_shape_and_cross_meld_duplicate_atomically() -> void:
	var melds := MeldCollection.new(0)
	var called := _tile(TileId.W5, 60)
	assert_null(melds.add_pon([
		called, _tile(TileId.W5, 61), _tile(TileId.W6, 62)
	], 1, called), "碰必须同牌种")
	assert_eq(melds.size(), 0)
	var pon := melds.add_pon([
		called, _tile(TileId.W5, 61), _tile(TileId.W5, 62)
	], 1, called)
	assert_not_null(pon)
	assert_null(melds.add_ankan([
		_tile(TileId.E, 62), _tile(TileId.E, 63),
		_tile(TileId.E, 64), _tile(TileId.E, 65),
	]), "同一实体不能跨副露重复")
	assert_eq(melds.size(), 1, "失败必须零修改")
	var called_e := _tile(TileId.E, 66)
	var second := melds.add_pon([
		called_e, _tile(TileId.E, 67), _tile(TileId.E, 68)
	], 3, called_e)
	assert_not_null(second)
	assert_false(melds.promote_pon(pon.meld_id, _tile(TileId.W5, 68)),
		"加杠实体不能已被其它副露占用")
	assert_eq(pon.kind, Meld.Kind.PON)


func test_meld_collection_restore_validates_seat_id_cursor_and_zero_mod() -> void:
	var melds := MeldCollection.new(2)
	var called := _tile(TileId.W5, 70)
	var valid := Meld.make_pon([
		called, _tile(TileId.W5, 71), _tile(TileId.W5, 72)
	], 1, 2, called)
	assert_true(melds.restore([valid], 1))
	var wrong_seat_id := Meld.make_pon([
		_tile(TileId.T5, 73), _tile(TileId.T5, 74), _tile(TileId.T5, 75)
	], 1, 3, _tile(TileId.T5, 73))
	assert_false(melds.restore([wrong_seat_id], 1))
	assert_same(melds.find_by_id(2), valid, "失败后原集合不变")
	assert_false(melds.restore([valid], 0), "游标不能落后于已有 meld_id")
	assert_same(melds.find_by_id(2), valid)
