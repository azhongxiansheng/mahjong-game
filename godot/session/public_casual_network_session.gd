class_name PublicCasualNetworkSession
extends Node

# E4-02（#244 round-3）：公共休闲场非视觉网络 runtime seam。
# 消费 CP assigned（worker / voice_worker / room / seat / token / game_mode / session）。
# 绑定调用方提供的 ModeModuleBundle.voice_port（仅 TRASH_TALK）；生产不强制 fixture。
# 协议：JOIN → READY → 消费业务事件；语音独立 WS + AuthoritySeqBridge。
# #323：由 PublicMatchCoordinator 在 CP assigned 后接入生产大厅与牌桌。
# 网络端到端未验证。

const JsonTransportDecoder := preload("res://protocol/json_transport_decoder.gd")

signal game_joined()
signal game_ready_sent()
signal voice_joined()
signal room_started_hint()
signal session_failed(code: String, message: String)
signal reconnecting(code: String, message: String)
signal recovered()
signal terminal_error(code: String, message: String)
signal authority_ptt_end(msg: Dictionary)
## #247：服务端字幕 → 调用方可接 PlayableTable.inject_caption_display
signal transcript_caption(msg: Dictionary)

var game_mode: String = ""
var room_id: String = ""
var seat: int = -1
var session_id: String = ""
var worker_url: String = ""
var voice_worker_url: String = ""
var room_token: String = ""

var nbc: NetworkedBattleController = null
var voice_port: VoicePortModule = null
var seq_bridge: AuthoritySeqBridge = AuthoritySeqBridge.new()

var _game_peer: WebSocketPeer = WebSocketPeer.new()
var _voice_client: VoiceRelayClient = null
var _bundle: ModeModuleBundle = null
var _game_joined: bool = false
var _game_join_sent: bool = false
var _game_ready_sent: bool = false
var _want_open: bool = false
var _released: bool = false
var _owns_voice_port: bool = false
var _recovering: bool = false
var _closed_notified: bool = false
var _has_committed_snapshot: bool = false
var _terminal_notified: bool = false


## E5-06：可选只读 UI 绑定。不改 schema/权威；展示侧消费 nbc committed journal。
## 生产大厅 bootstrap 未接通前可由测试/未来接线调用。
func bind_playable_table(table: Node) -> void:
	if table == null:
		return
	if table.has_method("bind_public_casual_session"):
		table.bind_public_casual_session(self)


## assigned：CP GET ticket 成功体；p_session_id 为 guest/session（token 绑定）。
func configure_from_assigned(assigned: Dictionary, p_session_id: String = "") -> bool:
	if assigned.is_empty():
		return false
	room_id = str(assigned.get("room_id", ""))
	worker_url = str(assigned.get("worker", ""))
	voice_worker_url = str(assigned.get("voice_worker", ""))
	room_token = str(assigned.get("room_token", ""))
	game_mode = str(assigned.get("game_mode", ""))
	if assigned.has("seat"):
		seat = int(assigned["seat"])
	session_id = p_session_id if not p_session_id.is_empty() else str(assigned.get("session_id", ""))
	if room_id.is_empty() or worker_url.is_empty() or room_token.is_empty():
		return false
	if seat < 0 or seat > 3:
		return false
	if session_id.is_empty():
		return false
	if game_mode != "STANDARD" and game_mode != "TRASH_TALK":
		return false
	# TRASH_TALK 必须显式 voice_worker（不得猜端口）
	if game_mode == "TRASH_TALK" and voice_worker_url.is_empty():
		return false
	# STANDARD 不得携带 voice_worker 能力（硬隔离）
	if game_mode == "STANDARD" and not voice_worker_url.is_empty():
		voice_worker_url = ""
	return true


## 绑定既有 ModeModuleBundle；必须与已配置 game_mode 一致。
## STANDARD → 仅 standard bundle 且无 voice；TRASH_TALK → 仅 trash bundle 且复用真实 voice_port。
func bind_mode_modules(bundle: ModeModuleBundle) -> bool:
	if bundle == null:
		return false
	if game_mode.is_empty():
		return false
	if game_mode == "STANDARD":
		if not bundle.is_standard():
			return false
		if bundle.voice_port != null:
			return false
		_bundle = bundle
		voice_port = null
		_owns_voice_port = false
		return true
	if game_mode == "TRASH_TALK":
		if not bundle.is_trash_talk():
			return false
		if bundle.voice_port == null:
			return false
		_bundle = bundle
		voice_port = bundle.voice_port
		_owns_voice_port = false
		return true
	return false


## 测试可注入 VoicePort（可不经 bundle）；生产应走 bind_mode_modules。
func bind_voice_port_for_test(port: VoicePortModule) -> void:
	voice_port = port
	_owns_voice_port = false


func start() -> Error:
	if _released:
		return ERR_INVALID_PARAMETER
	if room_id.is_empty() or worker_url.is_empty() or room_token.is_empty():
		return ERR_INVALID_PARAMETER
	if game_mode == "TRASH_TALK" and voice_worker_url.is_empty():
		return ERR_INVALID_PARAMETER
	if game_mode == "TRASH_TALK" and voice_port == null:
		return ERR_INVALID_PARAMETER

	_want_open = true
	_recovering = false
	_closed_notified = false
	_has_committed_snapshot = false
	_terminal_notified = false
	nbc = NetworkedBattleController.new(room_id, seat)
	if game_mode == "TRASH_TALK":
		nbc.configure_snapshot_registry_for_mode("TRASH_TALK")
		voice_port.bind_public_identity(room_id, session_id, seat)
	seq_bridge.bind_networked_controller(nbc)

	_game_peer = WebSocketPeer.new()
	var err: Error = _game_peer.connect_to_url(worker_url)
	if err != OK:
		_cleanup_partial()
		return err

	if game_mode == "TRASH_TALK":
		var verr: Error = _start_voice()
		if verr != OK:
			_cleanup_partial()
			return verr
	return OK


func _start_voice() -> Error:
	_voice_client = VoiceRelayClient.new()
	add_child(_voice_client)
	_voice_client.bind_voice_port(voice_port)
	_voice_client.bind_authority_seq_bridge(seq_bridge)
	if not _voice_client.authority_ptt_end.is_connected(_on_voice_ptt_end):
		_voice_client.authority_ptt_end.connect(_on_voice_ptt_end)
	if not _voice_client.transcript_caption.is_connected(_on_voice_transcript_caption):
		_voice_client.transcript_caption.connect(_on_voice_transcript_caption)
	if not _voice_client.connected.is_connected(_on_voice_connected):
		_voice_client.connected.connect(_on_voice_connected)
	if not _voice_client.error_received.is_connected(_on_voice_error):
		_voice_client.error_received.connect(_on_voice_error)
	var cerr: Error = _voice_client.connect_voice(
		voice_worker_url, room_id, seat, session_id, room_token
	)
	return cerr


func poll() -> void:
	if _released:
		return
	_poll_game()
	if _voice_client != null:
		_voice_client.poll()
	seq_bridge.tick()


func _process(_delta: float) -> void:
	poll()


func _poll_game() -> void:
	if _game_peer == null:
		return
	_game_peer.poll()
	var st: int = _game_peer.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _game_join_sent and _want_open:
			_game_peer.send_text(JSON.stringify({
				"protocol_version": 1,
				"kind": "JOIN",
				"room_id": room_id,
				"seat": seat,
				"room_token": room_token,
			}))
			_game_join_sent = true
		elif _game_join_sent and not _game_ready_sent and _want_open:
			# Worker JOIN 成功无业务 ACK；下一 poll 发 READY 推进权威 start
			_send_ready_if_needed()
		while _game_peer.get_available_packet_count() > 0:
			var pkt: PackedByteArray = _game_peer.get_packet()
			if not _game_peer.was_string_packet():
				continue
			_on_game_text(pkt.get_string_from_utf8())
	elif st == WebSocketPeer.STATE_CLOSED:
		if _want_open and not _released and not _closed_notified:
			_closed_notified = true
			_recovering = true
			reconnecting.emit("WS_CLOSED", "game ws closed")


func _on_game_text(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	var kind: String = str(d.get("kind", ""))
	if kind == "ERROR":
		if not _game_joined:
			_emit_terminal(str(d.get("code", "ERROR")), str(d.get("message", "")))
		return
	if kind == "COMMAND_RESULT" or str(d.get("status", "")) in ["ACCEPTED", "REJECTED"]:
		return
	# JOIN 成功：尚无业务事件时也允许发 READY（房间未开局）
	if not _game_joined and _game_join_sent:
		# 任意非 ERROR 回包或超时路径：首包后发 READY
		pass
	# NetworkedEvent
	if d.has("server_seq") and d.has("view_hash") and d.has("payload"):
		var event: NetworkedEvent = JsonTransportDecoder.decode_event(text)
		if event == null:
			_emit_terminal("BAD_EVENT", "authority event rejected")
			return
		if not _game_joined:
			_game_joined = true
			game_joined.emit()
		var ingested: Dictionary = seq_bridge.on_game_networked_event(event)
		if not bool(ingested.get("ok", false)):
			var ingest_code := str(ingested.get("error", ""))
			if ingest_code.is_empty():
				ingest_code = str(ingested.get("reason", "EVENT_REJECTED"))
			_emit_terminal(ingest_code, "authority event rejected")
			return
		if str(d.get("kind", "")) == "ROOM_SNAPSHOT":
			_has_committed_snapshot = true
			room_started_hint.emit()
			if _recovering:
				_recovering = false
				recovered.emit()
		return


func retry_reconnect() -> Error:
	if _released or not _recovering or worker_url.is_empty():
		return ERR_INVALID_PARAMETER
	if _game_peer != null and _game_peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		return ERR_BUSY
	_game_peer = WebSocketPeer.new()
	_game_joined = false
	_game_join_sent = false
	_game_ready_sent = false
	_closed_notified = false
	_terminal_notified = false
	var err := _game_peer.connect_to_url(worker_url)
	if err != OK:
		_closed_notified = true
		_emit_terminal("RECONNECT_FAILED", error_string(err))
	return err


func has_committed_snapshot() -> bool:
	return _has_committed_snapshot


func close_connection_for_test() -> void:
	if _game_peer != null:
		_game_peer.close()


func _emit_terminal(code: String, message: String) -> void:
	if _terminal_notified:
		return
	_terminal_notified = true
	_want_open = false
	session_failed.emit(code, message)
	terminal_error.emit(code, message)


func _send_ready_if_needed() -> void:
	if _game_ready_sent or not _want_open:
		return
	if _game_peer == null or _game_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_game_peer.send_text(JSON.stringify({
		"protocol_version": 1,
		"kind": "READY",
		"room_id": room_id,
		"seat": seat,
	}))
	_game_ready_sent = true
	game_ready_sent.emit()


## 若 JOIN 后长时间无事件（未开局），仍发送 READY 以推进权威 start。
func ensure_ready_sent() -> void:
	if _game_join_sent and not _game_ready_sent:
		_send_ready_if_needed()


func _on_voice_connected() -> void:
	voice_joined.emit()


func _on_voice_error(msg: Dictionary) -> void:
	if not is_voice_joined():
		session_failed.emit(str(msg.get("code", "ERROR")), str(msg.get("message", "voice error")))


func _on_voice_ptt_end(msg: Dictionary) -> void:
	authority_ptt_end.emit(msg)


func _on_voice_transcript_caption(msg: Dictionary) -> void:
	# 仅转发；展示侧用 inject_caption_display，不触达 RewardWindow
	transcript_caption.emit(msg.duplicate(true))


func is_voice_enabled() -> bool:
	return _voice_client != null


func is_voice_joined() -> bool:
	return _voice_client != null and _voice_client.is_joined()


func is_game_ready_sent() -> bool:
	return _game_ready_sent


func _cleanup_partial() -> void:
	if _voice_client != null:
		_voice_client.disconnect_voice()
		if is_instance_valid(_voice_client):
			_voice_client.queue_free()
		_voice_client = null
	if _game_peer != null:
		_game_peer.close()
	seq_bridge.clear()
	nbc = null
	_want_open = false


func release() -> void:
	if _released:
		return
	_released = true
	_want_open = false
	if _voice_client != null:
		_voice_client.disconnect_voice()
		if is_instance_valid(_voice_client):
			_voice_client.queue_free()
		_voice_client = null
	if voice_port != null:
		voice_port.release_all()
		if _owns_voice_port:
			voice_port = null
		# 绑定调用方 port 时不销毁对象，仅清空引用
		voice_port = null
	if _game_peer != null:
		_game_peer.close()
		_game_peer = null
	seq_bridge.clear()
	nbc = null
	_bundle = null
	_game_joined = false
	_game_join_sent = false
	_game_ready_sent = false
	_recovering = false
	_closed_notified = false
	_has_committed_snapshot = false
	_terminal_notified = false


func _exit_tree() -> void:
	release()
