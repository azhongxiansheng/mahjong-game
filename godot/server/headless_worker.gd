class_name HeadlessWorker
extends Node

# #240：Godot Headless Worker — 公共牌局唯一权威 WebSocket 入口。
# TCPServer + WebSocketPeer.accept_stream；验 room_token；JOIN/READY/Action。
# #241：连接代际、掉线 30s lease、重连快照、AI 接管/归还。
# 不依赖 Redis。网络端到端未验证。

const JOIN_KEYS := ["protocol_version", "kind", "room_id", "seat", "room_token"]
const READY_KEYS := ["protocol_version", "kind", "room_id", "seat"]
const CONTROL_ERROR_KIND := "ERROR"

signal client_message_handled(conn_id: int, kind: String)

var bind_host: String = "127.0.0.1"
var bind_port: int = 9000
var token_now_unix: int = -1  # 测试时钟；生产 -1
## #241：可注入单调时钟（毫秒）。>=0 时使用注入值；-1 用 Time.get_ticks_msec()。
var clock_now_ms: int = -1

var _tcp: TCPServer = TCPServer.new()
var _verifier: RoomTokenVerifier = RoomTokenVerifier.new()
var _listening: bool = false

# conn_id -> connection state
var _conns: Dictionary = {}
var _next_conn_id: int = 1
var _next_generation: int = 1
# room_id -> HeadlessRoomSession
var _rooms: Dictionary = {}


func configure(secret: String, host: String = "127.0.0.1", port: int = 9000) -> bool:
	if not _verifier.set_secret(secret):
		return false
	bind_host = host
	bind_port = port
	return true


func start_listen() -> Error:
	if _listening:
		return ERR_ALREADY_IN_USE
	var err: Error = _tcp.listen(bind_port, bind_host)
	if err != OK:
		return err
	_listening = true
	return OK


func stop() -> void:
	_listening = false
	for cid in _conns.keys():
		_close_conn(int(cid))
	_conns.clear()
	if _tcp.is_listening():
		_tcp.stop()
	_rooms.clear()


func is_listening() -> bool:
	return _listening and _tcp.is_listening()


func room_count() -> int:
	return _rooms.size()


func get_room(room_id: String) -> HeadlessRoomSession:
	if _rooms.has(room_id):
		return _rooms[room_id] as HeadlessRoomSession
	return null


func _process(_delta: float) -> void:
	poll()


func now_ms() -> int:
	if clock_now_ms >= 0:
		return clock_now_ms
	return Time.get_ticks_msec()


func set_clock_ms_for_test(ms: int) -> void:
	clock_now_ms = ms


func poll() -> void:
	if not _listening:
		return
	while _tcp.is_connection_available():
		var stream: StreamPeerTCP = _tcp.take_connection()
		if stream == null:
			break
		var peer := WebSocketPeer.new()
		var acc: Error = peer.accept_stream(stream)
		if acc != OK:
			continue
		var cid: int = _next_conn_id
		_next_conn_id += 1
		_conns[cid] = {
			"peer": peer,
			"stream": stream,
			"joined": false,
			"room_id": "",
			"seat": -1,
			"session_id": "",
			"last_seq": 0,
			"generation": 0,
			"superseded": false,
		}
	var to_drop: Array = []
	for cid in _conns.keys():
		var id: int = int(cid)
		if not _poll_conn(id):
			to_drop.append(id)
	for id in to_drop:
		_close_conn(int(id))
	# #241：掉线 lease / AI 接管（真实生产路径）
	_tick_all_leases()


func _poll_conn(cid: int) -> bool:
	if not _conns.has(cid):
		return false
	var st: Dictionary = _conns[cid]
	var peer: WebSocketPeer = st["peer"] as WebSocketPeer
	peer.poll()
	var state: int = peer.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSING or state == WebSocketPeer.STATE_CLOSED:
		return false
	if state != WebSocketPeer.STATE_OPEN:
		return true
	while peer.get_available_packet_count() > 0:
		# Godot 4.6：先 get_packet，再 was_string_packet 查询“刚取出的包”是否文本
		var pkt: PackedByteArray = peer.get_packet()
		var is_text: bool = peer.was_string_packet()
		_dispatch_packet(cid, pkt, is_text)
	return true


## 统一包分发：文本 JSON 进命令入口；二进制帧拒绝且不改权威状态。
func _dispatch_packet(cid: int, pkt: PackedByteArray, is_text: bool) -> void:
	if not is_text:
		_handle_binary_forbidden(cid)
		return
	_handle_text(cid, pkt.get_string_from_utf8())


func _handle_binary_forbidden(cid: int) -> void:
	# 协议冻结为文本 JSON；二进制不得触发 JOIN/Action
	_send_error(cid, _conn_room(cid), "", "COMMAND_REJECTED", "binary frame forbidden")
	var st: Dictionary = _conns.get(cid, {})
	st["binary_rejected"] = true
	_conns[cid] = st
	var peer: WebSocketPeer = st.get("peer") as WebSocketPeer
	if peer != null:
		peer.close()


func _handle_text(cid: int, text: String) -> void:
	if not _conns.has(cid):
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_send_error(cid, "", "", "COMMAND_REJECTED", "invalid json")
		return
	var d: Dictionary = parsed
	if not d.has("kind") or typeof(d["kind"]) != TYPE_STRING:
		_send_error(cid, str(d.get("room_id", "")), "", "COMMAND_REJECTED", "missing kind")
		return
	var kind: String = d["kind"]
	match kind:
		"JOIN":
			_handle_join(cid, d)
		"READY":
			_handle_ready(cid, d)
		"DISCARD", "CHI", "PON", "KAN", "RIICHI", "RON", "TSUMO", "PASS", \
		"ITEM_USE", "DECLARE_ABORTIVE_DRAW":
			_handle_action(cid, d)
		_:
			# 服务端专属 EventKind / ERROR 控制 kind 一律伪造拒绝
			if kind == CONTROL_ERROR_KIND or kind in NetworkedEvent.EVENT_KINDS:
				_send_error(cid, str(d.get("room_id", "")), str(d.get("command_id", "")),
					"FORGERY_REJECTED", "server event kind forbidden")
			else:
				_send_error(cid, str(d.get("room_id", "")), str(d.get("command_id", "")),
					"COMMAND_REJECTED", "unknown kind")
	client_message_handled.emit(cid, kind)


func _handle_join(cid: int, d: Dictionary) -> void:
	if not _exact_keys(d, JOIN_KEYS):
		_send_error(cid, str(d.get("room_id", "")), "", "COMMAND_REJECTED", "invalid JOIN schema")
		return
	# JSON 数字可能是 float；仅接受整数值 1
	if not _is_json_int(d["protocol_version"]) or int(d["protocol_version"]) != 1:
		_send_error(cid, str(d.get("room_id", "")), "", "PROTOCOL_VERSION_UNSUPPORTED", "version")
		return
	if typeof(d["room_id"]) != TYPE_STRING or typeof(d["room_token"]) != TYPE_STRING:
		_send_error(cid, "", "", "COMMAND_REJECTED", "bad types")
		return
	if not _is_json_int(d["seat"]):
		_send_error(cid, str(d["room_id"]), "", "COMMAND_REJECTED", "bad seat type")
		return
	var st: Dictionary = _conns[cid]
	# 同一连接禁止二次 JOIN（含改绑）；原 room/seat/session 完全不变
	if bool(st.get("joined", false)):
		_send_error(cid, str(st.get("room_id", "")), "", "COMMAND_REJECTED", "already joined")
		return
	var room_id: String = d["room_id"]
	var seat: int = int(d["seat"])
	var room_token: String = d["room_token"]
	var claims: Dictionary = _verifier.verify(room_token, room_id, seat, token_now_unix)
	if claims.is_empty():
		_send_error(cid, room_id, "", "UNAUTHORIZED", "room token rejected")
		return
	var session: HeadlessRoomSession = null
	if _rooms.has(room_id):
		session = _rooms[room_id] as HeadlessRoomSession
		# 已建房：bootstrap claims 必须一致
		if session.round_kind != str(claims["round_kind"]) \
				or session.game_mode != str(claims["game_mode"]) \
				or not _participants_equal(session.participants, claims["participants"]):
			_send_error(cid, room_id, "", "UNAUTHORIZED", "bootstrap mismatch")
			return
	else:
		session = HeadlessRoomSession.new()
		if not session.bootstrap_from_claims(claims):
			_send_error(cid, room_id, "", "COMMAND_REJECTED", "bootstrap failed")
			return
		_rooms[room_id] = session
	var session_id: String = str(claims["session_id"])
	var pre: Dictionary = session.can_join(seat, session_id)
	if not bool(pre.get("ok", false)):
		_send_error(cid, room_id, "", str(pre.get("code", "UNAUTHORIZED")), str(pre.get("message", "")))
		return
	var is_reconnect: bool = bool(pre.get("reconnect", false))
	var gen: int = _next_generation
	_next_generation += 1
	var seq_before: int = session.current_server_seq()
	var frozen_ctrl: Dictionary = {}
	# 重连且已开局：先交付当前快照（失败则不绑定连接、回滚控制态）
	if is_reconnect and session.is_started():
		frozen_ctrl = session.capture_seat_control_state(seat)
		var prep: Dictionary = session.prepare_reconnect_delivery(seat)
		if not bool(prep.get("ok", false)):
			session.restore_seat_control_state(seat, frozen_ctrl)
			_send_error(cid, room_id, "", "COMMAND_REJECTED", str(prep.get("message", "resync")))
			return
		# 交付成功后提交绑定；last_seq=交付前序号 → 只发新快照及之后增量
		var jr_rc: Dictionary = session.join(seat, session_id, cid, gen)
		if not bool(jr_rc.get("ok", false)):
			session.restore_seat_control_state(seat, frozen_ctrl)
			_send_error(cid, room_id, "", str(jr_rc.get("code", "UNAUTHORIZED")), str(jr_rc.get("message", "")))
			return
		var replaced_rc: int = int(jr_rc.get("replaced_conn_id", -1))
		if replaced_rc >= 0 and replaced_rc != cid:
			_supersede_conn(replaced_rc)
		st["joined"] = true
		st["room_id"] = room_id
		st["seat"] = seat
		st["session_id"] = session_id
		st["generation"] = gen
		st["superseded"] = false
		st["last_seq"] = seq_before
		_conns[cid] = st
		# 重连席：只 flush 新事件；其它已连接席同样只收增量
		_flush_events(cid)
		_broadcast_room_events_except(room_id, cid)
		return
	# 首次 JOIN 或未开局
	var jr: Dictionary = session.join(seat, session_id, cid, gen)
	if not bool(jr.get("ok", false)):
		_send_error(cid, room_id, "", str(jr.get("code", "UNAUTHORIZED")), str(jr.get("message", "")))
		return
	var replaced_cid: int = int(jr.get("replaced_conn_id", -1))
	if replaced_cid >= 0 and replaced_cid != cid:
		_supersede_conn(replaced_cid)
	st["joined"] = true
	st["room_id"] = room_id
	st["seat"] = seat
	st["session_id"] = session_id
	st["generation"] = gen
	st["superseded"] = false
	st["last_seq"] = 0
	_conns[cid] = st
	if session.is_started():
		_flush_events(cid)


func _handle_ready(cid: int, d: Dictionary) -> void:
	if not _exact_keys(d, READY_KEYS):
		_send_error(cid, str(d.get("room_id", "")), "", "COMMAND_REJECTED", "invalid READY schema")
		return
	if not _is_json_int(d["protocol_version"]) or int(d["protocol_version"]) != 1:
		_send_error(cid, str(d.get("room_id", "")), "", "PROTOCOL_VERSION_UNSUPPORTED", "version")
		return
	if not _is_json_int(d.get("seat", null)):
		_send_error(cid, str(d.get("room_id", "")), "", "COMMAND_REJECTED", "bad seat type")
		return
	var st: Dictionary = _conns[cid]
	if not bool(st.get("joined", false)):
		_send_error(cid, str(d.get("room_id", "")), "", "UNAUTHORIZED", "not joined")
		return
	var room_id: String = str(d["room_id"])
	var seat: int = int(d["seat"])
	if room_id != str(st["room_id"]) or seat != int(st["seat"]):
		_send_error(cid, room_id, "", "UNAUTHORIZED", "seat/room binding mismatch")
		return
	var session: HeadlessRoomSession = get_room(room_id)
	if session == null:
		_send_error(cid, room_id, "", "COMMAND_REJECTED", "no room")
		return
	var was_started: bool = session.is_started()
	var rr: Dictionary = session.ready(seat, str(st["session_id"]))
	if not bool(rr.get("ok", false)):
		_send_error(cid, room_id, "", str(rr.get("code", "COMMAND_REJECTED")), str(rr.get("message", "")))
		return
	# 开局后向全房已连接客户端刷事件
	if session.is_started() and not was_started:
		_broadcast_room_events(room_id)
	elif session.is_started():
		_flush_events(cid)


func _handle_action(cid: int, d: Dictionary) -> void:
	var st: Dictionary = _conns[cid]
	if not bool(st.get("joined", false)) or bool(st.get("superseded", false)):
		_send_error(cid, str(d.get("room_id", "")), _cmd_id_or_empty(d),
			"UNAUTHORIZED", "not joined")
		return
	# 禁止客户端塞结果字段 / server_seq
	if d.has("server_seq") or d.has("view_hash") or d.has("status") or d.has("error_code"):
		_send_error(cid, str(d.get("room_id", "")), _cmd_id_or_empty(d),
			"FORGERY_REJECTED", "forbidden authority fields")
		return
	# #240：Worker 入口验收 command_id（canonical v4）；非法不进领域、不改权威状态
	if not _is_canonical_command_id(d.get("command_id", null)):
		_send_error(cid, str(d.get("room_id", "")), "", "COMMAND_REJECTED", "invalid command_id")
		return
	# JsonTransportDecoder 无 class_name；经 load 做 JSON 数字安全转换
	var action: Action = null
	var dec_scr: Variant = load("res://protocol/json_transport_decoder.gd")
	if dec_scr != null:
		action = dec_scr.decode_action(JSON.stringify(d))
	if action == null:
		action = Action.from_dict(d)
	if action == null:
		_send_error(cid, str(d.get("room_id", "")), _cmd_id_or_empty(d),
			"COMMAND_REJECTED", "invalid action")
		return
	var room_id: String = str(st["room_id"])
	var seat: int = int(st["seat"])
	if action.room_id != room_id or int(action.seat) != seat:
		_send_error(cid, room_id, action.command_id, "UNAUTHORIZED", "action seat/room mismatch")
		return
	var session: HeadlessRoomSession = get_room(room_id)
	if session == null or not session.is_started():
		_send_error(cid, room_id, action.command_id, "COMMAND_REJECTED", "not started")
		return
	# #241：仅当前有效连接代际可提交
	if not session.is_connection_active(seat, cid, int(st.get("generation", -1))):
		_send_error(cid, room_id, action.command_id, "UNAUTHORIZED", "stale connection")
		return
	var seq_before: int = session.current_server_seq()
	var cr: CommandResult = session.submit_action_for_seat(seat, action)
	if cr == null:
		_send_error(cid, room_id, action.command_id, "COMMAND_REJECTED", "null result")
		return
	if cr.status == "REJECTED":
		# ADR §6.4：领域拒绝走 ERROR 控制通道，无 server_seq/view_hash，不广播业务事件
		var code := "COMMAND_REJECTED"
		var ec: String = cr.error_code
		if ec == "UNAUTHORIZED":
			code = "UNAUTHORIZED"
		elif ec == "COMMAND_ID_CONFLICT":
			code = "COMMAND_ID_CONFLICT"
		_send_error(cid, room_id, action.command_id, code, "rejected")
		# 拒绝不得推进权威序号；不 flush 事件
		if session.current_server_seq() != seq_before:
			# 防御：若内部误推进仍不向客户端泄露细节
			pass
		return
	# 仅 ACCEPTED 发送 CommandResult 并广播权威事件
	_send_json(cid, cr.to_dict())
	_broadcast_room_events(room_id)


func _broadcast_room_events(room_id: String) -> void:
	_broadcast_room_events_except(room_id, -1)


func _broadcast_room_events_except(room_id: String, except_cid: int) -> void:
	for cid in _conns.keys():
		var id: int = int(cid)
		if except_cid >= 0 and id == except_cid:
			continue
		var st: Dictionary = _conns[cid]
		if str(st.get("room_id", "")) == room_id and bool(st.get("joined", false)) \
				and not bool(st.get("superseded", false)):
			_flush_events(id)


func _flush_events(cid: int) -> void:
	if not _conns.has(cid):
		return
	var st: Dictionary = _conns[cid]
	var room_id: String = str(st.get("room_id", ""))
	var seat: int = int(st.get("seat", -1))
	var session: HeadlessRoomSession = get_room(room_id)
	if session == null:
		return
	var after: int = int(st.get("last_seq", 0))
	var events: Array = session.events_since(seat, after)
	var max_seq: int = after
	for ev in events:
		if ev is NetworkedEvent:
			var ne: NetworkedEvent = ev as NetworkedEvent
			_send_json(cid, ne.to_dict())
			if ne.server_seq > max_seq:
				max_seq = ne.server_seq
	st["last_seq"] = max_seq
	_conns[cid] = st


func _send_error(cid: int, room_id: String, command_id: String, code: String, message: String) -> void:
	# ERROR wire：command_id 可空（null）；避免 String|null 三元类型告警
	var body: Dictionary = {
		"protocol_version": 1,
		"room_id": room_id,
		"kind": CONTROL_ERROR_KIND,
		"request_id": null,
		"code": code,
		"message": message,
	}
	if command_id.is_empty():
		body["command_id"] = null
	else:
		body["command_id"] = command_id
	_send_json(cid, body)


func _cmd_id_or_empty(d: Dictionary) -> String:
	if not d.has("command_id") or typeof(d["command_id"]) != TYPE_STRING:
		return ""
	return str(d["command_id"])


func _is_canonical_command_id(v: Variant) -> bool:
	if typeof(v) != TYPE_STRING:
		return false
	return ProtocolUuid.is_canonical_v4(str(v))


func _close_conn(cid: int) -> void:
	if not _conns.has(cid):
		return
	var st: Dictionary = _conns[cid]
	# #241：仅当前有效连接关闭时启动 lease；被替换连接不触发
	if bool(st.get("joined", false)) and not bool(st.get("superseded", false)):
		var room_id: String = str(st.get("room_id", ""))
		var session: HeadlessRoomSession = get_room(room_id)
		if session != null:
			session.on_connection_closed(
				int(st.get("seat", -1)),
				str(st.get("session_id", "")),
				cid,
				int(st.get("generation", -1)),
				now_ms()
			)
	var peer: WebSocketPeer = st.get("peer") as WebSocketPeer
	if peer != null:
		peer.close()
	_conns.erase(cid)


## 同 session 新连接替换：立即失效旧连接，不启动 lease、不影响新连接。
func _supersede_conn(cid: int) -> void:
	if not _conns.has(cid):
		return
	var st: Dictionary = _conns[cid]
	st["superseded"] = true
	st["joined"] = false
	_conns[cid] = st
	var peer: WebSocketPeer = st.get("peer") as WebSocketPeer
	if peer != null:
		peer.close()
		_conns.erase(cid)
	# peer==null 测试桩：保留 superseded 条目，供旧连接动作拒绝断言


func _tick_all_leases() -> void:
	var now: int = now_ms()
	var rooms_touched: Dictionary = {}
	for rid in _rooms.keys():
		var session: HeadlessRoomSession = _rooms[rid] as HeadlessRoomSession
		if session == null:
			continue
		var room_key: String = str(rid)
		var taken: Array = session.tick_leases(now)
		if not taken.is_empty():
			rooms_touched[room_key] = true
		# AI 接管席：每个 poll/tick 至多一步权威 Action
		if session.has_ai_controlled_seat():
			var step: Dictionary = session.step_ai_once()
			if bool(step.get("advanced", false)):
				rooms_touched[room_key] = true
	for rid2 in rooms_touched.keys():
		_broadcast_room_events(str(rid2))


## 测试：显式推进 lease + AI 单步（不依赖 TCP listen）。
func tick_leases_for_test() -> void:
	_tick_all_leases()


## 测试：仅推进 AI 单步（不改时钟/lease）。
func step_ai_for_test(room_id: String) -> Dictionary:
	var session: HeadlessRoomSession = get_room(room_id)
	if session == null:
		return {"ok": false, "advanced": false}
	var step: Dictionary = session.step_ai_once()
	if bool(step.get("advanced", false)):
		_broadcast_room_events(room_id)
	return step


## 测试：模拟连接断开（走真实 on_connection_closed 路径）。
func simulate_disconnect_for_test(cid: int) -> void:
	_close_conn(cid)


func _exact_keys(d: Dictionary, expected: Array) -> bool:
	if d.keys().size() != expected.size():
		return false
	for k in expected:
		if not d.has(k):
			return false
	return true


func _is_json_int(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		return f == floor(f) and f >= float(-ProtocolConstants.MAX_SAFE_INT) \
			and f <= float(ProtocolConstants.MAX_SAFE_INT)
	return false


func _participants_equal(a: Array, b: Variant) -> bool:
	if typeof(b) != TYPE_ARRAY:
		return false
	var bb: Array = b
	if a.size() != bb.size():
		return false
	for i in range(a.size()):
		if str(a[i]) != str(bb[i]):
			return false
	return true


func _ensure_test_conn(cid: int) -> void:
	if _conns.has(cid):
		return
	_conns[cid] = {
		"peer": null,
		"stream": null,
		"joined": false,
		"room_id": "",
		"seat": -1,
		"session_id": "",
		"last_seq": 0,
		"generation": 0,
		"superseded": false,
		"outbox": [],
		"binary_rejected": false,
	}


## 测试辅助：不经 TCP，直接注入已解析 Dictionary（模拟 WS 文本）。
func handle_dict_for_test(cid: int, d: Dictionary) -> void:
	_ensure_test_conn(cid)
	_handle_text(cid, JSON.stringify(d))


## 测试：模拟二进制帧分发（不经真实 peer）。
func handle_binary_for_test(cid: int, raw: PackedByteArray) -> void:
	_ensure_test_conn(cid)
	_dispatch_packet(cid, raw, false)


## 测试：注入已启动会话并绑定连接（绕过 token，专测 Action 错误通道）。
func inject_bound_session_for_test(
	cid: int,
	session: HeadlessRoomSession,
	seat: int,
	session_id: String
) -> void:
	_ensure_test_conn(cid)
	if session == null or session.room_id.is_empty():
		return
	_rooms[session.room_id] = session
	var gen: int = _next_generation
	_next_generation += 1
	session.join(seat, session_id, cid, gen)
	var st: Dictionary = _conns[cid]
	st["joined"] = true
	st["room_id"] = session.room_id
	st["seat"] = seat
	st["session_id"] = session_id
	st["generation"] = gen
	st["superseded"] = false
	st["last_seq"] = 0
	_conns[cid] = st


func test_outbox(cid: int) -> Array:
	if not _conns.has(cid):
		return []
	var st: Dictionary = _conns[cid]
	if st.has("outbox"):
		return (st["outbox"] as Array).duplicate()
	return []


func test_conn_binding(cid: int) -> Dictionary:
	if not _conns.has(cid):
		return {}
	var st: Dictionary = _conns[cid]
	return {
		"joined": bool(st.get("joined", false)),
		"room_id": str(st.get("room_id", "")),
		"seat": int(st.get("seat", -1)),
		"session_id": str(st.get("session_id", "")),
		"generation": int(st.get("generation", 0)),
		"superseded": bool(st.get("superseded", false)),
		"binary_rejected": bool(st.get("binary_rejected", false)),
	}


func clear_outbox_for_test(cid: int) -> void:
	if not _conns.has(cid):
		return
	var st: Dictionary = _conns[cid]
	st["outbox"] = []
	_conns[cid] = st


func _conn_room(cid: int) -> String:
	if not _conns.has(cid):
		return ""
	return str((_conns[cid] as Dictionary).get("room_id", ""))


func _send_json(cid: int, obj: Variant) -> void:
	if not _conns.has(cid):
		return
	var st: Dictionary = _conns[cid]
	# 测试桩：无 peer 时写入 outbox
	if st.get("peer") == null:
		if not st.has("outbox"):
			st["outbox"] = []
		(st["outbox"] as Array).append(obj)
		_conns[cid] = st
		return
	var peer: WebSocketPeer = st["peer"] as WebSocketPeer
	if peer == null or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	peer.send_text(JSON.stringify(obj))
