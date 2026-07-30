extends SceneTree

const CAPTURE_SIZE := Vector2i(1600, 900)
const VIEWS := [&"main", &"top", &"south", &"east", &"north", &"west"]

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


func _add_all_meld_kinds(state: Variant) -> void:
	var pon := _fixture_tiles([TileId.T7, TileId.T7, TileId.T7], 0)
	state.seats[0].melds.add_pon(pon, 2, pon[1])
	var minkan := _fixture_tiles([TileId.E, TileId.E, TileId.E, TileId.E], 0)
	state.seats[0].melds.add_minkan(minkan, 3, minkan[2])
	var chi := _fixture_tiles([TileId.W3, TileId.W4, TileId.W5], 1)
	state.seats[1].melds.add_chi(chi, 0, chi[1])
	var ankan := _fixture_tiles(
		[TileId.CHUN, TileId.CHUN, TileId.CHUN, TileId.CHUN], 2)
	state.seats[2].melds.add_ankan(ankan)
	var added := _fixture_tiles(
		[TileId.S5, TileId.S5, TileId.S5, TileId.S5], 3)
	state.seats[3].melds.add_existing(Meld.make_added_kan(
		added, 0, 405399, added[0]))


func _new_state(battle_script: Script, seed: int) -> Variant:
	var battle: Variant = battle_script.new(seed, 0, false, 27)
	return battle.state


func _capture(path: String) -> bool:
	await _wait_frames(8)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	var error := image.save_png(path)
	print("[capture-405] output=", path, " size=", image.get_size(),
		" format=", image.get_format(), " error=", error)
	return error == OK


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
	root.content_scale_size = CAPTURE_SIZE
	DisplayServer.window_set_size(CAPTURE_SIZE)
	await _wait_frames(3)
	var packed := load("res://ui/lobby/lobby_shell.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	var lobby := packed.instantiate()
	root.add_child(lobby)
	await _wait_frames(12)
	var coordinator: Node = lobby.get_node("PracticeMatchCoordinator")
	var table := coordinator.call("mount_playable_table") as Node
	if table == null:
		quit(2)
		return
	table.set_hybrid_enabled(true)
	table.set_player_persona("林夜彻",
		"res://assets/roguelike/characters/char_lin_yeche.png")
	var battle_script := load("res://battle/battle_controller.gd") as Script
	var hybrid := table.get("_hybrid_table_3d") as Node

	var opening: Variant = _new_state(battle_script, 40501)
	_bind_state(table, opening)
	table._action_panel.enter_idle("等待 AI…")
	hybrid.set_camera_view(&"main")
	if not await _capture("/tmp/mahjong-405-hybrid-opening.png"):
		quit(3)
		return

	var crowded: Variant = _new_state(battle_script, 40502)
	_append_rivers(crowded, 12)
	_consume_wall(crowded, 36)
	_add_midgame_meld(crowded)
	_bind_state(table, crowded)
	if not await _capture("/tmp/mahjong-405-hybrid-midgame_crowded.png"):
		quit(3)
		return

	var riichi: Variant = _new_state(battle_script, 40503)
	_append_rivers(riichi, 8, 0)
	_consume_wall(riichi, 24)
	_bind_state(table, riichi)
	if not await _capture("/tmp/mahjong-405-hybrid-riichi.png"):
		quit(3)
		return

	var melds: Variant = _new_state(battle_script, 40504)
	_append_rivers(melds, 6)
	_consume_wall(melds, 28)
	_add_all_meld_kinds(melds)
	_bind_state(table, melds)
	# 上一张 riichi 图保留真实 -1000 反馈；独立 melds 验收清掉跨状态
	# 的临时飘字，业务分数与投影状态不做改写。
	_clear_score_float_labels(table)
	if not await _capture("/tmp/mahjong-405-hybrid-melds.png"):
		quit(3)
		return

	var action: Variant = _new_state(battle_script, 40505)
	_append_rivers(action, 5)
	_consume_wall(action, 20)
	_bind_state(table, action)
	hybrid.set_hand_clickable(true)
	table._action_panel.enter_waiting_discard(true, true, true, false, true, false)
	if not await _capture("/tmp/mahjong-405-hybrid-action.png"):
		quit(3)
		return

	hybrid.set_hand_clickable(false)
	table._action_panel.enter_idle("本局结束")
	_bind_state(table, crowded)
	table._present_public_hand_settlement({
		"outcome": "TSUMO", "winner_seats": [0], "loser_seat": -1,
		"score_deltas": [6000, -2000, -2000, -2000],
		"scores": [31000, 23000, 23000, 23000],
	})
	if not await _capture("/tmp/mahjong-405-hybrid-settlement.png"):
		quit(3)
		return
	table._clear_public_hand_settlement_overlay()

	_bind_state(table, opening)
	for view in VIEWS:
		hybrid.set_camera_view(view)
		if not await _capture("/tmp/mahjong-405-hybrid-%s.png" % String(view)):
			quit(3)
			return

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
	quit(0)
