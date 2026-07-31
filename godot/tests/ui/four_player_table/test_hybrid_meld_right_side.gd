extends GutTest

const PLAYABLE_TABLE := preload("res://ui/four_player_table/playable_table.tscn")

var _next_iid := 700000


func _tile(tile_id: int, owner: int) -> Tile:
	var result := Tile.new(tile_id, false, owner, _next_iid)
	_next_iid += 1
	return result


func _trim_hand(seat: Seat, target_count: int) -> void:
	while seat.hand.size() > target_count:
		var tile := seat.hand.first()
		assert_not_null(tile)
		seat.hand.take_by_instance_id(tile.instance_id)
	seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID


func _add_pon_groups(seat: Seat, group_count: int) -> void:
	for group in range(group_count):
		var tile_id: int = [TileId.W1, TileId.T2, TileId.S3, TileId.HAKU][group]
		var source := (seat.seat_id + 1) % 4
		var tiles: Array[Tile] = [
			_tile(tile_id, seat.seat_id),
			_tile(tile_id, source),
			_tile(tile_id, seat.seat_id),
		]
		assert_not_null(seat.melds.add_pon(tiles, source, tiles[1]))


func _mesh_screen_bounds(camera: Camera3D, instance: MeshInstance3D) -> Rect2:
	var bounds := instance.mesh.get_aabb()
	var first := camera.unproject_position(
		instance.global_transform * bounds.get_endpoint(0))
	var result := Rect2(first, Vector2.ZERO)
	for index in range(1, 8):
		result = result.expand(camera.unproject_position(
			instance.global_transform * bounds.get_endpoint(index)))
	return result


func _tiles_screen_bounds(camera: Camera3D, tiles: Array) -> Rect2:
	assert_false(tiles.is_empty())
	var result := _mesh_screen_bounds(camera, (tiles[0] as Tile3D)._mesh)
	for index in range(1, tiles.size()):
		result = result.merge(_mesh_screen_bounds(camera,
			(tiles[index] as Tile3D)._mesh))
	return result


func _hand_tiles(table: MahjongTable3D, seat_id: int) -> Array:
	return table._hand_tiles if seat_id == 0 else table._opp_tiles[seat_id]


func _assert_meld_on_player_right(seat_id: int, hand: Rect2, meld: Rect2,
		label: String) -> void:
	const GAP := 2.0
	match seat_id:
		0:
			assert_gte(meld.position.x, hand.end.x + GAP,
				"%s：自家副露必须在手牌屏幕右侧" % label)
		1:
			assert_lte(meld.end.y, hand.position.y - GAP,
				"%s：右家自身右侧对应屏幕上方" % label)
		2:
			assert_lte(meld.end.x, hand.position.x - GAP,
				"%s：对家自身右侧对应屏幕左方" % label)
		3:
			assert_gte(meld.position.y, hand.end.y + GAP,
				"%s：左家自身右侧对应屏幕下方" % label)


func test_opponent_hand_centers_apply_scale_once() -> void:
	var playable := PLAYABLE_TABLE.instantiate() as PlayableTable
	add_child_autofree(playable)
	playable.set_hybrid_enabled(true)
	await get_tree().process_frame
	var state := BattleState.for_east_round(41199, 0, 1, 0, 0)
	playable.bind_table_state(state, 0, 4)
	var table := playable.get("_hybrid_table_3d") as MahjongTable3D
	var expected_step := (Tile3D.TILE_W + 0.004) \
		* MahjongTable3D.OPPONENT_HAND_SCALE
	for seat_id in range(1, 4):
		var tiles: Array = table._opp_tiles[seat_id]
		assert_gte(tiles.size(), 2)
		var actual_step: float = (tiles[1] as Tile3D).position.distance_to(
			(tiles[0] as Tile3D).position)
		assert_almost_eq(actual_step, expected_step, 0.0001,
			"seat=%d：暗手中心步距只能应用一次 OPPONENT_HAND_SCALE" % seat_id)


func test_four_seats_one_to_four_melds_stay_on_each_players_right() -> void:
	var playable := PLAYABLE_TABLE.instantiate() as PlayableTable
	add_child_autofree(playable)
	playable.set_hybrid_enabled(true)
	await get_tree().process_frame
	var table := playable.get("_hybrid_table_3d") as MahjongTable3D
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(1600, 900))
	for group_count in range(1, 5):
		var state := BattleState.for_east_round(41200 + group_count, 0, 1, 0, 0)
		var concealed_count := 13 - group_count * 3
		for seat_id in range(4):
			_trim_hand(state.seats[seat_id], concealed_count)
			_add_pon_groups(state.seats[seat_id], group_count)
		playable.bind_table_state(state, 0, 4)
		await get_tree().process_frame
		for seat_id in range(4):
			var label := "seat=%d meld_count=%d" % [seat_id, group_count]
			var hand := _tiles_screen_bounds(table._camera, _hand_tiles(table, seat_id))
			var meld := _tiles_screen_bounds(table._camera, table._meld_tiles[seat_id])
			_assert_meld_on_player_right(seat_id, hand, meld, label)
			assert_true(viewport_rect.encloses(meld),
				"%s：副露不得裁切，rect=%s" % [label, meld])


func _make_kind_fixtures(claimant: int) -> Array[Meld]:
	var source := (claimant + 1) % 4
	var chi_tiles: Array[Tile] = [
		_tile(TileId.W1, claimant), _tile(TileId.W2, claimant),
		_tile(TileId.W3, source),
	]
	var pon_tiles: Array[Tile] = [
		_tile(TileId.T5, claimant), _tile(TileId.T5, source),
		_tile(TileId.T5, claimant),
	]
	var minkan_tiles: Array[Tile] = [
		_tile(TileId.S4, claimant), _tile(TileId.S4, source),
		_tile(TileId.S4, claimant), _tile(TileId.S4, claimant),
	]
	var ankan_tiles: Array[Tile] = [
		_tile(TileId.HAKU, claimant), _tile(TileId.HAKU, claimant),
		_tile(TileId.HAKU, claimant), _tile(TileId.HAKU, claimant),
	]
	var added_tiles: Array[Tile] = [
		_tile(TileId.CHUN, claimant), _tile(TileId.CHUN, source),
		_tile(TileId.CHUN, claimant), _tile(TileId.CHUN, claimant),
	]
	var added := Meld.make_pon(added_tiles.slice(0, 3), source, 16 + claimant,
		added_tiles[1])
	assert_true(added.promote_to_added_kan(added_tiles[3]))
	return [
		Meld.make_chi(chi_tiles, source, claimant, chi_tiles[2]),
		Meld.make_pon(pon_tiles, source, 4 + claimant, pon_tiles[1]),
		Meld.make_minkan(minkan_tiles, source, 8 + claimant, minkan_tiles[1]),
		Meld.make_ankan(ankan_tiles, 12 + claimant),
		added,
	]


func _yaw_delta(a: float, b: float) -> float:
	return absf(wrapf(a - b, -180.0, 180.0))


func test_five_meld_kinds_follow_meld_layout_slot_pose() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	for claimant in range(4):
		var melds := _make_kind_fixtures(claimant)
		table._rebuild_melds(claimant, melds)
		var node_index := 0
		for meld in melds:
			var slots := MeldLayout.compute(meld, claimant)
			var group_nodes: Array = []
			for slot in slots:
				var tile := table._meld_tiles[claimant][node_index] as Tile3D
				node_index += 1
				group_nodes.append(tile)
				var expected_instance_id := meld.added_tile_instance_id \
					if meld.kind == Meld.Kind.ADDED_KAN \
						and bool(slot["stacked_above"]) \
					else int(slot["tile_instance_id"])
				assert_eq(tile.tile_instance_id, expected_instance_id,
					"加杠叠牌用真实 added identity；其他槽保持 MeldLayout identity")
				assert_eq(tile.face_up, not bool(slot["face_down"]))
				var base_yaw: float = float([0.0, -90.0, 180.0, 90.0][claimant])
				var expected_yaw: float = base_yaw \
					+ (90.0 if bool(slot["rotated"]) else 0.0)
				assert_lte(_yaw_delta(tile.rotation_degrees.y, expected_yaw), 0.01)
				if bool(slot["stacked_above"]):
					var found_anchor := false
					for candidate in group_nodes:
						if candidate == tile:
							continue
						if Vector2(candidate.position.x, candidate.position.z).is_equal_approx(
								Vector2(tile.position.x, tile.position.z)):
							found_anchor = true
							assert_gt(tile.position.y, candidate.position.y)
					assert_true(found_anchor, "加杠叠牌必须位于原横牌正上方")
