extends GutTest

# E4-01（#243）：PlayableTable 从真实 bc.mode_modules.voice_port 绑定 PTT UI / 采集 / 播放。


func _make_config(mode: StringName, session_id: String) -> GameSessionConfig:
	var intent := SessionIntent.new(&"PRACTICE", &"EAST", mode, &"lin_yeche")
	var converted := GameSessionConfig.from_intent(
		intent, 42, session_id, "e4-01-v1", {}
	)
	assert_true(converted.ok, str(converted.error_code))
	return converted.config


func _launch_pbc(mode: StringName, session_id: String) -> PlayableBattleController:
	var cfg := _make_config(mode, session_id)
	var driver := PracticeSessionLauncher.new().launch(cfg)
	assert_not_null(driver)
	var bc: PlayableBattleController = driver.bc_factory.call(
		cfg.seed, 0, false, TileId.E, 0
	)
	assert_not_null(bc)
	return bc


func test_standard_has_no_ptt_button_or_voice_nodes() -> void:
	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child_autofree(table)
	await get_tree().process_frame
	var bc := _launch_pbc(&"STANDARD", "std-ptt")
	assert_null(bc.mode_modules.voice_port)
	table.bind_voice_from_battle(bc)
	await get_tree().process_frame
	assert_null(table.get_node_or_null("PttButton"))
	assert_null(table.get_node_or_null("PttStatusLabel"))
	assert_null(table.get_node_or_null("VoiceCapturePipeline"))
	assert_null(table.get_node_or_null("VoicePlaybackRouter"))
	assert_false(table.has_voice_runtime())


func test_trash_talk_creates_ptt_button_and_wires_press_release() -> void:
	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child_autofree(table)
	await get_tree().process_frame
	var bc := _launch_pbc(&"TRASH_TALK", "tt-ptt")
	assert_not_null(bc.mode_modules.voice_port)
	var vp: VoicePortModule = bc.mode_modules.voice_port
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	table.bind_voice_from_battle(bc)
	await get_tree().process_frame

	var btn := table.get_node_or_null("PttButton") as BaseButton
	assert_not_null(btn, "欢乐场必须有 PTT 按钮")
	assert_true(btn.visible)
	assert_true(String(btn.text).contains("按住说话") or String(btn.text).contains("🎙"))

	var controls: Array = []
	vp.outbound_control.connect(func(m: Dictionary): controls.append(m.duplicate(true)))

	btn.button_down.emit()
	await get_tree().process_frame
	assert_true(vp.is_ptt_pressed())
	assert_eq(controls.size(), 1)
	assert_eq(String(controls[0].get("kind", "")), "PTT_START")

	var status := table.get_node_or_null("PttStatusLabel") as Label
	assert_not_null(status)
	assert_true(String(status.text).contains("正在说话"))

	btn.button_up.emit()
	await get_tree().process_frame
	assert_false(vp.is_ptt_pressed())
	assert_eq(controls.size(), 2)
	assert_eq(String(controls[1].get("kind", "")), "PTT_END")


func test_trash_talk_creates_playback_router_for_remote_seats() -> void:
	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child_autofree(table)
	await get_tree().process_frame
	var bc := _launch_pbc(&"TRASH_TALK", "tt-play")
	bc.mode_modules.voice_port.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	table.bind_voice_from_battle(bc)
	await get_tree().process_frame
	var router := table.get_node_or_null("VoicePlaybackRouter") as VoicePlaybackRouter
	assert_not_null(router)
	assert_true(router.has_player_for_seat(1))
	assert_true(router.has_player_for_seat(2))
	assert_true(router.has_player_for_seat(3))


func test_exit_tree_releases_voice_resources() -> void:
	var table: PlayableTable = load("res://ui/four_player_table/playable_table.gd").new()
	add_child(table)
	await get_tree().process_frame
	var bc := _launch_pbc(&"TRASH_TALK", "tt-exit")
	var vp: VoicePortModule = bc.mode_modules.voice_port
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	table.bind_voice_from_battle(bc)
	await get_tree().process_frame
	assert_true(vp.press_ptt())
	assert_true(vp.is_ptt_pressed())
	table.free()
	await get_tree().process_frame
	assert_false(vp.is_ptt_pressed())
	assert_false(vp.is_capturing())
	assert_eq(vp.outbound_queue_size(), 0)


func test_practice_return_to_lobby_releases_voice() -> void:
	var lobby_scene := load("res://ui/lobby/lobby_shell.tscn") as PackedScene
	var lobby := lobby_scene.instantiate()
	add_child_autofree(lobby)
	await get_tree().process_frame
	var coordinator := lobby.get_node("PracticeMatchCoordinator") as PracticeMatchCoordinator
	assert_not_null(coordinator)
	var prepared := coordinator.prepare_practice(
		SessionIntent.new(&"PRACTICE", &"EAST", &"TRASH_TALK", &"lin_yeche"),
		99,
		"coord-voice"
	)
	assert_true(prepared.get("ok", false))
	var driver: GameDriver = prepared["driver"]
	var vp: VoicePortModule = driver.mode_modules.voice_port
	assert_not_null(vp)
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	var table := coordinator.mount_playable_table()
	assert_not_null(table)
	# 走生产绑定入口
	var bc: PlayableBattleController = driver.bc_factory.call(
		99, 0, false, TileId.E, 0
	)
	table.bind_voice_from_battle(bc)
	await get_tree().process_frame
	assert_true(vp.press_ptt())
	assert_true(vp.is_ptt_pressed())
	coordinator.return_to_lobby()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(vp.is_ptt_pressed())
	assert_false(vp.is_capturing())
