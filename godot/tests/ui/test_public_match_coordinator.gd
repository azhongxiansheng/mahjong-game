extends GutTest

const LOBBY_SCENE := preload("res://ui/lobby/lobby_shell.tscn")


func test_lobby_mounts_public_match_coordinator_as_public_intent_consumer() -> void:
	var lobby := LOBBY_SCENE.instantiate() as LobbyShell
	add_child_autofree(lobby)
	await wait_process_frames(1)
	var coordinator := lobby.get_node_or_null("PublicMatchCoordinator")
	assert_not_null(coordinator)
	assert_true(coordinator is PublicMatchCoordinator)
	assert_true(lobby.session_intent_confirmed.is_connected(coordinator._on_session_intent))


func test_authority_ticket_states_map_to_stable_token_free_view() -> void:
	var coordinator := PublicMatchCoordinator.new()
	add_child_autofree(coordinator)
	coordinator.consume_ticket_for_test({
		"ticket_id": "ticket-secret-ish",
		"status": "waiting",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"queued_at": "q",
		"deadline_at": "d",
	})
	var waiting := coordinator.get_view()
	assert_eq(waiting.get("state"), "waiting")
	assert_true(waiting.get("can_cancel", false))
	assert_false(waiting.has("ticket_id"), "UI view 不需要 ticket id")

	coordinator.consume_ticket_for_test({
		"status": "assigned",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"worker": "ws://worker-private:9000",
		"room_id": "room-visible",
		"seat": 1,
		"room_token": "room-token-secret",
	})
	var matched := coordinator.get_view()
	assert_eq(matched.get("state"), "matched")
	assert_eq(matched.get("room_id"), "room-visible")
	assert_eq(matched.get("seat"), 1)
	assert_false(matched.has("worker"))
	assert_false(matched.has("room_token"))
	assert_false(matched.has("session_token"))


func test_connection_facts_drive_reconnecting_recovered_and_terminal_views() -> void:
	var coordinator := PublicMatchCoordinator.new()
	add_child_autofree(coordinator)
	coordinator.consume_connection_fact_for_test(&"reconnecting", "WS_CLOSED", "连接已断开")
	var reconnecting := coordinator.get_view()
	assert_eq(reconnecting.get("state"), "reconnecting")
	assert_true(reconnecting.get("can_retry", false))
	coordinator.consume_connection_fact_for_test(&"recovered")
	assert_eq(coordinator.get_view().get("state"), "recovered")
	coordinator.consume_connection_fact_for_test(&"terminal_error", "UNAUTHORIZED", "认证失败")
	var failed := coordinator.get_view()
	assert_eq(failed.get("state"), "terminal_error")
	assert_eq(failed.get("error_code"), "UNAUTHORIZED")
	assert_false(failed.get("can_retry", true))


func test_view_schema_is_stable_and_incomplete_assigned_never_becomes_matched() -> void:
	var coordinator := PublicMatchCoordinator.new()
	add_child_autofree(coordinator)
	var expected_keys := [
		"state", "round_kind", "game_mode", "queued_at", "deadline_at",
		"room_id", "seat", "error_code", "message", "can_cancel", "can_retry",
	]
	var seen_states: Array[String] = []
	coordinator.view_changed.connect(func(view: Dictionary): seen_states.append(str(view.get("state", ""))))
	coordinator.consume_ticket_for_test({
		"status": "assigned", "round_kind": "EAST", "game_mode": "STANDARD",
		"worker": "ws://127.0.0.1:9000", "room_id": "room-incomplete", "seat": 0,
		# 故意缺 room_token
	})
	var failed := coordinator.get_view()
	assert_eq(failed.get("state"), "terminal_error")
	assert_false(seen_states.has("matched"), "不完整 assigned 不得短暂发布 matched")
	assert_eq(failed.keys(), expected_keys)
	for secret_key in ["ticket_id", "session_token", "room_token", "worker", "voice_worker"]:
		assert_false(failed.has(secret_key))
