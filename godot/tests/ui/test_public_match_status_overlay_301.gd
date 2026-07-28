extends GutTest

const LOBBY_SCENE := preload("res://ui/lobby/lobby_shell.tscn")
const DESIGN_SIZE := Vector2(1600, 900)


func _spawn_lobby() -> LobbyShell:
	var host := Control.new()
	host.size = DESIGN_SIZE
	add_child_autofree(host)
	var shell := LOBBY_SCENE.instantiate() as LobbyShell
	host.add_child(shell)
	return shell


func _visible_copy(root: Node) -> String:
	var copy := ""
	for node in root.find_children("*", "", true, false):
		if node is Label and (node as Label).is_visible_in_tree():
			copy += (node as Label).text + "\n"
		elif node is BaseButton and (node as BaseButton).is_visible_in_tree():
			copy += (node as BaseButton).text + "\n"
	return copy


func _escape() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	return event


func test_real_coordinator_view_drives_one_token_free_status_overlay() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	var coordinator := shell.get_node("PublicMatchCoordinator") as PublicMatchCoordinator
	var overlay := shell.get_node_or_null("%PublicMatchStatusOverlay") as Control
	assert_not_null(overlay)
	if overlay == null:
		return
	assert_false(overlay.visible, "idle 不应遮住大厅")
	coordinator.consume_ticket_for_test({
		"ticket_id": "secret-ticket", "status": "waiting",
		"round_kind": "EAST", "game_mode": "STANDARD",
		"queued_at": "q", "deadline_at": "d",
	})
	await get_tree().process_frame
	assert_true(overlay.visible)
	var copy := _visible_copy(overlay)
	assert_true(copy.contains("等待匹配"))
	for secret in ["secret-ticket", "room_token", "session_token", "worker"]:
		assert_false(copy.contains(secret), "状态层不得泄露内部字段：%s" % secret)
	assert_eq(shell.find_children("PublicMatchStatusOverlay", "", true, false).size(), 1)


func test_waiting_cancel_button_calls_real_queue_cancel_path() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	var coordinator := shell.get_node("PublicMatchCoordinator") as PublicMatchCoordinator
	coordinator._queue._ticket_id = "ticket-real-action"
	coordinator._queue._session_token = "session-private"
	coordinator.consume_ticket_for_test({
		"ticket_id": "ticket-real-action", "status": "waiting",
		"round_kind": "EAST", "game_mode": "STANDARD",
	})
	await get_tree().process_frame
	var cancel := shell.get_node_or_null("%PublicMatchCancelButton") as Button
	assert_not_null(cancel)
	if cancel == null:
		return
	assert_false(cancel.disabled)
	cancel.pressed.emit()
	assert_eq(coordinator._queue._pending_kind, "cancel",
		"按钮必须进入现有 CasualQueueClient.cancel_ticket 真实路径")


func test_reconnecting_retry_button_calls_real_session_retry_path() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	var coordinator := shell.get_node("PublicMatchCoordinator") as PublicMatchCoordinator
	var session := PublicCasualNetworkSession.new()
	session.worker_url = "ws://127.0.0.1:9"
	session._recovering = true
	coordinator.add_child(session)
	coordinator._session = session
	coordinator.consume_connection_fact_for_test(&"reconnecting", "WS_CLOSED", "连接已断开")
	await get_tree().process_frame
	var retry := shell.get_node_or_null("%PublicMatchRetryButton") as Button
	assert_not_null(retry)
	if retry == null:
		return
	assert_false(retry.disabled)
	var old_peer := session._game_peer
	retry.pressed.emit()
	assert_ne(session._game_peer, old_peer,
		"按钮必须进入现有 PublicCasualNetworkSession.retry_reconnect 真实路径")


func test_terminal_close_only_hides_view_and_restores_match_focus() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	var coordinator := shell.get_node("PublicMatchCoordinator") as PublicMatchCoordinator
	var source := shell.get_node("%MatchButton") as Button
	source.grab_focus()
	coordinator.consume_connection_fact_for_test(&"terminal_error", "ROOM_FAILED", "房间不可用")
	await get_tree().process_frame
	var overlay := shell.get_node_or_null("%PublicMatchStatusOverlay") as Control
	assert_not_null(overlay)
	if overlay == null:
		return
	var close_button := shell.get_node_or_null("%PublicMatchCloseButton") as Button
	assert_true(overlay.visible)
	assert_not_null(close_button)
	if close_button == null:
		return
	close_button.pressed.emit()
	await get_tree().process_frame
	assert_false(overlay.visible)
	assert_eq(coordinator.get_view().get("state"), "terminal_error",
		"关闭可见错误层不得伪造或改写协调器状态")
	assert_same(get_viewport().gui_get_focus_owner(), source)


func test_recovered_is_view_driven_non_modal_and_escape_never_changes_state() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	var coordinator := shell.get_node("PublicMatchCoordinator") as PublicMatchCoordinator
	coordinator.consume_connection_fact_for_test(&"recovered")
	await get_tree().process_frame
	var overlay := shell.get_node_or_null("%PublicMatchStatusOverlay") as Control
	assert_not_null(overlay)
	var recovered := shell.get_node_or_null("%PublicMatchRecoveredNotice") as Control
	var modal := shell.get_node_or_null("%PublicMatchModal") as Control
	if overlay == null:
		return
	assert_true(overlay.visible)
	assert_not_null(recovered)
	assert_not_null(modal)
	if recovered == null or modal == null:
		return
	assert_true(recovered.visible)
	assert_eq(recovered.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_false(modal.visible, "recovered 不得保留阻断牌桌输入的 Modal")
	get_viewport().push_input(_escape())
	await get_tree().process_frame
	assert_eq(coordinator.get_view().get("state"), "recovered")


func test_waiting_and_reconnecting_escape_do_not_hide_or_trigger_actions() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	var coordinator := shell.get_node("PublicMatchCoordinator") as PublicMatchCoordinator
	coordinator.consume_ticket_for_test({
		"ticket_id": "t", "status": "waiting",
		"round_kind": "EAST", "game_mode": "STANDARD",
	})
	await get_tree().process_frame
	get_viewport().push_input(_escape())
	await get_tree().process_frame
	var overlay := shell.get_node_or_null("%PublicMatchStatusOverlay") as Control
	assert_not_null(overlay)
	if overlay == null:
		return
	assert_true(overlay.visible)
	assert_eq(coordinator.get_view().get("state"), "waiting")
	assert_eq(coordinator._queue._pending_kind, "")

	coordinator.consume_connection_fact_for_test(&"reconnecting", "WS_CLOSED", "断线")
	await get_tree().process_frame
	get_viewport().push_input(_escape())
	await get_tree().process_frame
	assert_true(overlay.visible)
	assert_eq(coordinator.get_view().get("state"), "reconnecting")
