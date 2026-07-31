extends GutTest

const PLAYABLE_TABLE := preload("res://ui/four_player_table/playable_table.tscn")
const PUBLIC_ADAPTER := preload(
	"res://ui/four_player_table/public_table_projection_adapter.gd")


func _tile(tile_id: int, iid: int, p_owner: int, red := false) -> Dictionary:
	return {
		"tile_id": tile_id,
		"instance_id": iid,
		"owner_seat": p_owner,
		"is_red_dora": red,
	}


func _core(recipient: int) -> Dictionary:
	var seats: Array = []
	for absolute_seat in range(4):
		var concealed: Array = []
		var count := 13
		if absolute_seat == recipient:
			concealed = [
				_tile(TileId.W5, 420000 + absolute_seat * 10, absolute_seat, true),
				_tile(TileId.T6, 420001 + absolute_seat * 10, absolute_seat),
			]
			count = concealed.size()
		var melds: Array = []
		if absolute_seat == 1:
			var source := 2
			var called := _tile(TileId.HAKU, 421101, source)
			melds = [{
				"meld_id": 1,
				"kind": "PON",
				"from_seat": source,
				"called_tile_instance_id": int(called["instance_id"]),
				"added_tile_instance_id": Tile.INVALID_INSTANCE_ID,
				"tiles": [
					_tile(TileId.HAKU, 421100, absolute_seat),
					called,
					_tile(TileId.HAKU, 421102, absolute_seat),
				],
			}]
		seats.append({
			"seat": absolute_seat,
			"seat_wind": [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N][absolute_seat],
			"score": 25000,
			"concealed_tiles": concealed,
			"concealed_count": count,
			"last_drawn_tile_instance_id": Tile.INVALID_INSTANCE_ID,
			"river": [_tile(TileId.W1 + absolute_seat,
				422000 + absolute_seat, absolute_seat)],
			"melds": melds,
			"riichi_declared": absolute_seat == 3,
			"riichi_double": false,
			"riichi_discard_index": 0 if absolute_seat == 3 else -1,
		})
	return {
		"recipient_seat": recipient,
		"hand_seq": 0,
		"dealer_seat": 0,
		"current_seat": recipient,
		"phase": "DISCARD",
		"round_wind": TileId.E,
		"hand_number": 1,
		"honba": 0,
		"riichi_sticks": 1,
		"live_wall_count": 70,
		"dora_indicators": [_tile(TileId.S1, 423000, Tile.NO_OWNER)],
		"seats": seats,
	}


func test_public_core_projects_four_recipients_without_battle_state_or_privacy_leak() -> void:
	for recipient in range(4):
		var playable := PLAYABLE_TABLE.instantiate() as PlayableTable
		add_child_autofree(playable)
		playable.set_hybrid_enabled(true)
		await get_tree().process_frame
		var renderer := playable.get("_hybrid_table_3d") as MahjongTable3D
		assert_true(renderer.has_method("bind_core_table_view"),
			"公共 renderer 必须直接消费 renderer-neutral core view")
		if not renderer.has_method("bind_core_table_view"):
			return
		renderer.call("bind_core_table_view", _core(recipient))
		assert_null(renderer._state, "公共投影不得伪造 BattleState")
		assert_eq(renderer._hand_tiles.size(), 2)
		for relative_seat in range(1, 4):
			assert_eq(renderer._opp_tiles[relative_seat].size(), 13)
			for tile in renderer._opp_tiles[relative_seat]:
				assert_lt((tile as Tile3D).tile_id, 0,
					"他席只允许稳定牌背槽，不得泄露牌面")
		for absolute_seat in range(4):
			var relative := (absolute_seat - recipient + 4) % 4
			assert_eq((renderer._river_tiles[relative][0] as Tile3D).tile_id,
				TileId.W1 + absolute_seat)
		var meld_relative := (1 - recipient + 4) % 4
		assert_eq(renderer._meld_tiles[meld_relative].size(), 3)
		var before_hidden := renderer._opp_tiles[1][0] as Tile3D
		renderer.call("bind_core_table_view", _core(recipient))
		assert_same(renderer._opp_tiles[1][0], before_hidden,
			"公共暗手 stable slot 重绑不得闪烁")
		playable.queue_free()
		await get_tree().process_frame


func test_renderer_view_preserves_authorized_opponent_subset_without_expanding_visibility() -> void:
	var core := _core(0)
	var opponent := (core["seats"] as Array)[2] as Dictionary
	opponent["concealed_tiles"] = [
		_tile(TileId.S2, 424200, 2),
		_tile(TileId.S3, 424201, 2),
	]
	opponent["concealed_count"] = 13

	var view: Dictionary = PUBLIC_ADAPTER.renderer_view(core)
	var opponent_view := (view["seats"] as Array)[2] as Dictionary
	var visible := opponent_view["concealed_tiles"] as Array
	assert_eq(visible.size(), 2,
		"上游按 recipient 授权的他席可见子集不得在 adapter 丢失")
	if visible.size() == 2:
		assert_eq((visible[0] as Tile).instance_id, 424200)
		assert_eq((visible[1] as Tile).instance_id, 424201)
	opponent["concealed_count"] = 1
	var clipped_view := (PUBLIC_ADAPTER.renderer_view(core)["seats"] as Array)[2] \
		as Dictionary
	assert_eq((clipped_view["concealed_tiles"] as Array).size(), 1,
		"adapter 即使被直接调用也不得输出超过 concealed_count 的 identity")

	var no_data_view := (view["seats"] as Array)[1] as Dictionary
	assert_eq((no_data_view["concealed_tiles"] as Array).size(), 0,
		"上游未授权牌面时仍只能投影 concealed_count")
	assert_eq(int(no_data_view["concealed_count"]), 13)

	opponent["concealed_count"] = 13
	var playable := PLAYABLE_TABLE.instantiate() as PlayableTable
	add_child_autofree(playable)
	playable.set_hybrid_enabled(true)
	await get_tree().process_frame
	var renderer := playable.get("_hybrid_table_3d") as MahjongTable3D
	renderer.bind_core_table_view(core)
	assert_eq(renderer._opp_tiles[2].size(), 13)
	assert_eq((renderer._opp_tiles[2][0] as Tile3D).tile_id, TileId.S2)
	assert_eq((renderer._opp_tiles[2][1] as Tile3D).tile_id, TileId.S3)
	for tile in renderer._opp_tiles[2].slice(2):
		assert_lt((tile as Tile3D).tile_id, 0,
			"renderer 只能把上游授权子集翻面，其余仍是稳定牌背槽")


func test_renderer_view_has_drawn_is_identity_exact_for_self_and_count_based_for_others() -> void:
	var core := _core(0)
	var own := (core["seats"] as Array)[0] as Dictionary
	var own_tiles := own["concealed_tiles"] as Array
	own["last_drawn_tile_instance_id"] = int((own_tiles[1] as Dictionary)["instance_id"])
	var own_view := (PUBLIC_ADAPTER.renderer_view(core)["seats"] as Array)[0] as Dictionary
	assert_eq(own_view.get("has_drawn", null), true,
		"本席 has_drawn 必须由 exact last_drawn identity 决定")

	own["last_drawn_tile_instance_id"] = Tile.INVALID_INSTANCE_ID
	own_view = (PUBLIC_ADAPTER.renderer_view(core)["seats"] as Array)[0] as Dictionary
	assert_eq(own_view.get("has_drawn", null), false,
		"本席即使牌数余 2，无 exact last_drawn 也不是摸牌间隔")

	for count in range(15):
		var count_core := _core(0)
		var opponent := (count_core["seats"] as Array)[1] as Dictionary
		opponent["concealed_count"] = count
		var opponent_view := (
			PUBLIC_ADAPTER.renderer_view(count_core)["seats"] as Array)[1] as Dictionary
		assert_eq(opponent_view.get("has_drawn", null), count % 3 == 2,
			"他席 count=%d 的摸牌间隔推导错误" % count)

	var fourteen_core := _core(0)
	((fourteen_core["seats"] as Array)[1] as Dictionary)["concealed_count"] = 14
	var playable := PLAYABLE_TABLE.instantiate() as PlayableTable
	add_child_autofree(playable)
	playable.set_hybrid_enabled(true)
	await get_tree().process_frame
	var renderer := playable.get("_hybrid_table_3d") as MahjongTable3D
	renderer.bind_core_table_view(fourteen_core)
	var tiles: Array = renderer._opp_tiles[1]
	var regular := Vector2((tiles[12] as Tile3D).position.x,
		(tiles[12] as Tile3D).position.z).distance_to(Vector2(
		(tiles[11] as Tile3D).position.x, (tiles[11] as Tile3D).position.z))
	var drawn := Vector2((tiles[13] as Tile3D).position.x,
		(tiles[13] as Tile3D).position.z).distance_to(Vector2(
		(tiles[12] as Tile3D).position.x, (tiles[12] as Tile3D).position.z))
	assert_gt(drawn, regular + 0.02,
		"公共暗手 14 张必须保留稳定末槽摸牌间隔")
