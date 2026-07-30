extends Node

# #380：挂到 tools/capture_380_public_settlement.tscn 作为 main 运行（完整 Autoload）。
# 真实 LobbyShell → PublicMatchCoordinator → session.start → wire →
# settlement_view_changed / Node._process → PlayableTable 弹层。
# 禁止：synthetic host、自建 NBC fallback、私有 _sync_public_settlement_ui。

const CHARS := ["lin_yeche", "an_cheng", "bai_touli", "hua_ling"]
const NAMES := ["Alice", "Bob", "本席南家", "CPU"]
const LOBBY_SCENE := preload("res://ui/lobby/lobby_shell.tscn")
const OUT_DIR := "/tmp/mahjong-issue-380-grok-visual-round-8"
const WAIT_FRAMES := 180


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	await _shot(1600, 900, OUT_DIR + "/match-1600x900.png", true, false)
	await _shot(1600, 900, OUT_DIR + "/reconnect-match-1600x900.png", true, true)
	await _shot(1600, 900, OUT_DIR + "/hand-1600x900.png", false, false)
	await _shot(1280, 720, OUT_DIR + "/hand-1280x720.png", false, false)
	await _shot(1280, 720, OUT_DIR + "/match-1280x720.png", true, false)
	print("CAPTURE_380_DONE")
	get_tree().quit(0)


func _tile(tid: int, copy: int, red := false, hs := 0) -> Dictionary:
	return {
		"instance_id": hs * 136 + TileId.ALL.find(tid) * 4 + copy,
		"tile_id": tid, "is_red_dora": red, "owner_seat": copy,
	}


func _core(recip: int, scores: Array, hs := 0) -> Dictionary:
	var seats: Array = []
	for s in range(4):
		var conc: Array = []
		var cnt := 13
		if s == recip:
			conc = [_tile(TileId.W5, 0, true, hs), _tile(TileId.W5, 1, false, hs)]
			cnt = 2
		seats.append({
			"seat": s,
			"seat_wind": [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N][s],
			"score": int(scores[s]), "concealed_tiles": conc, "concealed_count": cnt,
			"last_drawn_tile_instance_id": -1, "river": [], "melds": [],
			"riichi_declared": false, "riichi_double": false, "riichi_discard_index": -1,
		})
	return {
		"recipient_seat": recip, "hand_seq": hs, "dealer_seat": 0,
		"current_seat": recip, "phase": "DRAW", "round_wind": TileId.E,
		"hand_number": hs + 1, "honba": 1, "riichi_sticks": 2,
		"live_wall_count": 70,
		"dora_indicators": [_tile(TileId.S1, 0, false, hs)],
		"seats": seats,
	}


func _feed(sess: PublicCasualNetworkSession, ne: NetworkedEvent) -> void:
	sess.ingest_authority_wire_for_test(JSON.stringify(ne.to_dict()))


func _fail(msg: String) -> void:
	push_error("CAPTURE_380_FAIL: " + msg)
	print("CAPTURE_380_FAIL ", msg)
	get_tree().quit(1)


func _wait_frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _find_hand_overlay(table: Node) -> Control:
	return table.find_child("PublicHandSettlementOverlay", true, false) as Control


func _find_match_panel(table: Node) -> Control:
	var p := table.find_child("PublicMatchSettlementPanel", true, false) as Control
	if p == null:
		p = table.find_child("MatchSettlementPanel", true, false) as Control
	return p


func _wait_until(pred: Callable, label: String) -> bool:
	for _i in range(WAIT_FRAMES):
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	print("CAPTURE_380_FAIL wait timeout: ", label)
	return false


func _shot(w: int, h: int, path: String, to_match: bool, reconnect_fact: bool) -> void:
	DisplayServer.window_set_size(Vector2i(w, h))
	await get_tree().process_frame

	var lobby := LOBBY_SCENE.instantiate() as LobbyShell
	if lobby == null:
		_fail("lobby_shell.tscn instantiate 失败")
		return
	lobby.name = "LobbyShellCapture"
	lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby.size = Vector2(w, h)
	add_child(lobby)
	await _wait_frames(2)

	var coordinator := lobby.get_node_or_null("PublicMatchCoordinator") as PublicMatchCoordinator
	if coordinator == null:
		_fail("LobbyShell 缺少真实 PublicMatchCoordinator")
		return
	var overlay := lobby.get_node_or_null("PublicMatchStatusOverlay") as PublicMatchStatusOverlay
	if overlay == null:
		_fail("LobbyShell 缺少真实 PublicMatchStatusOverlay")
		return
	if not coordinator.has_method("begin_network_from_assigned_for_test"):
		_fail("缺少 begin_network_from_assigned_for_test seam")
		return

	coordinator.set_last_public_intent_for_test(
		SessionIntent.new(&"PUBLIC_CASUAL", &"EAST", &"STANDARD", &"lin_yeche")
	)
	var room := "cap-%d-%d" % [w, Time.get_ticks_msec() % 100000]
	coordinator.begin_network_from_assigned_for_test({
		"status": "assigned", "round_kind": "EAST", "game_mode": "STANDARD",
		"worker": "ws://127.0.0.1:9", "room_id": room, "seat": 2,
		"room_token": "cap-tok", "session_id": "cap-guest",
	})
	await _wait_frames(3)

	var sess := coordinator.get_active_session()
	var table := coordinator.get_active_table()
	if sess == null or table == null:
		_fail("装配失败：session=%s table=%s（禁止 synthetic fallback）" % [sess, table])
		return
	# 必须来自真实 session.start；禁止本地 new/bind NBC
	if sess.nbc == null:
		_fail("session.start 后 NBC 为空，禁止截图工具合成 NBC")
		return

	var recip := 2
	var p := {
		"snapshot_server_seq": 1, "next_server_seq": 2, "seat_view": recip,
		"modules": [
			{
				"module_key": "core_table", "schema_version": 1,
				"payload": _core(recip, [25000, 25000, 25000, 25000]),
			},
			MatchingMetaSnapshotProvider.fixture_module(CHARS),
		],
	}
	var snap := NetworkedEvent.make(
		"ROOM_SNAPSHOT", 1, room, p, ProtocolViewCodec.compute_view_hash(p)
	)
	if snap == null:
		_fail("ROOM_SNAPSHOT fixture 无效")
		return
	_feed(sess, snap)
	var vh := snap.view_hash
	for s in range(4):
		var pj := NetworkedEvent.make("PLAYER_JOINED", 2 + s, room, {
			"seat": s, "participant_kind": "HUMAN" if s < 2 else "AI",
			"display_name": NAMES[s], "connected": true,
		}, vh)
		if pj == null:
			_fail("PLAYER_JOINED fixture 无效 seat=%d" % s)
			return
		_feed(sess, pj)
	var finals := [33000, 23000, 24000, 20000]
	var hand_scores: Array = finals if to_match else [24000, 23000, 33000, 20000]
	var hs := NetworkedEvent.make("HAND_SETTLED", 6, room, {
		"hand_seq": 0, "outcome": "RON", "winner_seats": [2], "loser_seat": 1,
		"score_deltas": [-1000, -2000, 8000, -5000],
		"scores": hand_scores,
		"dealer_seat": 0, "renchan": false, "honba": 1, "riichi_sticks": 0,
		"adjustments": [],
	}, vh)
	if hs == null:
		_fail("HAND_SETTLED fixture 无效")
		return
	_feed(sess, hs)
	if to_match:
		var ms := NetworkedEvent.make("MATCH_SETTLED", 7, room, {
			"round_kind": "EAST", "final_scores": finals, "seat_order": [0, 2, 1, 3],
		}, vh)
		if ms == null:
			_fail("MATCH_SETTLED fixture 无效")
			return
		_feed(sess, ms)

	# 仅依赖生产 settlement_view_changed + Node._process；不直调私有同步
	if to_match:
		var ok_match := await _wait_until(func():
			var phase_ok := str(sess.get_settlement_view().get("phase", "")) == "match_result"
			var state_ok := str(coordinator.get_view().get("state", "")) == "match_settled"
			var panel := _find_match_panel(table)
			return phase_ok and state_ok and panel != null and bool(panel.visible)
		, "MATCH panel visible + match_settled")
		if not ok_match:
			_fail("MATCH 等待超时 phase=%s state=%s panel=%s" % [
				sess.get_settlement_view().get("phase", ""),
				coordinator.get_view().get("state", ""),
				_find_match_panel(table),
			])
			return
		if reconnect_fact:
			sess.reconnecting.emit("WS_CLOSED", "断线")
			var ok_re := await _wait_until(func():
				var phase_ok := str(sess.get_settlement_view().get("phase", "")) == "match_result"
				var state_ok := str(coordinator.get_view().get("state", "")) == "match_settled"
				var panel := _find_match_panel(table)
				var panel_ok := panel != null and bool(panel.visible)
				var overlay_ok := overlay != null and not overlay.is_blocking()
				return phase_ok and state_ok and panel_ok and overlay_ok
			, "reconnect keeps match_settled + panel + overlay unblocked")
			if not ok_re:
				_fail("reconnect-MATCH 等待超时 state=%s blocking=%s" % [
					coordinator.get_view().get("state", ""),
					overlay.is_blocking() if overlay != null else "null",
				])
				return
	else:
		var ok_hand := await _wait_until(func():
			var phase_ok := str(sess.get_settlement_view().get("phase", "")) == "hand_result"
			var ov := _find_hand_overlay(table)
			return phase_ok and ov != null and bool(ov.visible)
		, "HAND overlay visible + hand_result")
		if not ok_hand:
			_fail("HAND 等待超时 phase=%s overlay=%s" % [
				sess.get_settlement_view().get("phase", ""),
				_find_hand_overlay(table),
			])
			return

	# 稳定一帧再截
	await _wait_frames(4)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_fail("空截图 " + path)
		return
	var err := img.save_png(path)
	if err != OK:
		_fail("save_png 失败 path=%s err=%s" % [path, error_string(err)])
		return
	var bytes := FileAccess.get_file_as_bytes(path).size()
	if bytes <= 0:
		_fail("截图 0 字节 " + path)
		return
	print(
		"saved ", path, " ", img.get_width(), "x", img.get_height(),
		" bytes=", bytes,
		" phase=", sess.get_settlement_view().get("phase", ""),
		" state=", coordinator.get_view().get("state", ""),
		" overlay_blocking=", overlay.is_blocking() if overlay != null else "null"
	)
	lobby.queue_free()
	await _wait_frames(2)
