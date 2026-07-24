extends GutTest

# E2-03（#233）：大厅壳通过独立协调层接入练习赛，保持 LobbyShell 纯 UI 边界。

const LOBBY_SCENE := preload("res://ui/lobby/lobby_shell.tscn")


func _spawn_lobby() -> LobbyShell:
	var lobby := LOBBY_SCENE.instantiate() as LobbyShell
	add_child_autofree(lobby)
	return lobby


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
