class_name VoiceRelayClient
extends Node

# E4-02（#244）：公共场语音 WebSocket 客户端。
# 将 VoicePortModule 出站控制/PCM 送往独立语音中继；远端帧重建后 ingest。
# JOIN 每连接仅一次；断开释放 VoicePort；侧通道序号经 AuthoritySeqBridge。
# 网络端到端未验证。

signal connected()
signal disconnected()
signal join_result(ok: bool, msg: Dictionary)
signal authority_ptt_end(msg: Dictionary)
signal error_received(msg: Dictionary)
## #247：房间字幕（已 schema/room 校验；不触发奖励）
signal transcript_caption(msg: Dictionary)

var _peer: WebSocketPeer = WebSocketPeer.new()
var _port: VoicePortModule = null
var _bridge: AuthoritySeqBridge = null
var _url: String = ""
var _room_id: String = ""
var _seat: int = -1
var _session_id: String = ""
var _room_token: String = ""
var _joined: bool = false
var _want_connected: bool = false
var _join_sent: bool = false
var _disconnect_emitted: bool = false


func bind_voice_port(port: VoicePortModule) -> void:
	if _port != null:
		if _port.outbound_control.is_connected(_on_outbound_control):
			_port.outbound_control.disconnect(_on_outbound_control)
		if _port.outbound_frame.is_connected(_on_outbound_frame):
			_port.outbound_frame.disconnect(_on_outbound_frame)
	_port = port
	if _port != null:
		if not _port.outbound_control.is_connected(_on_outbound_control):
			_port.outbound_control.connect(_on_outbound_control)
		if not _port.outbound_frame.is_connected(_on_outbound_frame):
			_port.outbound_frame.connect(_on_outbound_frame)


func bind_authority_seq_bridge(bridge: AuthoritySeqBridge) -> void:
	_bridge = bridge


func connect_voice(
	url: String,
	room_id: String,
	seat: int,
	session_id: String,
	room_token: String
) -> Error:
	_url = url
	_room_id = room_id
	_seat = seat
	_session_id = session_id
	_room_token = room_token
	_joined = false
	_join_sent = false
	_want_connected = true
	_disconnect_emitted = false
	_peer = WebSocketPeer.new()
	return _peer.connect_to_url(url)


func disconnect_voice() -> void:
	_want_connected = false
	_joined = false
	_join_sent = false
	if _peer != null:
		_peer.close()
		_peer = null
	_release_local_voice()
	_emit_disconnected_once()


func _exit_tree() -> void:
	disconnect_voice()


func is_joined() -> bool:
	return _joined


func join_sent() -> bool:
	return _join_sent


func poll() -> void:
	if _peer == null:
		return
	_peer.poll()
	var st: int = _peer.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _joined and _want_connected and not _join_sent and not _room_token.is_empty():
			_send_join()
			_join_sent = true
		while _peer.get_available_packet_count() > 0:
			var pkt: PackedByteArray = _peer.get_packet()
			var is_text: bool = _peer.was_string_packet()
			if is_text:
				_handle_text(pkt.get_string_from_utf8())
			else:
				_handle_binary(pkt)
	elif st == WebSocketPeer.STATE_CLOSED:
		if _want_connected or _joined or _join_sent:
			_joined = false
			_want_connected = false
			_join_sent = false
			_release_local_voice()
			_emit_disconnected_once()


func _process(_delta: float) -> void:
	poll()


func _send_join() -> void:
	var msg := {
		"protocol_version": 1,
		"kind": "JOIN",
		"room_id": _room_id,
		"seat": _seat,
		"room_token": _room_token,
	}
	_peer.send_text(JSON.stringify(msg))


func _on_outbound_control(msg: Dictionary) -> void:
	if not _joined or _peer == null:
		return
	if _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var out: Dictionary = msg.duplicate(true)
	for k in [
		"server_seq", "server_seq_ref", "view_hash", "status", "error_code",
		"ptt_end_server_seq", "closing_boundary_server_seq", "grace_deadline_at",
		"state_hash", "full_state_hash",
	]:
		out.erase(k)
	_peer.send_text(JSON.stringify(out))


func _on_outbound_frame(frame: Dictionary) -> void:
	if not _joined or _peer == null:
		return
	if _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var raw: PackedByteArray = VoiceBinaryCodec.encode_from_voice_port_frame(frame)
	if raw.is_empty():
		return
	_peer.put_packet(raw)


func _handle_text(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	var kind: String = str(d.get("kind", ""))
	match kind:
		"VOICE_JOINED":
			_joined = true
			if _port != null:
				_port.bind_public_identity(_room_id, _session_id, _seat)
			connected.emit()
			join_result.emit(true, d)
		"PTT_END":
			if d.has("server_seq"):
				if _bridge != null:
					_bridge.on_side_channel_authority_seq(int(d["server_seq"]))
				authority_ptt_end.emit(d)
		"ERROR":
			# 已成功 VOICE_JOINED 后的 ERROR（如 already joined）不得伪装 join failure
			if not _joined:
				join_result.emit(false, d)
			error_received.emit(d)
		"PTT_START":
			pass
		"TRANSCRIPT_PARTIAL", "TRANSCRIPT_FINAL":
			if _joined and _accept_transcript_msg(d):
				transcript_caption.emit(d.duplicate(true))
		_:
			pass


## 仅接受本房字幕；严格基础 schema，拒绝跨房/缺字段。
func _accept_transcript_msg(d: Dictionary) -> bool:
	if not _is_json_int(d.get("protocol_version", null)) or int(d["protocol_version"]) != 1:
		return false
	if str(d.get("room_id", "")) != _room_id or _room_id.is_empty():
		return false
	if not _is_json_int(d.get("seat", null)):
		return false
	var s: int = int(d["seat"])
	if s < 0 or s > 3:
		return false
	if str(d.get("utterance_id", "")).strip_edges().is_empty():
		return false
	if str(d.get("window_id", "")).strip_edges().is_empty():
		return false
	if not _is_json_int(d.get("hand_seq", null)):
		return false
	var src := str(d.get("source", ""))
	var kind := str(d.get("kind", ""))
	# #248：partial 仅 faster_whisper；final 可 faster_whisper 或 new_api；其它组合拒绝。
	if kind == "TRANSCRIPT_PARTIAL":
		if src != "faster_whisper":
			return false
		if bool(d.get("is_final", true)):
			return false
	elif kind == "TRANSCRIPT_FINAL":
		if src != "faster_whisper" and src != "new_api":
			return false
		if not bool(d.get("is_final", false)):
			return false
		if not _is_json_int(d.get("ptt_end_server_seq", null)) or int(d["ptt_end_server_seq"]) <= 0:
			return false
	else:
		return false
	if typeof(d.get("text", null)) != TYPE_STRING and typeof(d.get("text", null)) != TYPE_STRING_NAME:
		return false
	if typeof(d.get("lang", null)) != TYPE_STRING and typeof(d.get("lang", null)) != TYPE_STRING_NAME:
		return false
	return true


## JSON 整型：Godot JSON 可能把整数解为 float，仅接受整值 float，拒绝 1.5。
func _is_json_int(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		var f: float = float(v)
		return f == floorf(f)
	return false


func _handle_binary(raw: PackedByteArray) -> void:
	if _port == null:
		return
	var decoded: Dictionary = VoiceBinaryCodec.decode_frame(raw)
	if decoded.is_empty():
		return
	var frame: Dictionary = VoiceBinaryCodec.to_voice_port_frame(decoded, _room_id, _session_id)
	if frame.is_empty():
		return
	_port.ingest_remote_audio_frame(frame)


func _release_local_voice() -> void:
	if _port != null:
		_port.release_all()


func _emit_disconnected_once() -> void:
	if _disconnect_emitted:
		return
	_disconnect_emitted = true
	disconnected.emit()
