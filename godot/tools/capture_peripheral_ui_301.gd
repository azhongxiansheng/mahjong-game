extends SceneTree

# Issue #301 外围层截图矩阵：同一 1600×900 逻辑舞台下验证两档窗口。

const LOGICAL_SIZE := Vector2i(1600, 900)
const SIZES := [Vector2i(1600, 900), Vector2i(1280, 720)]
const LOBBY_SCENE := "res://ui/lobby/lobby_shell.tscn"


func _initialize() -> void:
	_run()


func _run() -> void:
	root.content_scale_size = LOGICAL_SIZE
	for size in SIZES:
		await _capture_lobby(size, "drawer", func(shell): shell.request_practice())
		await _capture_lobby(size, "codex_characters", func(shell):
			(shell.get_node("%CharacterCodexButton") as Button).pressed.emit())
		await _capture_lobby(size, "codex_items", func(shell):
			(shell.get_node("%ItemCodexButton") as Button).pressed.emit())
		await _capture_lobby(size, "codex_rules", func(shell):
			(shell.get_node("%RulesButton") as Button).pressed.emit())
		await _capture_lobby(size, "settings", func(shell):
			(shell.get_node("%SettingsButton") as Button).pressed.emit())
		await _capture_lobby(size, "joining", func(shell):
			var coordinator = shell.get_node("PublicMatchCoordinator")
			coordinator._set_view({
				"state": "joining", "round_kind": "EAST", "game_mode": "STANDARD",
				"can_cancel": false, "can_retry": false,
			}))
		await _capture_lobby(size, "waiting", func(shell):
			var coordinator = shell.get_node("PublicMatchCoordinator")
			coordinator.consume_ticket_for_test({
				"ticket_id": "screenshot-only", "status": "waiting",
				"round_kind": "EAST", "game_mode": "STANDARD",
				"queued_at": "2026-07-28T00:00:00Z", "deadline_at": "2026-07-28T00:01:00Z",
			}))
		await _capture_lobby(size, "reconnecting", func(shell):
			var coordinator = shell.get_node("PublicMatchCoordinator")
			coordinator.consume_connection_fact_for_test(&"reconnecting", "WS_CLOSED", "连接已断开，等待重新连接。"))
		await _capture_lobby(size, "terminal_error", func(shell):
			var coordinator = shell.get_node("PublicMatchCoordinator")
			coordinator.consume_connection_fact_for_test(&"terminal_error", "ROOM_FAILED", "匹配房间暂不可用。"))
		await _capture_hand_settlement(size)
		await _capture_match_settlement(size)
	print("[capture-301] done")
	quit()


func _capture_lobby(window_size: Vector2i, tag: String, setup: Callable) -> void:
	DisplayServer.window_set_size(window_size)
	var packed := load(LOBBY_SCENE) as PackedScene
	var shell := packed.instantiate()
	root.add_child(shell)
	await _frames(8)
	setup.call(shell)
	await _frames(14)
	await _save("lobby_%s" % tag, window_size)
	var settings := root.get_node_or_null("_settings_overlay_root")
	if settings != null:
		root.remove_child(settings)
		settings.queue_free()
	root.remove_child(shell)
	shell.queue_free()
	await _frames(2)


func _capture_hand_settlement(window_size: Vector2i) -> void:
	DisplayServer.window_set_size(window_size)
	var playable = load("res://ui/four_player_table/playable_table.gd").new()
	root.add_child(playable)
	await _frames(8)
	var controller_script = load("res://battle/playable_battle_controller.gd")
	playable._bc = controller_script.new(301)
	playable._show_hand_result_overlay({"last_event": "ABORTIVE_DRAW"})
	await create_timer(0.8).timeout
	await _frames(4)
	await _save("hand_settlement", window_size)
	root.remove_child(playable)
	playable.queue_free()
	await _frames(2)


func _capture_match_settlement(window_size: Vector2i) -> void:
	DisplayServer.window_set_size(window_size)
	var playable = load("res://ui/four_player_table/playable_table.gd").new()
	root.add_child(playable)
	await _frames(8)
	var panel_script = load("res://ui/four_player_table/match_settlement_panel.gd")
	var settlement_script = load("res://session/match_settlement.gd")
	var panel = panel_script.new()
	playable.add_child(panel)
	panel.present(settlement_script.build_view([32000, 28000, 22000, 18000], &"EAST"))
	await _frames(8)
	await _save("match_settlement", window_size)
	root.remove_child(playable)
	playable.queue_free()
	await _frames(2)


func _save(tag: String, window_size: Vector2i) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image.get_size() != window_size:
		image.resize(window_size.x, window_size.y, Image.INTERPOLATE_LANCZOS)
	var path := "/tmp/shot_301_%s_%dx%d.png" % [tag, window_size.x, window_size.y]
	image.save_png(path)
	print("[capture-301] ", path, " actual=", image.get_width(), "x", image.get_height())


func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame
