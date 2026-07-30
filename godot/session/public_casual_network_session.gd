class_name PublicCasualNetworkSession
extends Node

# E4-02（#244 round-3）：公共休闲场非视觉网络 runtime seam。
# 消费 CP assigned（worker / voice_worker / room / seat / token / game_mode / session）。
# 绑定调用方提供的 ModeModuleBundle.voice_port（仅 TRASH_TALK）；生产不强制 fixture。
# 协议：JOIN → READY → 消费业务事件；语音独立 WS + AuthoritySeqBridge。
# #323：由 PublicMatchCoordinator 在 CP assigned 后接入生产大厅与牌桌。
# #378：submit_action(Action) 为公共客户端唯一命令出口；ACCEPTED/ERROR 结果信号。
# #380：只读消费 committed HAND_SETTLED / MATCH_SETTLED → get_settlement_view。
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
## #378：Worker CommandResult ACCEPTED（五键）；不乐观改牌。
signal command_accepted(result: CommandResult)
## #378：Worker ERROR / REJECTED 控制结果；恢复权威 decision。
signal command_rejected(code: String, command_id: String, message: String)
## #378：统一结果旁路（status=ACCEPTED|REJECTED）。
signal command_result_received(status: String, code: String, command_id: String)
## #378：pending 因 decision 不匹配 / 代际失效被丢弃。
signal command_pending_dropped(reason: String)
## #380：committed 结算投影变更（只读；无 READY / 本地计分副作用）。
signal settlement_view_changed(view: Dictionary)

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
## #377：权威 resync 只发一次 reconnecting，直到合法 ROOM_SNAPSHOT 恢复。
var _resync_reconnect_notified: bool = false
## #378：连接代际；重连递增；旧代际不得提交。
var _connection_generation: int = 0
## #378：client_seq 单调有界（1..MAX_SAFE_INT）。
var _client_seq: int = 0
## #378：至多一条 in-flight 业务命令（冻结 Action 副本 + 发送时代际）。
var _pending_action: Action = null
var _pending_generation: int = -1
var _pending_awaiting_result: bool = false
var _pending_retry_on_recover: bool = false
## #378 R4：ACCEPTED 后至 matching committed 事件/seq 到达前，禁止第二条命令。
var _awaiting_committed: bool = false
var _accepted_commit_seq: int = 0
## #380：只读结算投影（仅 NBC committed journal；pending 不入）。
var _settlement_phase: String = "idle"
var _settlement_hand: Dictionary = {}
var _settlement_match: Dictionary = {}
var _roster_names: Dictionary = {}  # seat(int) -> display_name
var _character_ids: Array = []
var _settlement_journal_cursor: int = 0
var _match_latched: bool = false
var _last_settlement_sig: String = ""
## #380：当前 committed 局手序号（来自 SNAP core_table.hand_seq）
var _ledger_hand_seq: int = -1
## #380：最近一次已投影 HAND 的 hand_seq（防旧局以更高 server_seq 覆盖）
var _last_settled_hand_seq: int = -1
## #380：结算连续性 resync 中，禁止同帧 recovered
var _settlement_resync_active: bool = false


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
	_resync_reconnect_notified = false
	_connection_generation = 1
	_clear_pending("start")
	_reset_settlement_projection()
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
	# #377：gap timeout/overflow 强制 resync 时通知 UI，不得忽略 tick 返回
	var tick_result: Dictionary = seq_bridge.tick()
	_observe_bridge_result(tick_result)


func _process(_delta: float) -> void:
	poll()


## 测试：注入权威 wire JSON（真实 _on_game_text 入口，不直连 NBC）。
func ingest_authority_wire_for_test(text: String) -> void:
	_on_game_text(text)


## #378：公共客户端唯一 Action 命令出口。成功发送后 pending 直到 ACCEPTED/ERROR。
## 仅在已 JOIN 且非重连恢复窗口时可提交；不得仅凭 join_sent 放行。
func submit_action(action: Action) -> Error:
	if _released or action == null:
		return ERR_INVALID_PARAMETER
	if _pending_awaiting_result or _pending_action != null:
		return ERR_BUSY
	if _pending_retry_on_recover:
		return ERR_BUSY
	if _awaiting_committed:
		return ERR_BUSY
	if _recovering:
		return ERR_CONNECTION_ERROR
	if action.room_id != room_id or int(action.seat) != seat:
		return ERR_INVALID_PARAMETER
	if _game_peer == null or _game_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_CONNECTION_ERROR
	# #378 P1：必须已完成权威 JOIN；重连后亦须等 game_joined
	if not _game_joined:
		return ERR_CONNECTION_ERROR
	# 冻结发送快照（只读 Action）
	var frozen: Action = Action.from_dict(action.to_dict())
	if frozen == null:
		return ERR_INVALID_PARAMETER
	var payload_text := JSON.stringify(frozen.to_dict())
	var err: Error = _game_peer.send_text(payload_text)
	if err != OK:
		return err
	_pending_action = frozen
	_pending_generation = _connection_generation
	_pending_awaiting_result = true
	_pending_retry_on_recover = false
	_awaiting_committed = false
	_accepted_commit_seq = 0
	return OK


func is_command_pending() -> bool:
	return _pending_action != null


## #378 R4：ACCEPTED 后等待 matching committed（CR.server_seq 入账）期间仍不可新提交。
func is_awaiting_authority_commit() -> bool:
	return _awaiting_committed


## #378：重连后等待新 TURN/CLAIM 匹配中（尚不可新提交）。
func is_awaiting_pending_retry() -> bool:
	return _pending_retry_on_recover and _pending_action != null


func get_pending_command_id() -> String:
	if _pending_action == null:
		return ""
	return _pending_action.command_id


func get_pending_action() -> Action:
	if _pending_action == null:
		return null
	return Action.from_dict(_pending_action.to_dict())


func get_connection_generation() -> int:
	return _connection_generation


## 分配单调 client_seq（1..MAX_SAFE_INT）；耗尽返回 -1。
func allocate_client_seq() -> int:
	if _client_seq >= ProtocolConstants.MAX_SAFE_INT:
		return -1
	_client_seq += 1
	return _client_seq


## 分配 canonical lowercase UUID v4 command_id。
func allocate_command_id() -> String:
	return _new_canonical_v4()


func _new_canonical_v4() -> String:
	var c := Crypto.new()
	var b: PackedByteArray = c.generate_random_bytes(16)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % [
		b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
		b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15],
	]


func _clear_pending(reason: String) -> void:
	var had := _pending_action != null
	_pending_action = null
	_pending_generation = -1
	_pending_awaiting_result = false
	_pending_retry_on_recover = false
	_awaiting_committed = false
	_accepted_commit_seq = 0
	if had and not reason.is_empty() and reason != "result" and reason != "start" \
			and reason != "release":
		command_pending_dropped.emit(reason)


func _try_clear_awaiting_committed() -> void:
	if not _awaiting_committed or nbc == null:
		return
	if int(nbc.current_seq()) >= _accepted_commit_seq and _accepted_commit_seq > 0:
		_awaiting_committed = false
		_accepted_commit_seq = 0


func _observe_bridge_result(result: Dictionary) -> void:
	if result.is_empty():
		return
	if bool(result.get("resync", false)):
		_emit_authority_resync(str(result.get("reason", "RESYNC_REQUIRED")))
		return
	_try_clear_awaiting_committed()
	if nbc != null and nbc.resync_required() and not bool(result.get("ok", true)):
		_emit_authority_resync(str(result.get("reason", "RESYNC_REQUIRED")))


func _emit_authority_resync(code: String) -> void:
	if _released or _terminal_notified:
		return
	if _resync_reconnect_notified:
		return
	_resync_reconnect_notified = true
	_recovering = true
	# #377 P1：权威 resync 时关闭旧 game peer，使「重新连接」可发起新连接；
	# 并抑制 poll 在 CLOSED 时二次 emit WS_CLOSED reconnecting。
	if _game_peer != null:
		var st: int = _game_peer.get_ready_state()
		if st != WebSocketPeer.STATE_CLOSED:
			_game_peer.close()
		_closed_notified = true
	var msg := "authority resync required"
	var c := code if not code.is_empty() else "RESYNC_REQUIRED"
	reconnecting.emit(c, msg)


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
			# #378：断线时若仍 awaiting，标记待重连匹配后重试；否则丢弃
			if _pending_action != null and _pending_awaiting_result:
				_pending_retry_on_recover = true
				_pending_awaiting_result = false
			elif _pending_action != null and not _pending_retry_on_recover:
				_clear_pending("ws_closed")
			reconnecting.emit("WS_CLOSED", "game ws closed")


func _on_game_text(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	var kind: String = str(d.get("kind", ""))
	if kind == "ERROR":
		_handle_control_error(d)
		return
	# #378：CommandResult 五键（无 kind）；不得把带 view_hash 的业务事件误判为 CR
	if kind == "COMMAND_RESULT" \
			or (
				not d.has("view_hash")
				and not d.has("kind")
				and str(d.get("status", "")) in ["ACCEPTED", "REJECTED"]
				and d.has("command_id")
				and d.has("error_code")
			):
		_handle_command_result_wire(text, d)
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
		# #380：HAND→下一局 SNAP 连续性 preflight —— 错误起分不得进入 NBC committed
		if str(event.kind) == "ROOM_SNAPSHOT":
			var pre: Dictionary = _settlement_preflight_room_snapshot(event)
			if not bool(pre.get("ok", true)):
				var pre_reason := str(pre.get("reason", "SETTLEMENT_SCORE_MISMATCH"))
				# 终场锁存后任意迟到 SNAP：静默丢弃，不入 seq_bridge/NBC、不 resync
				if pre_reason == "MATCH_LATCHED_SNAPSHOT" or bool(pre.get("discard_only", false)):
					return
				_reject_settlement_snapshot(pre_reason)
				return
		var ingested: Dictionary = seq_bridge.on_game_networked_event(event)
		_observe_bridge_result(ingested)
		if not bool(ingested.get("ok", false)):
			# #377：resync / RESYNC_REQUIRED 冻结桌面并进入可恢复重连，不得 terminal
			if bool(ingested.get("resync", false)) \
					or str(ingested.get("reason", "")) == "RESYNC_REQUIRED" \
					or (nbc != null and nbc.resync_required()):
				_emit_authority_resync(str(ingested.get("reason", "RESYNC_REQUIRED")))
				return
			var ingest_code := str(ingested.get("error", ""))
			if ingest_code.is_empty():
				ingest_code = str(ingested.get("reason", "EVENT_REJECTED"))
			_emit_terminal(ingest_code, "authority event rejected")
			return
		# #380：仅在成功入 bridge 后投影 committed journal（pending 不在 journal）
		_drain_settlement_from_journal()
		if str(d.get("kind", "")) == "ROOM_SNAPSHOT" and bool(ingested.get("applied", true)):
			# 结算 resync 中不得同帧 room_started / recovered
			if _settlement_resync_active or _settlement_phase == "resync":
				return
			_has_committed_snapshot = true
			room_started_hint.emit()
			if _recovering:
				_recovering = false
				_resync_reconnect_notified = false
				recovered.emit()
				# #378 P1：snapshot 只标记恢复；不得在尚无 TURN/CLAIM 时判 mismatch
			return
		# #378：仅当新代际收到真实 TURN/CLAIM 后比较 decision，匹配才重试
		if _pending_retry_on_recover and (
			str(d.get("kind", "")) == "TURN_PROMPT" or str(d.get("kind", "")) == "CLAIM_WINDOW"
		):
			_maybe_retry_pending_after_recover()
		return


func _handle_control_error(d: Dictionary) -> void:
	var code := str(d.get("code", "ERROR"))
	var message := str(d.get("message", ""))
	var cmd_raw: Variant = d.get("command_id", null)
	var cmd := ""
	if typeof(cmd_raw) == TYPE_STRING:
		cmd = str(cmd_raw)
	# #378 P2：仅 canonical 且精确匹配 pending.command_id 的 ERROR 才消费 pending
	# 空/异 command_id 可能是 JOIN/房间 terminal，不得伪装成该命令拒绝
	if _pending_awaiting_result and _pending_action != null:
		if ProtocolUuid.is_canonical_v4(cmd) and cmd == _pending_action.command_id:
			var pending_cmd := _pending_action.command_id
			_pending_awaiting_result = false
			_pending_retry_on_recover = false
			_pending_action = null
			_pending_generation = -1
			command_rejected.emit(code, pending_cmd, message)
			command_result_received.emit("REJECTED", code, pending_cmd)
			return
	# JOIN 前 ERROR → terminal（既有语义）
	if not _game_joined:
		_emit_terminal(code, message)


func _handle_command_result_wire(text: String, d: Dictionary) -> void:
	# 仅严格五键 CommandResult；伪造字段不得当权威
	var cr: CommandResult = JsonTransportDecoder.decode_command_result(text)
	if cr == null:
		# REJECTED 不应走五键 ACCEPTED 路径；忽略畸形
		return
	if not _pending_awaiting_result or _pending_action == null:
		return
	if cr.command_id != _pending_action.command_id:
		return
	if cr.status == "ACCEPTED":
		_pending_awaiting_result = false
		_pending_retry_on_recover = false
		_pending_action = null
		_pending_generation = -1
		# ACCEPTED 后仍锁定出口直到 CR.server_seq 对应业务事件入账
		_awaiting_committed = true
		_accepted_commit_seq = int(cr.server_seq)
		command_accepted.emit(cr)
		command_result_received.emit("ACCEPTED", "", cr.command_id)
		_try_clear_awaiting_committed()
		return
	if cr.status == "REJECTED":
		var ec := cr.error_code
		_pending_awaiting_result = false
		_pending_retry_on_recover = false
		_pending_action = null
		_pending_generation = -1
		_awaiting_committed = false
		_accepted_commit_seq = 0
		command_rejected.emit(ec, cr.command_id, "rejected")
		command_result_received.emit("REJECTED", ec, cr.command_id)


func _maybe_retry_pending_after_recover() -> void:
	if not _pending_retry_on_recover or _pending_action == null:
		return
	if _pending_generation == _connection_generation:
		# 同代际已发送，不应再 recover 重试
		return
	if _game_peer == null or _game_peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not _game_joined:
		return
	var pending: Action = _pending_action
	# 尚无本席 TURN/CLAIM：继续等待新 prompt，不得提前 mismatch 丢弃
	var last: NetworkedEvent = _latest_self_decision_event()
	if last == null:
		return
	if not _pending_matches_current_authority(pending):
		_clear_pending("decision_mismatch")
		return
	# 原 command_id + 原 payload 安全重试（新代际）
	var payload_text := JSON.stringify(pending.to_dict())
	var err: Error = _game_peer.send_text(payload_text)
	if err != OK:
		_clear_pending("retry_send_failed")
		return
	_pending_generation = _connection_generation
	_pending_awaiting_result = true
	_pending_retry_on_recover = false


func _pending_matches_current_authority(pending: Action) -> bool:
	if pending == null or nbc == null:
		return false
	if pending.room_id != room_id or int(pending.seat) != seat:
		return false
	var last: NetworkedEvent = _latest_self_decision_event()
	if last == null:
		return false
	var p: Dictionary = last.payload
	if str(p.get("decision_id", "")) != pending.decision_id:
		return false
	if int(p.get("hand_seq", -1)) != pending.hand_seq:
		return false
	if last.kind == "TURN_PROMPT" and int(p.get("seat", -1)) != seat:
		return false
	return true


func _latest_self_decision_event() -> NetworkedEvent:
	if nbc == null:
		return null
	var last: NetworkedEvent = null
	for item in nbc.get_event_journal():
		if not (item is NetworkedEvent):
			continue
		var ne: NetworkedEvent = item as NetworkedEvent
		if ne.kind == "ROOM_SNAPSHOT":
			last = null
			continue
		if ne.kind == "TURN_PROMPT":
			if int(ne.payload.get("seat", -1)) == seat:
				last = ne
			continue
		if ne.kind == "CLAIM_WINDOW":
			last = ne
	return last


func retry_reconnect() -> Error:
	if _released or not _recovering or worker_url.is_empty():
		return ERR_INVALID_PARAMETER
	# #377 P1：authority resync 可能留下 OPEN/CONNECTING/CLOSING peer；
	# 关闭并替换，不得 ERR_BUSY 阻断「重新连接」。
	if _game_peer != null:
		var st: int = _game_peer.get_ready_state()
		if st != WebSocketPeer.STATE_CLOSED:
			_game_peer.close()
		_game_peer = null
	_game_peer = WebSocketPeer.new()
	_game_joined = false
	_game_join_sent = false
	_game_ready_sent = false
	_closed_notified = false
	_terminal_notified = false
	# #378：新连接代际；旧连接 generation 绝不可再提交
	_connection_generation += 1
	if _pending_action != null:
		# 保留 pending：仍 awaiting，或断线时已标记待重试。
		# 不得在已设 _pending_retry_on_recover 时误清（否则同 decision 重试永远不发生）。
		if _pending_awaiting_result or _pending_retry_on_recover:
			_pending_retry_on_recover = true
			_pending_awaiting_result = false
		else:
			_clear_pending("reconnect_no_await")
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


## #380：只读结算投影（phase / hand / match / local_seat / roster）。
func get_settlement_view() -> Dictionary:
	var hand_v: Variant = null
	if not _settlement_hand.is_empty():
		hand_v = _settlement_hand.duplicate(true)
	var match_v: Variant = null
	if not _settlement_match.is_empty():
		match_v = _settlement_match.duplicate(true)
	return {
		"phase": _settlement_phase,
		"hand": hand_v,
		"match": match_v,
		"local_seat": seat,
		"roster": _roster_list(),
	}


func _roster_list() -> Array:
	var out: Array = []
	for s in range(4):
		out.append({
			"seat": s,
			"display_name": str(_roster_names.get(s, "")),
			"character_id": str(_character_ids[s]) if s < _character_ids.size() else "",
		})
	return out


func _reset_settlement_projection() -> void:
	_settlement_phase = "idle"
	_settlement_hand = {}
	_settlement_match = {}
	_roster_names.clear()
	_character_ids = []
	_settlement_journal_cursor = 0
	_match_latched = false
	_last_settlement_sig = ""
	_ledger_hand_seq = -1
	_last_settled_hand_seq = -1
	_settlement_resync_active = false


func _emit_settlement_if_changed() -> void:
	var view: Dictionary = get_settlement_view()
	var sig := JSON.stringify(view)
	if sig == _last_settlement_sig:
		return
	_last_settlement_sig = sig
	settlement_view_changed.emit(view)


## #380：SNAP 入 NBC 前连续性检查（拒绝错误账本提交）。
func _settlement_preflight_room_snapshot(ne: NetworkedEvent) -> Dictionary:
	if ne == null:
		return {"ok": false, "reason": "BAD_EVENT"}
	# 终场锁存后：任意迟到 ROOM_SNAPSHOT 静默丢弃（不入 NBC、不 resync、不改 match_result）
	if _match_latched:
		return {"ok": false, "reason": "MATCH_LATCHED_SNAPSHOT", "discard_only": true}
	if _settlement_phase != "hand_result" or _settlement_hand.is_empty():
		return {"ok": true}
	var snap_scores: Array = _settlement_scores_from_snapshot(ne)
	if snap_scores.is_empty():
		return {"ok": true}
	var hand_scores: Array = _settlement_hand.get("scores", []) as Array
	# 相同/旧 hand_seq 的 filler SNAP：允许提交桌面但不作为「合法新局」关弹层（apply 侧门控）
	# 起分不一致且为更高 hand_seq 的新局：拒绝
	if not _settlement_scores_equal(snap_scores, hand_scores):
		# 仅当看起来像「新局」或无法判定 hand_seq 时 resync；旧局同分错误也 resync
		return {"ok": false, "reason": "SETTLEMENT_SCORE_MISMATCH"}
	return {"ok": true}


func _reject_settlement_snapshot(reason: String) -> void:
	# 不提交 SNAP；NBC 进入 resync；HAND scores 保留；只发 reconnecting
	if nbc != null:
		nbc.force_resync_for_authority_gap()
	_settlement_phase = "resync"
	_settlement_resync_active = true
	_emit_settlement_if_changed()
	_emit_authority_resync(reason if not reason.is_empty() else "SETTLEMENT_SCORE_MISMATCH")


## 仅消费 NBC committed journal；pending 事件不在 journal 中。
func _drain_settlement_from_journal() -> void:
	if nbc == null:
		return
	var journal: Array = nbc.get_event_journal()
	for item in journal:
		var ne: NetworkedEvent = null
		if item is NetworkedEvent:
			ne = item as NetworkedEvent
		elif typeof(item) == TYPE_DICTIONARY:
			ne = NetworkedEvent.from_dict(item)
		if ne == null:
			continue
		var seq: int = int(ne.server_seq)
		if seq <= _settlement_journal_cursor:
			continue
		match String(ne.kind):
			"PLAYER_JOINED":
				_settlement_apply_player_joined(ne)
			"HAND_SETTLED":
				_settlement_apply_hand(ne)
			"MATCH_SETTLED":
				_settlement_apply_match(ne)
			"ROOM_SNAPSHOT":
				_settlement_apply_snapshot(ne)
		_settlement_journal_cursor = maxi(_settlement_journal_cursor, seq)
	_emit_settlement_if_changed()


func _settlement_apply_player_joined(ne: NetworkedEvent) -> void:
	var p: Dictionary = ne.payload
	var s: int = int(p.get("seat", -1))
	if s < 0 or s > 3:
		return
	_roster_names[s] = str(p.get("display_name", ""))


func _settlement_apply_hand(ne: NetworkedEvent) -> void:
	if _match_latched:
		return
	if _settlement_resync_active or _settlement_phase == "resync":
		return
	var seq: int = int(ne.server_seq)
	var p: Dictionary = ne.payload
	var hs: int = int(p.get("hand_seq", -1))
	# 必须对应当前 committed 局（ledger）；旧 hand_seq 即使更高 server_seq 也拒绝
	if _ledger_hand_seq >= 0 and hs != _ledger_hand_seq:
		return
	# 已结算过的 hand_seq 不得以新 server_seq 重新打开 UI
	if hs >= 0 and hs <= _last_settled_hand_seq and _settlement_phase != "hand_result":
		return
	if not _settlement_hand.is_empty():
		var prev_seq: int = int(_settlement_hand.get("server_seq", -1))
		var prev_hs: int = int(_settlement_hand.get("hand_seq", -1))
		if seq <= prev_seq:
			return
		if hs == prev_hs and seq > prev_seq:
			# 同局重复 HAND：不覆盖已展示权威
			return
	_settlement_hand = {
		"hand_seq": hs,
		"outcome": str(p.get("outcome", "")),
		"winner_seats": (p.get("winner_seats", []) as Array).duplicate(),
		"loser_seat": int(p.get("loser_seat", -1)),
		"score_deltas": (p.get("score_deltas", []) as Array).duplicate(),
		"scores": (p.get("scores", []) as Array).duplicate(),
		"dealer_seat": int(p.get("dealer_seat", 0)),
		"renchan": bool(p.get("renchan", false)),
		"honba": int(p.get("honba", 0)),
		"riichi_sticks": int(p.get("riichi_sticks", 0)),
		"server_seq": seq,
	}
	_settlement_phase = "hand_result"
	if hs >= 0:
		_last_settled_hand_seq = hs


func _settlement_apply_match(ne: NetworkedEvent) -> void:
	# 终态锁存：重复 MATCH 不得覆盖
	if _match_latched:
		return
	var p: Dictionary = ne.payload
	var finals: Array = (p.get("final_scores", []) as Array).duplicate()
	var order: Array = (p.get("seat_order", []) as Array).duplicate()
	var rows: Array = []
	for i in range(order.size()):
		var sid: int = int(order[i])
		var score := 0
		if sid >= 0 and sid < finals.size():
			score = int(finals[sid])
		var cname := ""
		if sid >= 0 and sid < _character_ids.size():
			cname = str(_character_ids[sid])
		var dname := str(_roster_names.get(sid, ""))
		if dname.is_empty():
			dname = "席位%d" % sid
		rows.append({
			"rank": i + 1,
			"seat_id": sid,
			"name": dname,
			"character_id": cname,
			"score": score,
			"is_local": sid == seat,
		})
	_settlement_match = {
		"round_kind": str(p.get("round_kind", "")),
		"final_scores": finals,
		"seat_order": order,
		"rows": rows,
		"server_seq": int(ne.server_seq),
		"rematch_label": "再次匹配",
	}
	_settlement_hand = {}
	_settlement_phase = "match_result"
	_match_latched = true
	_settlement_resync_active = false
	# 库存权威投影仅由 ROOM_SNAPSHOT registry restore；不在此伪造 apply_restored_module/clear。
	# 终场可见清场由 PlayableTable match_result 展示边界完成；迟到 SNAP 由 preflight 整包丢弃。


func _settlement_apply_snapshot(ne: NetworkedEvent) -> void:
	_settlement_refresh_meta_from_snapshot(ne)
	var snap_hs := _settlement_hand_seq_from_snapshot(ne)
	# 终场锁存：迟到 SNAP 不得覆盖 match_result
	if _match_latched:
		_settlement_phase = "match_result"
		return
	if _settlement_phase == "hand_result" and not _settlement_hand.is_empty():
		var snap_scores: Array = _settlement_scores_from_snapshot(ne)
		var hand_scores: Array = _settlement_hand.get("scores", []) as Array
		# 合法新局：snap_hand_seq > settled_hand_seq 且起分一致 → 关单局弹层
		var is_next_hand := snap_hs > _last_settled_hand_seq
		if (
			not snap_scores.is_empty()
			and _settlement_scores_equal(snap_scores, hand_scores)
			and is_next_hand
		):
			_settlement_hand = {}
			_settlement_phase = "idle"
			_settlement_resync_active = false
			_ledger_hand_seq = snap_hs
		# 同/旧 hand_seq filler：保持 hand_result；不一致已在 preflight 拒绝
		return
	# 非 hand_result：推进 ledger 到当前 SNAP 局
	if snap_hs >= 0:
		_ledger_hand_seq = snap_hs
	_settlement_resync_active = false


func _settlement_hand_seq_from_snapshot(ne: NetworkedEvent) -> int:
	var modules: Array = ne.payload.get("modules", []) as Array
	for m in modules:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("module_key", "")) != "core_table":
			continue
		var payload: Variant = m.get("payload", {})
		if typeof(payload) != TYPE_DICTIONARY:
			return -1
		return int((payload as Dictionary).get("hand_seq", -1))
	return -1


func _settlement_refresh_meta_from_snapshot(ne: NetworkedEvent) -> void:
	var modules: Array = ne.payload.get("modules", []) as Array
	for m in modules:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("module_key", "")) != "matching_meta":
			continue
		var payload: Variant = m.get("payload", {})
		if typeof(payload) != TYPE_DICTIONARY:
			continue
		var chars: Variant = (payload as Dictionary).get("character_ids", null)
		if typeof(chars) == TYPE_ARRAY:
			_character_ids = (chars as Array).duplicate()
		break


func _settlement_scores_from_snapshot(ne: NetworkedEvent) -> Array:
	var modules: Array = ne.payload.get("modules", []) as Array
	for m in modules:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str(m.get("module_key", "")) != "core_table":
			continue
		var payload: Variant = m.get("payload", {})
		if typeof(payload) != TYPE_DICTIONARY:
			return []
		var seats: Array = (payload as Dictionary).get("seats", []) as Array
		var out: Array = [0, 0, 0, 0]
		var filled := 0
		for s in seats:
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var sid: int = int((s as Dictionary).get("seat", -1))
			if sid < 0 or sid > 3:
				continue
			out[sid] = int((s as Dictionary).get("score", 0))
			filled += 1
		if filled >= 4:
			return out
		return out
	return []


func _settlement_scores_equal(a: Array, b: Array) -> bool:
	if a.size() != 4 or b.size() != 4:
		return false
	for i in range(4):
		if int(a[i]) != int(b[i]):
			return false
	return true


func release() -> void:
	if _released:
		# 幂等：二次 release 仍保证敏感字段为空
		_clear_runtime_identity()
		return
	_released = true
	_want_open = false
	_clear_pending("release")
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
	_resync_reconnect_notified = false
	_connection_generation = 0
	_client_seq = 0
	_reset_settlement_projection()
	_clear_runtime_identity()


## #380：清除 token / session / worker 等敏感与运行身份引用。
func _clear_runtime_identity() -> void:
	room_token = ""
	session_id = ""
	worker_url = ""
	voice_worker_url = ""
	room_id = ""
	game_mode = ""
	seat = -1


func _exit_tree() -> void:
	release()
