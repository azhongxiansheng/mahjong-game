class_name VoiceRelayServer
extends Node

# E4-02（#244）：四座位低延迟 WebSocket 语音中继。
# 独立 listener/端口；与牌局 WebSocket 分离，背压不得阻塞牌局通道。
# 鉴权复用 room_token；仅 TRASH_TALK；只广播同房其他 HUMAN。
# STT 仅内存挂点/信号，不实现转写。网络端到端未验证。

const JOIN_KEYS := ["protocol_version", "kind", "room_id", "seat", "room_token"]
## #243 客户端控制帧 exact schema（无权威字段）
const PTT_CLIENT_KEYS := [
	"protocol_version", "room_id", "session_id", "seat", "kind", "utterance_id",
]
const CONTROL_ERROR_KIND := "ERROR"
const DEFAULT_QUEUE_CAPACITY: int = 64
## 每 poll 每连接最多刷出站帧数 → 应用层队列可在突发下积压并丢旧
const OUTBOUND_SEND_BUDGET_PER_POLL: int = 2
## peer 出站缓冲有界（字节 / 包）；低于 Godot 默认 65535/4096
const PEER_OUTBOUND_BUFFER_SIZE: int = 8192
const PEER_MAX_QUEUED_PACKETS: int = 32
## peer 缓冲达到该阈值则停止 put_packet（字节）
const PEER_FLUSH_HIGH_WATER: int = 6144
const MAX_COMPLETED_PTT_ENDS: int = 64
const AUTHORITY_FIELD_KEYS := [
	"server_seq", "server_seq_ref", "view_hash", "status", "error_code",
	"ptt_end_server_seq", "state_hash", "full_state_hash",
	"closing_boundary_server_seq", "grace_deadline_at", "context_boundary_server_seq",
]

## STT 挂点：重建后的 PCM 字典（含 room/seat/session/seq）
signal stt_frame_hook(frame: Dictionary)
## STT 挂点：权威归一化 PTT_END（含 server_seq）
signal stt_ptt_end_hook(msg: Dictionary)
## #247：仍在 speaking 的连接断开/同座替换时通知 STT 释放在途流
signal stt_utterance_abort_hook(info: Dictionary)
signal client_message_handled(conn_id: int, kind: String)

var bind_host: String = "127.0.0.1"
var bind_port: int = 0
var token_now_unix: int = -1
var outbound_queue_capacity: int = DEFAULT_QUEUE_CAPACITY
var outbound_send_budget_per_poll: int = OUTBOUND_SEND_BUDGET_PER_POLL
var peer_outbound_buffer_size: int = PEER_OUTBOUND_BUFFER_SIZE
var peer_max_queued_packets: int = PEER_MAX_QUEUED_PACKETS
var peer_flush_high_water: int = PEER_FLUSH_HIGH_WATER

var _tcp: TCPServer = TCPServer.new()
var _verifier: RoomTokenVerifier = RoomTokenVerifier.new()
var _listening: bool = false
var _conns: Dictionary = {}  # cid -> state
var _next_conn_id: int = 1
## room_id -> { seats: {seat -> cid}, game_mode, participants, session_by_seat }
var _rooms: Dictionary = {}
## 权威 Worker：合法 PTT_END 取 server_seq；bootstrap 房间
var _worker: HeadlessWorker = null
## 测试：记录是否曾向 STT 挂点送帧
var _stt_frame_count: int = 0
var _stt_ptt_end_count: int = 0


func configure(secret: String, host: String = "127.0.0.1", port: int = 0) -> bool:
	if not _verifier.set_secret(secret):
		return false
	bind_host = host
	bind_port = port
	return true


func bind_authority_worker(worker: HeadlessWorker) -> void:
	_worker = worker


func start_listen() -> Error:
	if _listening:
		return ERR_ALREADY_IN_USE
	var err: Error = _tcp.listen(bind_port, bind_host)
	if err != OK:
		return err
	_listening = true
	# port=0 时记录 OS 分配端口
	if bind_port == 0:
		bind_port = _tcp.get_local_port()
	return OK


func get_listen_port() -> int:
	if _listening and _tcp.is_listening():
		return _tcp.get_local_port()
	return bind_port


func stop() -> void:
	_listening = false
	for cid in _conns.keys():
		_close_conn(int(cid), true)
	_conns.clear()
	_rooms.clear()
	if _tcp.is_listening():
		_tcp.stop()
	_stt_frame_count = 0
	_stt_ptt_end_count = 0


func _exit_tree() -> void:
	stop()


func is_listening() -> bool:
	return _listening and _tcp.is_listening()


func stt_frame_hook_count() -> int:
	return _stt_frame_count


func stt_ptt_end_hook_count() -> int:
	return _stt_ptt_end_count


func _process(_delta: float) -> void:
	poll()


func poll() -> void:
	if not _listening:
		return
	while _tcp.is_connection_available():
		var stream: StreamPeerTCP = _tcp.take_connection()
		if stream == null:
			break
		var peer := WebSocketPeer.new()
		# accept 前配置有界 peer 出站缓冲（Godot 4.6 WebSocketPeer）
		peer.outbound_buffer_size = peer_outbound_buffer_size
		peer.max_queued_packets = peer_max_queued_packets
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
			"game_mode": "",
			"outbound": VoiceFrameQueue.new(outbound_queue_capacity),
			"inbound": VoiceFrameQueue.new(outbound_queue_capacity),
			"out_seq": 0,
			"active_utterance": "",
			"ptt_speaking": false,
			"utterance_pcm": [],  # Array[PackedByteArray] 短缓冲，不落盘
			"completed_ptt_ends": {},  # utterance_id -> auth_msg（幂等）
			"completed_order": [],  # 有界淘汰顺序
		}
	var to_drop: Array = []
	for cid in _conns.keys():
		var id: int = int(cid)
		if not _poll_conn(id):
			to_drop.append(id)
	for id in to_drop:
		_close_conn(int(id), false)


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
		var pkt: PackedByteArray = peer.get_packet()
		var is_text: bool = peer.was_string_packet()
		_dispatch_packet(cid, pkt, is_text)
	_flush_outbound(cid)
	return true


func _dispatch_packet(cid: int, pkt: PackedByteArray, is_text: bool) -> void:
	if is_text:
		_handle_text(cid, pkt.get_string_from_utf8())
	else:
		_handle_binary(cid, pkt)


func _handle_text(cid: int, text: String) -> void:
	if not _conns.has(cid):
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_send_error(cid, "", "COMMAND_REJECTED", "invalid json")
		return
	var d: Dictionary = parsed
	if not d.has("kind") or typeof(d["kind"]) != TYPE_STRING:
		_send_error(cid, str(d.get("room_id", "")), "COMMAND_REJECTED", "missing kind")
		return
	var kind: String = d["kind"]
	match kind:
		"JOIN":
			_handle_join(cid, d)
		"PTT_START":
			_handle_ptt_start(cid, d)
		"PTT_END":
			_handle_ptt_end(cid, d)
		_:
			_send_error(cid, str(d.get("room_id", "")), "COMMAND_REJECTED", "unknown kind")
	client_message_handled.emit(cid, kind)


func _handle_join(cid: int, d: Dictionary) -> void:
	if not _exact_keys(d, JOIN_KEYS):
		_send_error(cid, str(d.get("room_id", "")), "COMMAND_REJECTED", "invalid JOIN schema")
		return
	if not _is_json_int(d["protocol_version"]) or int(d["protocol_version"]) != 1:
		_send_error(cid, str(d.get("room_id", "")), "PROTOCOL_VERSION_UNSUPPORTED", "version")
		return
	if typeof(d["room_id"]) != TYPE_STRING or typeof(d["room_token"]) != TYPE_STRING:
		_send_error(cid, "", "COMMAND_REJECTED", "bad types")
		return
	if not _is_json_int(d["seat"]):
		_send_error(cid, str(d["room_id"]), "COMMAND_REJECTED", "bad seat type")
		return
	var st: Dictionary = _conns[cid]
	if bool(st.get("joined", false)):
		_send_error(cid, str(st.get("room_id", "")), "COMMAND_REJECTED", "already joined")
		return
	var room_id: String = d["room_id"]
	var seat: int = int(d["seat"])
	var room_token: String = d["room_token"]
	var claims: Dictionary = _verifier.verify(room_token, room_id, seat, token_now_unix)
	if claims.is_empty():
		_send_error(cid, room_id, "UNAUTHORIZED", "room token rejected")
		return
	var game_mode: String = str(claims.get("game_mode", ""))
	# STANDARD 硬拒绝：不创建/不保留语音房间状态
	if game_mode != "TRASH_TALK":
		_send_error(cid, room_id, "UNAUTHORIZED", "voice only for TRASH_TALK")
		return
	var session_id: String = str(claims.get("session_id", ""))
	var participants: Array = claims.get("participants", []) as Array
	if seat < 0 or seat > 3:
		_send_error(cid, room_id, "UNAUTHORIZED", "invalid seat")
		return
	if seat >= participants.size() or str(participants[seat]) != "HUMAN":
		_send_error(cid, room_id, "UNAUTHORIZED", "AI seat cannot join voice")
		return
	# 确保牌局权威房间存在（供 PTT_END server_seq）
	if _worker != null:
		var boot: Dictionary = _worker.ensure_room_from_claims(claims)
		if not bool(boot.get("ok", false)):
			_send_error(cid, room_id, "COMMAND_REJECTED", str(boot.get("message", "bootstrap")))
			return
	_register_room_seat(room_id, seat, cid, session_id, game_mode, participants)
	st["joined"] = true
	st["room_id"] = room_id
	st["seat"] = seat
	st["session_id"] = session_id
	st["game_mode"] = game_mode
	_conns[cid] = st
	_send_json(cid, {
		"protocol_version": 1,
		"room_id": room_id,
		"kind": "VOICE_JOINED",
		"seat": seat,
	})


func _register_room_seat(
	room_id: String,
	seat: int,
	cid: int,
	session_id: String,
	game_mode: String,
	participants: Array
) -> void:
	if not _rooms.has(room_id):
		_rooms[room_id] = {
			"seats": {},  # seat -> cid
			"session_by_seat": {},
			"game_mode": game_mode,
			"participants": participants.duplicate(),
		}
	var rm: Dictionary = _rooms[room_id]
	var seats: Dictionary = rm["seats"]
	# 同座替换：断开旧连接
	if seats.has(seat):
		var old_cid: int = int(seats[seat])
		if old_cid != cid and _conns.has(old_cid):
			_close_conn(old_cid, true)
	seats[seat] = cid
	(rm["session_by_seat"] as Dictionary)[seat] = session_id
	rm["seats"] = seats
	_rooms[room_id] = rm


func _handle_ptt_start(cid: int, d: Dictionary) -> void:
	var st: Dictionary = _conns.get(cid, {})
	if not bool(st.get("joined", false)):
		_send_error(cid, str(d.get("room_id", "")), "UNAUTHORIZED", "not joined")
		return
	var gate: Dictionary = _validate_client_ptt_control(st, d, "PTT_START")
	if not bool(gate.get("ok", false)):
		_send_error(cid, str(st.get("room_id", "")), str(gate.get("code", "COMMAND_REJECTED")), str(gate.get("message", "")))
		return
	var room_id: String = str(st.get("room_id", ""))
	# #247：CLOSING/终态后关闭新语音；由 Worker 读 RewardWindow 权威 phase
	if _worker != null and _worker.has_method("voice_accepts_new_utterance"):
		if not bool(_worker.voice_accepts_new_utterance(room_id)):
			_send_error(cid, room_id, "COMMAND_REJECTED", "voice closed for window phase")
			return
	var utt: String = String(d["utterance_id"])
	# 已在 speaking：禁止重复 START 重置缓冲逃逸
	if bool(st.get("ptt_speaking", false)):
		_send_error(cid, str(st.get("room_id", "")), "COMMAND_REJECTED", "already speaking")
		return
	# 仍在 completed 缓存中的 utterance_id 禁止复用（避免旧 END 幂等污染新会话）
	var completed0: Dictionary = st.get("completed_ptt_ends", {}) as Dictionary
	if completed0.has(utt):
		_send_error(cid, str(st.get("room_id", "")), "COMMAND_REJECTED", "utterance id completed")
		return
	st["active_utterance"] = utt
	st["ptt_speaking"] = true
	st["utterance_pcm"] = []
	var inbound: VoiceFrameQueue = st.get("inbound") as VoiceFrameQueue
	if inbound != null:
		inbound.clear()
	_conns[cid] = st
	var out_msg := {
		"protocol_version": 1,
		"room_id": room_id,
		"seat": int(st["seat"]),
		"kind": "PTT_START",
		"utterance_id": utt,
	}
	_broadcast_control_to_others(room_id, int(st["seat"]), out_msg)


func _handle_ptt_end(cid: int, d: Dictionary) -> void:
	var st: Dictionary = _conns.get(cid, {})
	if not bool(st.get("joined", false)):
		_send_error(cid, str(d.get("room_id", "")), "UNAUTHORIZED", "not joined")
		return
	var gate: Dictionary = _validate_client_ptt_control(st, d, "PTT_END")
	if not bool(gate.get("ok", false)):
		_send_error(cid, str(st.get("room_id", "")), str(gate.get("code", "COMMAND_REJECTED")), str(gate.get("message", "")))
		return
	var utt: String = String(d["utterance_id"])
	var room_id: String = str(st["room_id"])
	var seat: int = int(st["seat"])
	var session_id: String = str(st["session_id"])
	# 幂等：同 utterance 已完成则回送首次权威结果，不二次 alloc / STT
	var completed: Dictionary = st.get("completed_ptt_ends", {}) as Dictionary
	if completed.has(utt):
		var prev: Dictionary = completed[utt] as Dictionary
		_send_json(cid, prev.duplicate(true))
		return
	if not bool(st.get("ptt_speaking", false)) or String(st.get("active_utterance", "")) != utt:
		_send_error(cid, room_id, "COMMAND_REJECTED", "no matching active ptt")
		return
	if _worker == null:
		_send_error(cid, room_id, "COMMAND_REJECTED", "no authority worker")
		_clear_utterance_buffer(cid)
		return
	var auth: Dictionary = _worker.allocate_ptt_end_authority(room_id, seat, session_id, utt)
	if not bool(auth.get("ok", false)):
		_send_error(
			cid,
			room_id,
			str(auth.get("code", "COMMAND_REJECTED")),
			str(auth.get("message", "ptt end rejected"))
		)
		_clear_utterance_buffer(cid)
		return
	var server_seq: int = int(auth.get("server_seq", 0))
	var auth_msg := {
		"protocol_version": 1,
		"room_id": room_id,
		"seat": seat,
		"kind": "PTT_END",
		"utterance_id": utt,
		"server_seq": server_seq,
	}
	completed[utt] = auth_msg.duplicate(true)
	var order: Array = st.get("completed_order", []) as Array
	order.append(utt)
	while order.size() > MAX_COMPLETED_PTT_ENDS:
		var old_id: String = str(order.pop_front())
		completed.erase(old_id)
	st["completed_order"] = order
	st["completed_ptt_ends"] = completed
	st["ptt_speaking"] = false
	st["active_utterance"] = ""
	st["utterance_pcm"] = []
	var inbound2: VoiceFrameQueue = st.get("inbound") as VoiceFrameQueue
	if inbound2 != null:
		inbound2.clear()
	_conns[cid] = st
	_send_json(cid, auth_msg)
	_broadcast_control_to_others(room_id, seat, auth_msg)
	_stt_ptt_end_count += 1
	stt_ptt_end_hook.emit(auth_msg.duplicate(true))


func _handle_binary(cid: int, raw: PackedByteArray) -> void:
	var st: Dictionary = _conns.get(cid, {})
	if not bool(st.get("joined", false)):
		return
	var room_id: String = str(st.get("room_id", ""))
	var bound_seat: int = int(st.get("seat", -1))
	var session_id: String = str(st.get("session_id", ""))
	# 必须已 PTT_START 且 speaking
	if not bool(st.get("ptt_speaking", false)):
		_send_error(cid, room_id, "COMMAND_REJECTED", "pcm without ptt start")
		return
	var decoded: Dictionary = VoiceBinaryCodec.decode_frame(raw)
	if decoded.is_empty():
		_send_error(cid, room_id, "COMMAND_REJECTED", "bad voice frame")
		return
	if int(decoded.get("seat", -1)) != bound_seat:
		_send_error(cid, room_id, "UNAUTHORIZED", "seat mismatch")
		return
	var utt: String = String(decoded.get("utterance_id", ""))
	if utt != String(st.get("active_utterance", "")):
		_send_error(cid, room_id, "COMMAND_REJECTED", "utterance mismatch")
		return
	var frame: Dictionary = VoiceBinaryCodec.to_voice_port_frame(decoded, room_id, session_id)
	if frame.is_empty():
		_send_error(cid, room_id, "COMMAND_REJECTED", "rebuild failed")
		return
	var inbound: VoiceFrameQueue = st["inbound"] as VoiceFrameQueue
	var push_r: Dictionary = inbound.push(frame)
	if not bool(push_r.get("ok", false)):
		return
	var buf: Array = st.get("utterance_pcm", []) as Array
	buf.append((frame["pcm"] as PackedByteArray).duplicate())
	while buf.size() > outbound_queue_capacity:
		buf.pop_front()
	st["utterance_pcm"] = buf
	_conns[cid] = st
	_stt_frame_count += 1
	stt_frame_hook.emit(frame.duplicate(true))
	_broadcast_binary_to_others(room_id, bound_seat, raw)


func _broadcast_control_to_others(room_id: String, from_seat: int, msg: Dictionary) -> void:
	if not _rooms.has(room_id):
		return
	var seats: Dictionary = (_rooms[room_id] as Dictionary).get("seats", {})
	for s in seats.keys():
		var seat: int = int(s)
		if seat == from_seat:
			continue
		if not _is_human_seat(room_id, seat):
			continue
		var tid: int = int(seats[s])
		_send_json(tid, msg)


## #247：向房间全部当前 HUMAN 成员广播控制帧（字幕 partial/final；不跨房）。
func broadcast_control_to_room(room_id: String, msg: Dictionary) -> void:
	if not _rooms.has(room_id):
		return
	var seats: Dictionary = (_rooms[room_id] as Dictionary).get("seats", {})
	for s in seats.keys():
		var seat: int = int(s)
		if not _is_human_seat(room_id, seat):
			continue
		var tid: int = int(seats[s])
		_send_json(tid, msg)


func _broadcast_binary_to_others(room_id: String, from_seat: int, raw: PackedByteArray) -> void:
	if not _rooms.has(room_id):
		return
	var seats: Dictionary = (_rooms[room_id] as Dictionary).get("seats", {})
	for s in seats.keys():
		var seat: int = int(s)
		if seat == from_seat:
			continue
		if not _is_human_seat(room_id, seat):
			continue
		var tid: int = int(seats[s])
		_enqueue_binary(tid, raw)


func _is_human_seat(room_id: String, seat: int) -> bool:
	if not _rooms.has(room_id):
		return false
	var parts: Array = (_rooms[room_id] as Dictionary).get("participants", []) as Array
	if seat < 0 or seat >= parts.size():
		return false
	return str(parts[seat]) == "HUMAN"


func _enqueue_binary(cid: int, raw: PackedByteArray) -> void:
	if not _conns.has(cid):
		return
	var st: Dictionary = _conns[cid]
	var q: VoiceFrameQueue = st["outbound"] as VoiceFrameQueue
	# 有界出站：满则 VoiceFrameQueue 丢最旧；不在此处一次排空 peer
	var seq: int = int(st.get("out_seq", 0))
	st["out_seq"] = seq + 1
	var outbound_item := {
		"utterance_id": "_bin",
		"frame_seq": seq,
		"_raw": raw,
	}
	q.push(outbound_item)
	_conns[cid] = st
	# 不立即 flush 全部；由 poll 预算发送，使慢接收方队列积压可见


func _flush_outbound(cid: int) -> void:
	if not _conns.has(cid):
		return
	var st: Dictionary = _conns[cid]
	var peer: WebSocketPeer = st.get("peer") as WebSocketPeer
	if peer == null or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var q: VoiceFrameQueue = st["outbound"] as VoiceFrameQueue
	var budget: int = maxi(1, outbound_send_budget_per_poll)
	var sent: int = 0
	while q.size() > 0 and sent < budget:
		# peer 内部缓冲高压：停止灌包，帧留在有界应用队列
		var buffered: int = peer.get_current_outbound_buffered_amount()
		if buffered >= peer_flush_high_water:
			break
		var item: Dictionary = q.peek()
		if item.is_empty():
			break
		var put_ok := false
		if item.has("_raw") and item["_raw"] is PackedByteArray:
			var err: Error = peer.put_packet(item["_raw"] as PackedByteArray)
			put_ok = (err == OK)
		elif item.has("_text"):
			var err2: Error = peer.send_text(str(item["_text"]))
			put_ok = (err2 == OK)
		else:
			q.pop()
			continue
		if not put_ok:
			# 失败不当作已发送：保留队头
			break
		q.pop()
		sent += 1


func _send_json(cid: int, obj: Variant) -> void:
	if not _conns.has(cid):
		return
	var st: Dictionary = _conns[cid]
	var peer: WebSocketPeer = st.get("peer") as WebSocketPeer
	if peer == null:
		# 测试桩
		if not st.has("outbox"):
			st["outbox"] = []
		(st["outbox"] as Array).append(obj)
		_conns[cid] = st
		return
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	peer.send_text(JSON.stringify(obj))


func _send_error(cid: int, room_id: String, code: String, message: String) -> void:
	var body := {
		"protocol_version": 1,
		"room_id": room_id,
		"kind": CONTROL_ERROR_KIND,
		"request_id": null,
		"command_id": null,
		"code": code,
		"message": message,
	}
	# ERROR 无 server_seq / view_hash
	_send_json(cid, body)


func _clear_utterance_buffer(cid: int) -> void:
	if not _conns.has(cid):
		return
	var st: Dictionary = _conns[cid]
	st["active_utterance"] = ""
	st["ptt_speaking"] = false
	st["utterance_pcm"] = []
	var inbound: VoiceFrameQueue = st.get("inbound") as VoiceFrameQueue
	if inbound != null:
		inbound.clear()
	_conns[cid] = st


## 客户端 PTT 控制 exact schema + 绑定 + 权威字段门控。
func _validate_client_ptt_control(st: Dictionary, d: Dictionary, expect_kind: String) -> Dictionary:
	if _has_authority_fields(d):
		return {"ok": false, "code": "FORGERY_REJECTED", "message": "authority fields forbidden"}
	if not _exact_keys(d, PTT_CLIENT_KEYS):
		return {"ok": false, "code": "COMMAND_REJECTED", "message": "invalid ptt schema"}
	if str(d.get("kind", "")) != expect_kind:
		return {"ok": false, "code": "COMMAND_REJECTED", "message": "kind mismatch"}
	if not _is_json_int(d.get("protocol_version", null)) or int(d["protocol_version"]) != 1:
		return {"ok": false, "code": "PROTOCOL_VERSION_UNSUPPORTED", "message": "version"}
	if typeof(d.get("room_id", null)) != TYPE_STRING or typeof(d.get("session_id", null)) != TYPE_STRING:
		return {"ok": false, "code": "COMMAND_REJECTED", "message": "bad types"}
	if not _is_json_int(d.get("seat", null)):
		return {"ok": false, "code": "COMMAND_REJECTED", "message": "bad seat"}
	if typeof(d.get("utterance_id", null)) != TYPE_STRING or String(d["utterance_id"]).is_empty():
		return {"ok": false, "code": "COMMAND_REJECTED", "message": "empty utterance"}
	if str(d["room_id"]) != str(st.get("room_id", "")):
		return {"ok": false, "code": "UNAUTHORIZED", "message": "room mismatch"}
	if str(d["session_id"]) != str(st.get("session_id", "")):
		return {"ok": false, "code": "UNAUTHORIZED", "message": "session mismatch"}
	if int(d["seat"]) != int(st.get("seat", -1)):
		return {"ok": false, "code": "UNAUTHORIZED", "message": "seat mismatch"}
	return {"ok": true, "code": "", "message": ""}


## 只读观测：出站应用层队列长度 / 丢帧（生产逻辑不依赖测试桩）
func conn_outbound_queue_size(cid: int) -> int:
	if not _conns.has(cid):
		return -1
	var q: VoiceFrameQueue = (_conns[cid] as Dictionary).get("outbound") as VoiceFrameQueue
	return 0 if q == null else q.size()


func conn_outbound_dropped_count(cid: int) -> int:
	if not _conns.has(cid):
		return -1
	var q: VoiceFrameQueue = (_conns[cid] as Dictionary).get("outbound") as VoiceFrameQueue
	return 0 if q == null else q.dropped_count()


func conn_peer_outbound_buffered(cid: int) -> int:
	if not _conns.has(cid):
		return -1
	var peer: WebSocketPeer = (_conns[cid] as Dictionary).get("peer") as WebSocketPeer
	if peer == null:
		return -1
	return peer.get_current_outbound_buffered_amount()


func conn_completed_ptt_count(cid: int) -> int:
	if not _conns.has(cid):
		return -1
	var completed: Dictionary = (_conns[cid] as Dictionary).get("completed_ptt_ends", {}) as Dictionary
	return completed.size()


## 测试/诊断：按 seat 查当前 voice cid
func conn_id_for_seat(room_id: String, seat: int) -> int:
	if not _rooms.has(room_id):
		return -1
	var seats: Dictionary = (_rooms[room_id] as Dictionary).get("seats", {})
	if not seats.has(seat):
		return -1
	return int(seats[seat])


func _close_conn(cid: int, _supersede: bool) -> void:
	if not _conns.has(cid):
		return
	var st: Dictionary = _conns[cid]
	var room_id: String = str(st.get("room_id", ""))
	var seat: int = int(st.get("seat", -1))
	# #247：speaking 中断 → 通知 STT 释放在途 stream（不跨房）
	if bool(st.get("ptt_speaking", false)):
		var utt_abort := str(st.get("active_utterance", ""))
		if not room_id.is_empty() and not utt_abort.is_empty() and seat >= 0:
			stt_utterance_abort_hook.emit({
				"room_id": room_id,
				"seat": seat,
				"utterance_id": utt_abort,
			})
	_clear_utterance_buffer(cid)
	if not room_id.is_empty() and _rooms.has(room_id):
		var rm: Dictionary = _rooms[room_id]
		var seats: Dictionary = rm.get("seats", {})
		if seats.has(seat) and int(seats[seat]) == cid:
			seats.erase(seat)
		var sess: Dictionary = rm.get("session_by_seat", {})
		if sess.has(seat):
			sess.erase(seat)
		rm["seats"] = seats
		rm["session_by_seat"] = sess
		if seats.is_empty():
			_rooms.erase(room_id)
		else:
			_rooms[room_id] = rm
	var peer: WebSocketPeer = st.get("peer") as WebSocketPeer
	if peer != null:
		peer.close()
	_conns.erase(cid)


func _bind_matches(st: Dictionary, d: Dictionary) -> bool:
	if d.has("room_id") and str(d["room_id"]) != str(st.get("room_id", "")):
		return false
	if d.has("seat") and int(d["seat"]) != int(st.get("seat", -1)):
		return false
	if d.has("session_id") and str(d["session_id"]) != str(st.get("session_id", "")):
		return false
	return true


func _has_authority_fields(d: Dictionary) -> bool:
	for k in AUTHORITY_FIELD_KEYS:
		if d.has(k):
			return true
	return false


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
		return f == floor(f)
	return false


## 测试：当前房间活跃语音连接数
func room_voice_conn_count(room_id: String) -> int:
	if not _rooms.has(room_id):
		return 0
	return ((_rooms[room_id] as Dictionary).get("seats", {}) as Dictionary).size()


## 测试：连接是否仍有 utterance 短缓冲
func conn_utterance_buffer_size(cid: int) -> int:
	if not _conns.has(cid):
		return -1
	var buf: Array = (_conns[cid] as Dictionary).get("utterance_pcm", []) as Array
	return buf.size()


## 测试：是否仍持有房间语音状态
func has_room_voice_state(room_id: String) -> bool:
	return _rooms.has(room_id)
