class_name SttServiceClient
extends Node

# #247：JSON STT 客户端；有界传输重连（非 RewardWindow 时钟）。

signal connected()
signal disconnected()
signal transcript_partial(msg: Dictionary)
signal transcript_final(msg: Dictionary)
signal utterance_failed(msg: Dictionary)
signal protocol_error(msg: Dictionary)

const PROTOCOL_VERSION: int = 1
const RECONNECT_BASE_MS: int = 200
const RECONNECT_MAX_MS: int = 5000
const RECONNECT_MAX_ATTEMPTS: int = 32

var _peer: WebSocketPeer = WebSocketPeer.new()
var _url: String = ""
var _want: bool = false
var _opened: bool = false
var _reconnect_attempt: int = 0
var _next_reconnect_at_ms: int = 0
var _reconnect_clock_ms: int = -1  # test inject; -1 = Time.get_ticks_msec()


func connect_stt(url: String) -> Error:
	_url = url.strip_edges()
	_want = true
	_opened = false
	_reconnect_attempt = 0
	_next_reconnect_at_ms = 0
	return _connect_now()


func disconnect_stt() -> void:
	_want = false
	_opened = false
	_reconnect_attempt = 0
	if _peer != null:
		_peer.close()
	_peer = WebSocketPeer.new()


func is_stt_open() -> bool:
	if _test_send_ok and _opened:
		return true
	return _opened and _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN


func set_reconnect_clock_ms_for_test(ms: int) -> void:
	_reconnect_clock_ms = ms


var _test_send_ok: bool = false


## 测试：强制标记 transport OPEN（不经真实 WS）；可选假发送成功。
func force_open_for_test(send_ok: bool = true) -> void:
	_want = true
	_opened = true
	_test_send_ok = send_ok


func force_closed_for_test() -> void:
	_opened = false
	_want = true
	_test_send_ok = false


func poll() -> void:
	if _peer == null:
		_peer = WebSocketPeer.new()
	_peer.poll()
	var st: int = _peer.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _opened:
			_opened = true
			_reconnect_attempt = 0
			connected.emit()
		while _peer.get_available_packet_count() > 0:
			_on_packet(_peer.get_packet())
	elif st == WebSocketPeer.STATE_CLOSED:
		if _opened:
			_opened = false
			disconnected.emit()
		if _want:
			_maybe_reconnect()
	elif st == WebSocketPeer.STATE_CONNECTING:
		pass
	elif st == WebSocketPeer.STATE_CLOSING:
		pass


func send_start(room_id: String, seat: int, hand_seq: int, window_id: String, utterance_id: String) -> bool:
	return _send_json({
		"protocol_version": PROTOCOL_VERSION, "kind": "UTTERANCE_START",
		"room_id": room_id, "seat": seat, "hand_seq": hand_seq,
		"window_id": window_id, "utterance_id": utterance_id,
	})


func send_audio_chunk(
	room_id: String, seat: int, hand_seq: int, window_id: String,
	utterance_id: String, pcm: PackedByteArray, want_partial: bool = false
) -> bool:
	if pcm.is_empty():
		return false
	return _send_json({
		"protocol_version": PROTOCOL_VERSION, "kind": "AUDIO_CHUNK",
		"room_id": room_id, "seat": seat, "hand_seq": hand_seq,
		"window_id": window_id, "utterance_id": utterance_id,
		"pcm_b64": Marshalls.raw_to_base64(pcm), "want_partial": want_partial,
	})


func send_commit(
	room_id: String, seat: int, hand_seq: int, window_id: String,
	utterance_id: String, ptt_end_server_seq: int
) -> bool:
	return _send_json({
		"protocol_version": PROTOCOL_VERSION, "kind": "UTTERANCE_COMMIT",
		"room_id": room_id, "seat": seat, "hand_seq": hand_seq,
		"window_id": window_id, "utterance_id": utterance_id,
		"ptt_end_server_seq": ptt_end_server_seq,
	})


func send_utterance_cancel(
	room_id: String, seat: int, hand_seq: int, window_id: String, utterance_id: String
) -> bool:
	return _send_json({
		"protocol_version": PROTOCOL_VERSION, "kind": "UTTERANCE_CANCEL",
		"room_id": room_id, "seat": seat, "hand_seq": hand_seq,
		"window_id": window_id, "utterance_id": utterance_id,
	})


func send_window_cancel(room_id: String, hand_seq: int, window_id: String) -> bool:
	return _send_json({
		"protocol_version": PROTOCOL_VERSION, "kind": "WINDOW_CANCEL",
		"room_id": room_id, "hand_seq": hand_seq, "window_id": window_id,
	})


func _connect_now() -> Error:
	if _url.is_empty():
		return ERR_INVALID_PARAMETER
	_peer = WebSocketPeer.new()
	return _peer.connect_to_url(_url)


func _now_ms() -> int:
	if _reconnect_clock_ms >= 0:
		return _reconnect_clock_ms
	return Time.get_ticks_msec()


func _maybe_reconnect() -> void:
	if not _want or _url.is_empty():
		return
	if _reconnect_attempt >= RECONNECT_MAX_ATTEMPTS:
		return
	var now: int = _now_ms()
	if now < _next_reconnect_at_ms:
		return
	var delay: int = mini(RECONNECT_MAX_MS, RECONNECT_BASE_MS * int(pow(2.0, float(mini(_reconnect_attempt, 8)))))
	_reconnect_attempt += 1
	_next_reconnect_at_ms = now + delay
	_connect_now()


func _send_json(msg: Dictionary) -> bool:
	if not is_stt_open():
		return false
	if _test_send_ok:
		return true
	return _peer.send_text(JSON.stringify(msg)) == OK


func _on_packet(pkt: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(pkt.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var msg: Dictionary = parsed as Dictionary
	match str(msg.get("kind", "")):
		"TRANSCRIPT_PARTIAL":
			transcript_partial.emit(msg)
		"TRANSCRIPT_FINAL":
			transcript_final.emit(msg)
		"UTTERANCE_FAILED":
			utterance_failed.emit(msg)
		"ERROR":
			protocol_error.emit(msg)
		_:
			pass
