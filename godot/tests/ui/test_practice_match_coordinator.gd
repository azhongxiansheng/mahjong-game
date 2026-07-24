extends GutTest

# E2-03（#233）+ E2-05（#235）：协调层启动、整场结算、再来一局与返回大厅。

const LOBBY_SCENE := preload("res://ui/lobby/lobby_shell.tscn")


func _spawn_lobby() -> LobbyShell:
	var lobby := LOBBY_SCENE.instantiate() as LobbyShell
	add_child_autofree(lobby)
	return lobby


func _practice_config(
	seed_value: int = 42,
	session_id: String = "coord-session",
	round_kind: StringName = &"EAST",
	mode: StringName = &"STANDARD"
) -> GameSessionConfig:
	var intent := SessionIntent.new(&"PRACTICE", round_kind, mode, &"lin_yeche")
	var converted := GameSessionConfig.from_intent(
		intent, seed_value, session_id, "e2-05-v1", {}
	)
	assert_true(converted.ok)
	return converted.config


func _completed_summary(config: GameSessionConfig, scores: Array = [32000, 28000, 22000, 18000]) -> Dictionary:
	return {
		"completed": true,
		"error": &"",
		"session_id": config.session_id,
		"round_kind": config.round_kind,
		"hand_count": 4,
		"final_scores": scores.duplicate(),
		"seat_order": MatchSettlement.build_seat_order(scores),
		"riichi_sticks": 0,
		"score_conserved": true,
	}


func test_lobby_mounts_independent_practice_coordinator() -> void:
	var lobby := _spawn_lobby()
	await get_tree().process_frame
	var coordinator := lobby.get_node_or_null("PracticeMatchCoordinator")
	assert_not_null(coordinator)
	assert_true(coordinator is PracticeMatchCoordinator)
	assert_false(
		(load("res://ui/lobby/lobby_shell.gd") as GDScript).source_code.contains("GameSessionConfig"),
		"正式配置与牌局启动不得回流到 LobbyShell"
	)


func test_all_four_practice_intents_prepare_same_playable_path() -> void:
	var lobby := _spawn_lobby()
	await get_tree().process_frame
	var coordinator := lobby.get_node("PracticeMatchCoordinator") as PracticeMatchCoordinator
	for round_kind in [&"EAST", &"HANCHAN"]:
		for mode in [&"STANDARD", &"TRASH_TALK"]:
			var prepared := coordinator.prepare_practice(
				SessionIntent.new(&"PRACTICE", round_kind, mode, &"lin_yeche"),
				77,
				"ui-%s-%s" % [String(round_kind), String(mode)]
			)
			assert_true(prepared.get("ok", false), str(prepared))
			assert_true(prepared.get("driver") is GameDriver)
			assert_true(prepared.get("config") is GameSessionConfig)
			assert_eq(prepared.get("driver").total_hands, 4 if round_kind == &"EAST" else 8)


func test_public_intent_is_not_started_locally() -> void:
	var lobby := _spawn_lobby()
	await get_tree().process_frame
	var coordinator := lobby.get_node("PracticeMatchCoordinator") as PracticeMatchCoordinator
	var prepared := coordinator.prepare_practice(
		SessionIntent.new(&"PUBLIC_CASUAL", &"EAST", &"STANDARD"), 1, "public"
	)
	assert_false(prepared.get("ok", true))
	assert_eq(prepared.get("error"), &"PUBLIC_NOT_LOCAL")


func test_coordinator_mounts_existing_playable_table_as_fullscreen_overlay() -> void:
	var lobby := _spawn_lobby()
	await get_tree().process_frame
	var coordinator := lobby.get_node("PracticeMatchCoordinator") as PracticeMatchCoordinator
	var table := coordinator.mount_playable_table()
	assert_not_null(table)
	assert_true(table is PlayableTable)
	assert_eq(table.get_parent(), lobby)
	assert_eq(table.anchor_right, 1.0)
	assert_eq(table.anchor_bottom, 1.0)
	assert_eq(coordinator.mount_playable_table(), table, "整场只复用一个牌桌覆盖层")


func test_present_settlement_shows_panel_on_table() -> void:
	var lobby := _spawn_lobby()
	await get_tree().process_frame
	var coordinator := lobby.get_node("PracticeMatchCoordinator") as PracticeMatchCoordinator
	var config := _practice_config()
	var driver := PracticeSessionLauncher.new().launch(config)
	assert_not_null(driver)
	var summary := _completed_summary(config, [24000, 25000, 26000, 25000])
	coordinator.present_settlement(summary, config, driver)
	await get_tree().process_frame
	await get_tree().process_frame

	var table := coordinator.get_active_table()
	assert_not_null(table)
	var panel := table.find_child("MatchSettlementPanel", true, false)
	assert_not_null(panel, "整场结算必须挂在现有牌桌覆盖层上")
	var title := panel.find_child("TitleLabel", true, false) as Label
	assert_not_null(title)
	assert_eq(title.text, "对局结束")
	var rows_host := panel.find_child("RankRows", true, false)
	assert_not_null(rows_host)
	assert_eq(rows_host.get_child_count(), 4)
	var first_row := rows_host.get_child(0) as Label
	assert_true(first_row.text.contains("AI 2"))
	assert_true(first_row.text.contains("26000"))
	assert_true(coordinator.is_busy())


func test_rebuild_for_rematch_new_identity_and_fresh_runtime() -> void:
	var lobby := _spawn_lobby()
	await get_tree().process_frame
	var coordinator := lobby.get_node("PracticeMatchCoordinator") as PracticeMatchCoordinator
	var config := _practice_config(11, "old-sid", &"HANCHAN", &"TRASH_TALK")
	var driver := PracticeSessionLauncher.new().launch(config)
	assert_not_null(driver)
	assert_not_null(driver.mode_modules)
	assert_not_null(driver.mode_modules.voice_port)
	coordinator.present_settlement(_completed_summary(config), config, driver)
	await get_tree().process_frame

	var old_table := coordinator.get_active_table()
	var old_driver := coordinator.get_active_driver()
	var old_modules := old_driver.mode_modules
	var rebuilt: Dictionary = coordinator.rebuild_for_rematch(1001, "rematch-1001")
	assert_true(rebuilt.get("ok", false), str(rebuilt))
	var new_config: GameSessionConfig = rebuilt["config"]
	var new_driver: GameDriver = rebuilt["driver"]
	var new_table: PlayableTable = rebuilt["table"]
	# queue_free 在帧末真正释放
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(new_config.seed, 1001)
	assert_eq(new_config.session_id, "rematch-1001")
	assert_eq(new_config.room_kind, config.room_kind)
	assert_eq(new_config.round_kind, config.round_kind)
	assert_eq(new_config.game_mode, config.game_mode)
	assert_eq(new_config.participants, config.participants)
	assert_eq(new_config.character_ids, config.character_ids)
	assert_eq(new_config.rule_version, config.rule_version)
	assert_ne(new_config.session_id, config.session_id)
	assert_ne(new_config.seed, config.seed)

	assert_true(new_driver != old_driver, "再来一局不得复用旧 GameDriver")
	assert_true(new_driver.mode_modules != old_modules, "再来一局不得复用旧模式模块")
	assert_false(is_instance_valid(old_table), "再来一局必须释放旧牌桌运行态")
	assert_not_null(new_table)
	assert_true(is_instance_valid(new_table))
	assert_eq(coordinator.get_active_table(), new_table)
	assert_true(
		new_table.find_child("MatchSettlementPanel", true, false) == null,
		"新局不应残留旧结算面板"
	)


func test_return_to_lobby_releases_runtime_and_restores_audio() -> void:
	var lobby := _spawn_lobby()
	await get_tree().process_frame
	var coordinator := lobby.get_node("PracticeMatchCoordinator") as PracticeMatchCoordinator
	var config := _practice_config(3, "ret-sid", &"EAST", &"TRASH_TALK")
	var driver := PracticeSessionLauncher.new().launch(config)
	coordinator.present_settlement(_completed_summary(config), config, driver)
	await get_tree().process_frame
	var old_table := coordinator.get_active_table()
	assert_not_null(old_table)

	var am = get_node_or_null("/root/AudioManager")
	assert_not_null(am)
	# 先播一个非大厅流，返回后应恢复大厅 BGM 路径
	if am.has_method("play_bgm"):
		am.play_bgm("res://assets/sfx/game_begin.wav")
	if am.has_method("play"):
		am.play("game_begin")

	coordinator.return_to_lobby()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(is_instance_valid(old_table), "返回大厅必须销毁牌桌")
	assert_null(coordinator.get_active_table())
	assert_null(coordinator.get_active_driver())
	assert_null(coordinator.get_active_config())
	assert_false(coordinator.is_busy())

	# 可再次 prepare
	var prepared := coordinator.prepare_practice(
		SessionIntent.new(&"PRACTICE", &"EAST", &"STANDARD", &"lin_yeche"),
		5,
		"after-return"
	)
	assert_true(prepared.get("ok", false))

	if am != null and am.get("_bgm_player") != null:
		var bgm_player = am._bgm_player
		if bgm_player != null and bgm_player.stream != null:
			assert_eq(
				String(bgm_player.stream.resource_path),
				LobbyShell.LOBBY_BGM_PATH,
				"返回大厅应恢复大厅 BGM"
			)


func test_return_lobby_button_releases_runtime_without_locked_free() -> void:
	# P1：必须从真实 Button.pressed 进入协调器，禁止只调 return_to_lobby()。
	# 旧实现在信号栈内 free 锁定的 MatchSettlementPanel → free 失败、泄漏、未释放。
	var lobby := _spawn_lobby()
	await get_tree().process_frame
	var coordinator := lobby.get_node("PracticeMatchCoordinator") as PracticeMatchCoordinator
	var config := _practice_config(21, "btn-return", &"EAST", &"TRASH_TALK")
	var driver := PracticeSessionLauncher.new().launch(config)
	assert_not_null(driver)
	assert_not_null(driver.mode_modules)
	assert_not_null(driver.mode_modules.voice_port)
	coordinator.present_settlement(_completed_summary(config), config, driver)
	await get_tree().process_frame
	await get_tree().process_frame

	var old_table := coordinator.get_active_table()
	assert_not_null(old_table)
	var panel := old_table.find_child("MatchSettlementPanel", true, false) as MatchSettlementPanel
	assert_not_null(panel)
	var return_btn := panel.find_child("ReturnLobbyButton", true, false) as Button
	assert_not_null(return_btn)

	return_btn.pressed.emit()
	# deferred + queue_free 需要 idle 帧
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(is_instance_valid(panel), "按钮返回后结算面板必须真正释放（非锁定 free 失败）")
	assert_false(is_instance_valid(old_table), "按钮返回后旧牌桌必须释放")
	assert_null(coordinator.get_active_table())
	assert_null(coordinator.get_active_driver())
	assert_null(coordinator.get_active_config())
	assert_false(coordinator.is_busy(), "返回后协调器应 IDLE")


func test_rematch_button_rebuilds_without_locked_free() -> void:
	# P1：真实「再来一局」按钮路径不得在信号栈内同步 free 面板。
	var lobby := _spawn_lobby()
	await get_tree().process_frame
	var coordinator := lobby.get_node("PracticeMatchCoordinator") as PracticeMatchCoordinator
	var config := _practice_config(22, "btn-rematch", &"HANCHAN", &"STANDARD")
	var driver := PracticeSessionLauncher.new().launch(config)
	assert_not_null(driver)
	coordinator.present_settlement(_completed_summary(config), config, driver)
	await get_tree().process_frame
	await get_tree().process_frame

	var old_table := coordinator.get_active_table()
	var old_driver := coordinator.get_active_driver()
	assert_not_null(old_table)
	assert_not_null(old_driver)
	var panel := old_table.find_child("MatchSettlementPanel", true, false) as MatchSettlementPanel
	assert_not_null(panel)
	var rematch_btn := panel.find_child("RematchButton", true, false) as Button
	assert_not_null(rematch_btn)

	rematch_btn.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	assert_false(is_instance_valid(panel), "再来一局后旧结算面板必须释放")
	assert_false(is_instance_valid(old_table), "再来一局后旧牌桌必须释放")
	var new_table := coordinator.get_active_table()
	var new_driver := coordinator.get_active_driver()
	var new_config := coordinator.get_active_config()
	assert_not_null(new_table, "再来一局后应挂载新牌桌")
	assert_not_null(new_driver)
	assert_not_null(new_config)
	assert_true(new_table != old_table)
	assert_true(new_driver != old_driver)
	assert_ne(new_config.session_id, config.session_id)
	assert_ne(new_config.seed, config.seed)
	assert_eq(new_config.round_kind, config.round_kind)
	assert_eq(new_config.game_mode, config.game_mode)
	assert_true(
		new_table.find_child("MatchSettlementPanel", true, false) == null,
		"新局开局时不应残留旧结算面板"
	)

	# 打断可能已启动的整场跑局，避免 GUT 卡在完整 AI 对战
	coordinator.return_to_lobby()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(coordinator.is_busy())


func test_coordinator_source_has_no_run_reward_paths() -> void:
	var src := String((load("res://ui/lobby/practice_match_coordinator.gd") as GDScript).source_code)
	for forbidden in ["RunState", "NodeResult", "BattleNodeRunner", "run_flow", "hp_delta"]:
		assert_false(src.contains(forbidden), "协调层不得接入 %s" % forbidden)
