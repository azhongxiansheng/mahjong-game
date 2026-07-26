extends SceneTree

# Issue #304 独立牌桌截图矩阵。所有生产脚本均在 Autoload 就绪后运行时加载，
# 避免综合截图工具的大厅/Anima 早期编译噪音污染牌桌验收证据。

const CAPTURE_SIZE := Vector2i(1600, 900)


func _initialize() -> void:
	_run()


func _save(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "/tmp/shot_304_%s.png" % tag
	image.save_png(path)
	print("[capture-304] saved ", path)


func _frames(count: int = 8) -> void:
	for _index in range(count):
		await process_frame


func _run() -> void:
	root.content_scale_size = CAPTURE_SIZE
	DisplayServer.window_set_size(CAPTURE_SIZE)
	await _frames(2)
	var table_script = load("res://ui/four_player_table/playable_table.gd")
	var battle_script = load("res://battle/playable_battle_controller.gd")
	if table_script == null or battle_script == null:
		push_error("[capture-304] production script load failed")
		quit(1)
		return
	var table = table_script.new()
	root.add_child(table)
	table.set_player_persona("林夜彻",
		"res://assets/roguelike/characters/char_lin_yeche.png")
	var battle = battle_script.new(42, 0, false, 27)
	table._table.bind_battle_state(battle.state, 0, 4)
	await _frames(30)
	await _save("normal")

	var player = table._table.seat_panels[0]
	var allowed: Array = []
	for slot_index in mini(3, player._hand_slots.size()):
		allowed.append(int(player._hand_slots[slot_index].get_meta(
			"hand_instance_id", -1)))
	player.set_hand_clickable(true)
	player.dim_hand_except(allowed)
	table._action_panel.enter_waiting_claim(true, true, true, true, 1)
	await _frames()
	await _save("claim_candidates")

	player.clear_hand_dim()
	table._action_panel.enter_waiting_riichi_confirm()
	player.set_riichi(true)
	await _frames()
	await _save("riichi_confirm")

	table._action_panel.enter_idle("等待 AI…")
	player.set_riichi(false)
	player.set_hand_clickable(false)
	table._play_call_announce(&"pon", 1)
	await _frames(4)
	await _save("pon_after")
	await _frames(100)

	table._play_confirmed_moment_band([{"name": "海底捞月", "han": 1}])
	await _frames(20)
	await _save("high_impact_band")
	var moment = table.get_node_or_null("MomentBand")
	if moment != null:
		moment.queue_free()
	await process_frame

	var result: Dictionary = battle.run_to_end()
	table._bc = battle
	table._table.bind_battle_state(battle.state, 0, 4)
	table._show_hand_result_overlay(result)
	await _frames(220)
	await _save("settlement_entry")
	var overlay: Node = table.get_node_or_null("ResultOverlay")
	if overlay != null:
		var buttons: Array[Node] = overlay.find_children(
			"*", "Button", true, false)
		if not buttons.is_empty():
			(buttons[0] as Button).pressed.emit()
	await _frames(30)
	table.queue_free()
	await _frames(10)
	var win_table = table_script.new()
	root.add_child(win_table)
	win_table._table.bind_battle_state(battle.state, 0, 4)
	await _frames(8)
	win_table._play_call_announce(&"ron", 1)
	await _frames(4)
	await _save("win_announce")
	win_table.queue_free()
	await _frames(10)
	print("[capture-304] done")
	quit()
