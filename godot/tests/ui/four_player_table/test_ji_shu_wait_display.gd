extends GutTest


func test_only_local_ji_shu_view_shows_opponent_waits_in_safe_strip() -> void:
	var table := FourPlayerTable.new()
	add_child_autofree(table)
	await get_tree().process_frame
	table.set_local_seat(0)
	table.set_viewer_reveal_label("圣裁")
	var state := BattleState.for_east_round(346, 0, 1, 0, 0)
	state.tenpai_wait_reveals = {0: {1: [TileId.S_WIND]}}
	table.bind_battle_state(state, 0, 4)
	assert_eq((table.seat_panels[1] as SeatPanel).viewer_reveal_count(), 1)
	assert_eq((table.seat_panels[1] as SeatPanel).viewer_reveal_label(), "圣裁")
	for seat in [2, 3]:
		assert_eq((table.seat_panels[seat] as SeatPanel).viewer_reveal_count(), 0)
	table.set_local_seat(2)
	table.bind_battle_state(state, 0, 4)
	assert_eq((table.seat_panels[1] as SeatPanel).viewer_reveal_count(), 0,
		"非 recipient 视角不得看到纪枢私有等待牌")


func test_network_optional_absence_clears_old_wait_display() -> void:
	var table := FourPlayerTable.new()
	add_child_autofree(table)
	await get_tree().process_frame
	table.set_local_seat(0)
	table.apply_viewer_tenpai_waits_view({
		"recipient_seat": 0,
		"hand_seq": 0,
		"subjects": [{"seat": 3, "wait_tile_ids": [TileId.W1, TileId.W4]}],
	})
	assert_eq((table.seat_panels[3] as SeatPanel).viewer_reveal_count(), 2)
	table.apply_viewer_tenpai_waits_view({})
	assert_eq((table.seat_panels[3] as SeatPanel).viewer_reveal_count(), 0)
