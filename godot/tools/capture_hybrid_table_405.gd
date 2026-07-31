extends SceneTree

const CAPTURE_SIZES := [Vector2i(1600, 900), Vector2i(1280, 720)]
const LOGICAL_SIZE := Vector2i(1600, 900)

var _next_instance_id := 405000


func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _fixture_tile(tile_id: int, owner: int = -1) -> Variant:
	var tile := Tile.new(tile_id, false, owner, _next_instance_id)
	_next_instance_id += 1
	return tile


func _fixture_tiles(ids: Array, owner: int) -> Array[Tile]:
	var output: Array[Tile] = []
	for tile_id in ids:
		output.append(_fixture_tile(int(tile_id), owner))
	return output


func _trim_hand(seat: Seat, target_count: int) -> void:
	while seat.hand.size() > target_count:
		var tile := seat.hand.first()
		if tile == null:
			return
		seat.hand.take_by_instance_id(tile.instance_id)
	seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID


func _append_rivers(state: Variant, count: int,
		riichi_seat: int = -1) -> void:
	for seat_id in range(4):
		for index in range(count):
			var tile_id: int = TileId.ALL[(seat_id * 7 + index) % TileId.ALL.size()]
			state.seats[seat_id].river.append_discard(
				_fixture_tile(tile_id, seat_id),
				seat_id == riichi_seat and index == count - 1)
	if riichi_seat >= 0:
		state.seats[riichi_seat].riichi.declared = true
		state.seats[riichi_seat].points -= 1000
		state.riichi_sticks = 1


func _consume_wall(state: Variant, count: int) -> void:
	for _index in range(count):
		if state.wall.draw() == null:
			return


func _add_midgame_meld(state: Variant) -> void:
	var tiles := _fixture_tiles([TileId.W3, TileId.W4, TileId.W5], 1)
	state.seats[1].melds.add_chi(tiles, 0, tiles[1])
	_trim_hand(state.seats[1], 10)


func _add_all_meld_kinds(state: Variant) -> bool:
	var pon := _fixture_tiles([TileId.T7, TileId.T7, TileId.T7], 0)
	if state.seats[0].melds.add_pon(pon, 2, pon[1]) == null:
		return false
	var minkan := _fixture_tiles([TileId.E, TileId.E, TileId.E, TileId.E], 0)
	if state.seats[0].melds.add_minkan(minkan, 3, minkan[2]) == null:
		return false
	var chi := _fixture_tiles([TileId.W3, TileId.W4, TileId.W5], 1)
	if state.seats[1].melds.add_chi(chi, 0, chi[1]) == null:
		return false
	var ankan := _fixture_tiles(
		[TileId.CHUN, TileId.CHUN, TileId.CHUN, TileId.CHUN], 2)
	if state.seats[2].melds.add_ankan(ankan) == null:
		return false
	var called := _fixture_tile(TileId.S5, 0) as Tile
	var added := _fixture_tile(TileId.S5, 3) as Tile
	var added_kan := Meld.make_pon([
		_fixture_tile(TileId.S5, 3), called, _fixture_tile(TileId.S5, 3),
	], 0, 405399, called)
	if not added_kan.promote_to_added_kan(added) \
			or not state.seats[3].melds.add_existing(added_kan):
		return false
	_trim_hand(state.seats[0], 7)
	for seat_id in range(1, 4):
		_trim_hand(state.seats[seat_id], 10)
	return true


func _new_state(battle_script: Script, seed: int) -> Variant:
	var battle: Variant = battle_script.new(seed, 0, false, 27)
	return battle.state


func _capture(path: String, expected_size: Vector2i) -> bool:
	await _wait_frames(8)
	# 8 个完整 process frame 已让 SubViewport.UPDATE_ALWAYS 提交新画面；这里不再
	# 单独等待 frame_post_draw，避免 macOS 在运行中缩放窗口后信号偶发停滞。
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	var error := image.save_png(path)
	print("[capture-405] output=", path, " size=", image.get_size(),
		" format=", image.get_format(), " error=", error)
	return error == OK and image.get_size() == expected_size


func _output_path(capture_size: Vector2i, state_name: String) -> String:
	return "/tmp/mahjong-405-hybrid-%dx%d-%s.png" % [
		capture_size.x, capture_size.y, state_name,
	]


func _bind_state(table: Node, state: Variant) -> void:
	table.bind_table_state(state, 0, 4)
	table._sync_dora_widget(state)


func _clear_score_float_labels(table: Node) -> void:
	for node in table.find_children("*", "Label", true, false):
		var label := node as Label
		if label != null and label.z_index == 50 \
				and (label.text.begins_with("+") or label.text.begins_with("-")):
			# SeatPanel 的定时回调仍捕获该 Label；只隐藏，交回原生命周期释放。
			label.visible = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for capture_size in CAPTURE_SIZES:
		var result := await _capture_size(capture_size)
		if result != OK:
			quit(result)
			return
	print("[capture-405] done sizes=", CAPTURE_SIZES)
	quit(0)


func _capture_size(capture_size: Vector2i) -> int:
	# 产品使用固定 1600×900 stage + canvas_items 等比缩放；1280×720 应验证
	# 完整桌面缩小后的结果，而不是把固定 stage 右侧/底部直接裁掉。
	root.content_scale_size = LOGICAL_SIZE
	DisplayServer.window_set_size(capture_size)
	await _wait_frames(3)
	var packed := load("res://ui/lobby/lobby_shell.tscn") as PackedScene
	if packed == null:
		return 1
	var lobby := packed.instantiate()
	root.add_child(lobby)
	await _wait_frames(12)
	var coordinator: Node = lobby.get_node("PracticeMatchCoordinator")
	var table := coordinator.call("mount_playable_table") as Node
	if table == null:
		lobby.queue_free()
		return 2
	table.set_hybrid_enabled(true)
	table.set_player_persona("林夜彻",
		"res://assets/roguelike/characters/char_lin_yeche.png")
	var battle_script := load("res://battle/battle_controller.gd") as Script
	var hybrid := table.get("_hybrid_table_3d") as Node

	var opening: Variant = _new_state(battle_script, 40501)
	_bind_state(table, opening)
	table._action_panel.enter_idle("等待 AI…")
	hybrid.set_camera_view(&"main")
	if not await _capture(_output_path(capture_size, "opening"), capture_size):
		lobby.queue_free()
		return 3

	var crowded: Variant = _new_state(battle_script, 40502)
	_append_rivers(crowded, 24)
	_consume_wall(crowded, 36)
	_add_midgame_meld(crowded)
	_bind_state(table, crowded)
	if not await _capture(
			_output_path(capture_size, "midgame_crowded"), capture_size):
		lobby.queue_free()
		return 3

	var riichi: Variant = _new_state(battle_script, 40503)
	_append_rivers(riichi, 8, 0)
	_consume_wall(riichi, 24)
	_bind_state(table, riichi)
	if not await _capture(_output_path(capture_size, "riichi"), capture_size):
		lobby.queue_free()
		return 3

	var melds: Variant = _new_state(battle_script, 40504)
	_append_rivers(melds, 6)
	_consume_wall(melds, 28)
	if not _add_all_meld_kinds(melds):
		push_error("[capture-405] failed to build all five meld kinds")
		lobby.queue_free()
		return 4
	_bind_state(table, melds)
	# 上一张 riichi 图保留真实 -1000 反馈；独立 melds 验收清掉跨状态
	# 的临时飘字，业务分数与投影状态不做改写。
	_clear_score_float_labels(table)
	if not await _capture(_output_path(capture_size, "melds"), capture_size):
		lobby.queue_free()
		return 3

	var action: Variant = _new_state(battle_script, 40505)
	_append_rivers(action, 5)
	_consume_wall(action, 20)
	_bind_state(table, action)
	hybrid.set_hand_clickable(true)
	var allowed: Array = []
	for index in range(mini(4, hybrid._hand_tiles.size())):
		allowed.append((hybrid._hand_tiles[index] as Tile3D).tile_instance_id)
	if not allowed.is_empty():
		hybrid.dim_hand_except(allowed)
		hybrid.set_selected_instances([allowed[0]])
		table._table.highlight_tile_id(
			(hybrid._hand_tiles[0] as Tile3D).tile_id)
	table._action_panel.enter_waiting_discard(true, true, true, false, true, false)
	if not await _capture(_output_path(capture_size, "action"), capture_size):
		lobby.queue_free()
		return 3

	hybrid.set_hand_clickable(false)
	hybrid.clear_hand_dim()
	hybrid.set_selected_instances([])
	table._table.clear_tile_highlight()
	table._action_panel.enter_idle("本局结束")
	_bind_state(table, crowded)
	table._table.reveal_seat_hand_face_up(1, crowded.seats[1].hand, false)
	var settlement_win_tile := crowded.seats[1].hand.first() as Tile
	if settlement_win_tile != null:
		table._table.mark_win_tile(settlement_win_tile.id, 1)
	table._present_public_hand_settlement({
		"outcome": "TSUMO", "winner_seats": [1], "loser_seat": -1,
		"score_deltas": [-2000, 6000, -2000, -2000],
		"scores": [23000, 31000, 23000, 23000],
	})
	if not await _capture(_output_path(capture_size, "settlement"), capture_size):
		lobby.queue_free()
		return 3
	table._clear_public_hand_settlement_overlay()

	# SeatPanel 的分数飘字通过 1.55s SceneTreeTimer 释放；等回调完成后再销毁
	# 本轮 Lobby，避免跨分辨率时 lambda 捕获已释放 Label。
	await create_timer(1.6).timeout
	lobby.queue_free()
	opening = null
	crowded = null
	riichi = null
	melds = null
	action = null
	hybrid = null
	table = null
	coordinator = null
	battle_script = null
	lobby = null
	packed = null
	await _wait_frames(3)
	return OK
