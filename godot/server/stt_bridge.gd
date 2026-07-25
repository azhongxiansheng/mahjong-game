class_name SttBridge
extends Node

# #247 r5：流式 STT 桥。partial/final 仅在权威准入后广播；
# 代际 room|hand_seq|window_id；deadline 使用 #252 RewardWindow 权威时钟；
# 仅 OPEN 续传；transport 未就绪/失败 drop 至 PTT_END；断线不截断续传。
# 网络 e2e 未验证。

signal transcript_partial_broadcast(msg: Dictionary)
signal transcript_final_broadcast(msg: Dictionary)
signal utterance_terminalized(room_id: String, seat: int, utterance_id: String, reason: String)

const MAX_PCM_BYTES: int = 960000
const MAX_BUFFERED_UTTERANCES: int = 16
const MAX_CANCEL_TOMBSTONES: int = 64
const MAX_OVERFLOW_TOMBSTONES: int = 64
const MAX_DROP_TOMBSTONES: int = 64
const PROTOCOL_VERSION: int = 1
const SOURCE_FASTER_WHISPER := "faster_whisper"
const SOURCE_NEW_API := "new_api"
const PARTIAL_EVERY_N_FRAMES: int = 10

var _worker: HeadlessWorker = null
var _client: SttServiceClient = null
var _stt_url: String = ""

var _streams: Dictionary = {}  # ukey -> stream
var _pending: Dictionary = {}  # ukey -> frozen ctx
## gen_key -> { cancelled:true, sent:true } 有界代际 tombstone
var _gen_tombstones: Dictionary = {}
var _gen_order: Array = []
var _overflowed: Dictionary = {}  # ukey -> true
var _overflow_order: Array = []
## 丢弃至权威 PTT_END 的 utterance（禁止截断重传）；有界
var _drop_until_end: Dictionary = {}
var _drop_order: Array = []

var frames_accepted: int = 0
var ends_accepted: int = 0
var finals_ingested: int = 0
var partials_broadcast: int = 0
var finals_broadcast: int = 0
var last_ingest_result: Dictionary = {}
var last_reject_reason: String = ""
var last_broadcast_count: int = 0
## 观测：向 Python 发出的 cancel 次数（含 window/utt）
var cancels_sent: int = 0


func configure(worker: HeadlessWorker, stt_url: String) -> void:
	_worker = worker
	_stt_url = stt_url.strip_edges()
	if _client != null:
		_teardown_client()
	if _stt_url.is_empty():
		return
	_client = SttServiceClient.new()
	add_child(_client)
	_client.transcript_partial.connect(_on_stt_partial)
	_client.transcript_final.connect(_on_stt_final)
	_client.utterance_failed.connect(_on_stt_failed)
	if not _client.disconnected.is_connected(_on_stt_disconnected):
		_client.disconnected.connect(_on_stt_disconnected)
	_client.connect_stt(_stt_url)


func bind_voice_relay(relay: VoiceRelayServer) -> void:
	if relay == null:
		return
	if not relay.stt_frame_hook.is_connected(_on_stt_frame):
		relay.stt_frame_hook.connect(_on_stt_frame)
	if not relay.stt_ptt_end_hook.is_connected(_on_stt_ptt_end):
		relay.stt_ptt_end_hook.connect(_on_stt_ptt_end)
	if relay.has_signal("stt_utterance_abort_hook") \
			and not relay.stt_utterance_abort_hook.is_connected(_on_stt_utterance_abort):
		relay.stt_utterance_abort_hook.connect(_on_stt_utterance_abort)


func unbind_voice_relay(relay: VoiceRelayServer) -> void:
	if relay == null:
		return
	if relay.stt_frame_hook.is_connected(_on_stt_frame):
		relay.stt_frame_hook.disconnect(_on_stt_frame)
	if relay.stt_ptt_end_hook.is_connected(_on_stt_ptt_end):
		relay.stt_ptt_end_hook.disconnect(_on_stt_ptt_end)
	if relay.has_signal("stt_utterance_abort_hook") \
			and relay.stt_utterance_abort_hook.is_connected(_on_stt_utterance_abort):
		relay.stt_utterance_abort_hook.disconnect(_on_stt_utterance_abort)


func stop() -> void:
	_teardown_client()
	_streams.clear()
	_pending.clear()
	_gen_tombstones.clear()
	_gen_order.clear()
	_overflowed.clear()
	_overflow_order.clear()
	_drop_until_end.clear()
	_drop_order.clear()


func poll() -> void:
	if _client != null:
		_client.poll()
	_reconcile_streams_with_live()
	_tick_deadlines()


## 测试：挂接假 client（默认 CLOSED），用于 P1-2 初始不可用。
func attach_test_client_closed() -> void:
	_teardown_client()
	_client = SttServiceClient.new()
	add_child(_client)
	_client.force_closed_for_test()
	if not _client.disconnected.is_connected(_on_stt_disconnected):
		_client.disconnected.connect(_on_stt_disconnected)


func force_test_client_open(send_ok: bool = true) -> void:
	if _client == null:
		attach_test_client_closed()
	_client.force_open_for_test(send_ok)


func is_drop_until_end(room_id: String, seat: int, utterance_id: String) -> bool:
	return _drop_until_end.has(_utt_key(room_id, seat, utterance_id))


func get_drop_tombstone_count() -> int:
	return _drop_until_end.size()


func cancel_window_generation(room_id: String, hand_seq: int, window_id: String) -> void:
	var rid := room_id.strip_edges()
	var wid := window_id.strip_edges()
	if rid.is_empty() or wid.is_empty() or hand_seq < 0:
		return
	var gkey := _gen_key(rid, hand_seq, wid)
	var already_sent: bool = _mark_gen_cancelled(gkey)
	if not already_sent and _client != null:
		if _client.send_window_cancel(rid, hand_seq, wid):
			cancels_sent += 1
	var keys: Array = _pending.keys()
	for k in keys:
		var ctx: Dictionary = _pending[k] as Dictionary
		if str(ctx.get("room_id", "")) == rid \
				and int(ctx.get("hand_seq", -1)) == hand_seq \
				and str(ctx.get("window_id", "")) == wid:
			_terminalize_pending(str(k), "CANCELLED", "", "", false)
	var sks: Array = _streams.keys()
	for sk in sks:
		var st: Dictionary = _streams[sk] as Dictionary
		if str(st.get("room_id", "")) == rid \
				and int(st.get("hand_seq", -1)) == hand_seq \
				and str(st.get("window_id", "")) == wid:
			_stop_stream_and_drop(str(sk), true)
			_clear_drop_until_end(str(sk))  # window cancel 即终：不必再等 PTT
			_clear_overflow(str(sk))


func handle_stream_abort(room_id: String, seat: int, utterance_id: String) -> void:
	_on_stt_utterance_abort({
		"room_id": room_id, "seat": seat, "utterance_id": utterance_id,
	})


func get_pending_count() -> int:
	return _pending.size()


func get_stream_count() -> int:
	return _streams.size()


func get_buffer_pcm_bytes() -> int:
	var total: int = 0
	for k in _streams.keys():
		total += int((_streams[k] as Dictionary).get("bytes", 0))
	return total


func is_overflowed(room_id: String, seat: int, utterance_id: String) -> bool:
	return _overflowed.has(_utt_key(room_id, seat, utterance_id))


func inject_pending_for_test(ctx: Dictionary) -> void:
	var key := _utt_key(str(ctx.get("room_id", "")), int(ctx.get("seat", -1)), str(ctx.get("utterance_id", "")))
	_pending[key] = ctx.duplicate(true)


func handle_stt_result_for_test(msg: Dictionary) -> void:
	var kind := str(msg.get("kind", ""))
	if kind == "TRANSCRIPT_FINAL":
		_on_stt_final(msg)
	elif kind == "UTTERANCE_FAILED":
		_on_stt_failed(msg)
	elif kind == "TRANSCRIPT_PARTIAL":
		_on_stt_partial(msg)


func handle_frame_for_test(frame: Dictionary) -> void:
	_on_stt_frame(frame)


func handle_ptt_end_for_test(auth_msg: Dictionary) -> void:
	_on_stt_ptt_end(auth_msg)


func _teardown_client() -> void:
	if _client == null:
		return
	if _client.transcript_partial.is_connected(_on_stt_partial):
		_client.transcript_partial.disconnect(_on_stt_partial)
	if _client.transcript_final.is_connected(_on_stt_final):
		_client.transcript_final.disconnect(_on_stt_final)
	if _client.utterance_failed.is_connected(_on_stt_failed):
		_client.utterance_failed.disconnect(_on_stt_failed)
	if _client.disconnected.is_connected(_on_stt_disconnected):
		_client.disconnected.disconnect(_on_stt_disconnected)
	_client.disconnect_stt()
	if is_instance_valid(_client):
		_client.queue_free()
	_client = null


func _on_stt_frame(frame: Dictionary) -> void:
	var room_id := str(frame.get("room_id", ""))
	var seat: int = int(frame.get("seat", -1))
	var utt := str(frame.get("utterance_id", ""))
	if room_id.is_empty() or utt.is_empty() or seat < 0 or seat > 3:
		return
	var ukey := _utt_key(room_id, seat, utt)
	if _overflowed.has(ukey):
		return
	# 丢弃至权威 PTT_END：禁止截断续传
	if _drop_until_end.has(ukey):
		return
	var auth: Dictionary = _read_live_window_auth(room_id)
	if auth.is_empty():
		return
	var phase := str(auth.get("phase", ""))
	var window_id := str(auth.get("window_id", ""))
	var hand_seq: int = int(auth.get("hand_seq", 0))
	var is_new := not _streams.has(ukey)
	if is_new:
		if phase != RewardWindowModule.PHASE_OPEN:
			return
		if window_id.is_empty() or _is_gen_cancelled(room_id, hand_seq, window_id):
			return
		if _streams.size() >= MAX_BUFFERED_UTTERANCES:
			return
		# P1-2：已配置 transport 但未 OPEN → 整句 drop，禁止稍后截断续传
		if _client != null and not _client.is_stt_open():
			_mark_drop_until_end(ukey)
			return
		_streams[ukey] = {
			"room_id": room_id, "seat": seat, "utterance_id": utt,
			"window_id": window_id, "hand_seq": hand_seq,
			"bytes": 0, "frame_count": 0, "started": false,
		}
		if _client != null and _client.is_stt_open():
			if _client.send_start(room_id, seat, hand_seq, window_id, utt):
				(_streams[ukey] as Dictionary)["started"] = true
			else:
				# 首帧 START 失败：完整性未知，drop 至 PTT_END
				_streams.erase(ukey)
				_mark_drop_until_end(ukey)
				return
	else:
		var st0: Dictionary = _streams[ukey] as Dictionary
		# P1-5：后续帧实时核对 live phase/generation；离开 OPEN 立即停流+cancel
		if phase != RewardWindowModule.PHASE_OPEN \
				or str(st0.get("window_id", "")) != window_id \
				or int(st0.get("hand_seq", -1)) != hand_seq \
				or _is_gen_cancelled(room_id, hand_seq, window_id):
			_stop_stream_and_drop(ukey, true)
			return

	var chunk: PackedByteArray = frame.get("pcm", PackedByteArray()) as PackedByteArray
	if chunk.is_empty():
		return
	if not _streams.has(ukey):
		return
	var st: Dictionary = _streams[ukey] as Dictionary
	var nbytes: int = int(st.get("bytes", 0)) + chunk.size()
	if nbytes > MAX_PCM_BYTES:
		_mark_overflow(ukey)
		_stop_stream_and_drop(ukey, true)
		return
	st["bytes"] = nbytes
	st["frame_count"] = int(st.get("frame_count", 0)) + 1
	_streams[ukey] = st
	frames_accepted += 1
	if _client != null and _client.is_stt_open():
		if not bool(st.get("started", false)):
			if _client.send_start(room_id, seat, hand_seq, window_id, utt):
				st["started"] = true
				_streams[ukey] = st
			else:
				_stop_stream_and_drop(ukey, false)
				return
		var want_partial: bool = (int(st["frame_count"]) % PARTIAL_EVERY_N_FRAMES) == 0
		if not _client.send_audio_chunk(room_id, seat, hand_seq, window_id, utt, chunk, want_partial):
			# 发送失败：完整性未知，停流 drop
			_stop_stream_and_drop(ukey, true)
			return


func _on_stt_ptt_end(auth_msg: Dictionary) -> void:
	var room_id := str(auth_msg.get("room_id", ""))
	var seat: int = int(auth_msg.get("seat", -1))
	var utt := str(auth_msg.get("utterance_id", ""))
	var ptt_seq: int = int(auth_msg.get("server_seq", 0))
	if room_id.is_empty() or utt.is_empty() or seat < 0 or seat > 3 or ptt_seq <= 0:
		return
	if _worker == null:
		return
	var ukey := _utt_key(room_id, seat, utt)
	var auth: Dictionary = _read_live_window_auth(room_id)
	if auth.is_empty():
		_streams.erase(ukey)
		return
	var phase := str(auth.get("phase", ""))
	var window_id := str(auth.get("window_id", ""))
	var hand_seq: int = int(auth.get("hand_seq", 0))
	var closing = auth.get("closing_boundary_server_seq", null)
	var grace_ms: int = int(auth.get("grace_deadline_ms", 0))
	var grace_at := str(auth.get("grace_deadline_at", ""))
	var lang0 := str(auth.get("language", "zh"))
	if lang0 != "zh" and lang0 != "en" and lang0 != "ja":
		lang0 = "zh"

	# stream 代际必须与当前权威一致
	if _streams.has(ukey):
		var st_chk: Dictionary = _streams[ukey] as Dictionary
		if str(st_chk.get("window_id", "")) != window_id or int(st_chk.get("hand_seq", -1)) != hand_seq:
			_streams.erase(ukey)
			_clear_overflow(ukey)
			return

	if _overflowed.has(ukey):
		if phase == RewardWindowModule.PHASE_OPEN or phase == RewardWindowModule.PHASE_CLOSING:
			if not (phase == RewardWindowModule.PHASE_CLOSING and closing != null and ptt_seq > int(closing)):
				if not window_id.is_empty() and not _is_gen_cancelled(room_id, hand_seq, window_id):
					_register_pending_empty(room_id, seat, utt, hand_seq, window_id, phase, ptt_seq, closing, grace_at, grace_ms, lang0)
					_terminalize_pending(ukey, "OVERFLOW", "", "", false)
		_streams.erase(ukey)
		_clear_overflow(ukey)
		_clear_drop_until_end(ukey)
		return

	if phase != RewardWindowModule.PHASE_OPEN and phase != RewardWindowModule.PHASE_CLOSING:
		_streams.erase(ukey)
		return
	if window_id.is_empty() or _is_gen_cancelled(room_id, hand_seq, window_id):
		_streams.erase(ukey)
		return
	if phase == RewardWindowModule.PHASE_CLOSING and closing != null and ptt_seq > int(closing):
		_streams.erase(ukey)
		return

	var stream: Dictionary = _streams.get(ukey, {}) as Dictionary
	var ctx := {
		"room_id": room_id, "seat": seat, "utterance_id": utt,
		"hand_seq": hand_seq, "window_id": window_id, "phase_at_ptt": phase,
		"ptt_end_server_seq": ptt_seq, "closing_boundary_server_seq": closing,
		"grace_deadline_at": grace_at, "grace_deadline_ms": grace_ms, "language": lang0,
	}
	_pending[ukey] = ctx
	ends_accepted += 1
	var rw: RewardWindowModule = _get_rw(room_id)
	if rw == null:
		_pending.erase(ukey)
		_streams.erase(ukey)
		return
	var ing: Dictionary = rw.ingest_utterance({
		"seat": seat, "utterance_id": utt, "text": "", "language": lang0,
		"ptt_end_server_seq": ptt_seq, "terminal": false,
	})
	if not bool(ing.get("accepted", false)) and str(ing.get("reason", "")) != "DUPLICATE":
		_pending.erase(ukey)
		_streams.erase(ukey)
		return

	_clear_drop_until_end(ukey)
	if _client != null and _client.is_stt_open():
		if stream.is_empty() or not bool(stream.get("started", false)):
			if not _client.send_start(room_id, seat, hand_seq, window_id, utt):
				_terminalize_pending(ukey, "STT_SEND_FAIL", "", "", false)
				_streams.erase(ukey)
				return
		if not _client.send_commit(room_id, seat, hand_seq, window_id, utt, ptt_seq):
			_terminalize_pending(ukey, "STT_SEND_FAIL", "", "", false)
			_streams.erase(ukey)
			return
	else:
		_terminalize_pending(ukey, "NO_STT", "", "", false)
	_streams.erase(ukey)


func _on_stt_utterance_abort(info: Dictionary) -> void:
	var room_id := str(info.get("room_id", ""))
	var seat: int = int(info.get("seat", -1))
	var utt := str(info.get("utterance_id", ""))
	if room_id.is_empty() or utt.is_empty() or seat < 0:
		return
	var ukey := _utt_key(room_id, seat, utt)
	if _streams.has(ukey):
		_stop_stream_and_drop(ukey, true)
	_clear_overflow(ukey)
	# abort 也清理 drop tombstone（连接已结束 speaking）
	_clear_drop_until_end(ukey)
	# 若尚未 pending，无需 RW terminalize（未注册屏障）


func _on_stt_partial(msg: Dictionary) -> void:
	if not _validate_service_msg(msg, false):
		return
	if not _match_active_context(msg, false):
		return
	# partial 永不 ingest、永不改 RW
	transcript_partial_broadcast.emit(msg.duplicate(true))
	partials_broadcast += 1
	last_broadcast_count += 1
	_broadcast_room_transcript(msg)


func _on_stt_final(msg: Dictionary) -> void:
	if not _validate_service_msg(msg, true):
		last_reject_reason = "SCHEMA"
		return
	# 先权威准入 + ingest，成功才广播
	var accepted: bool = _try_ingest_final(msg)
	if not accepted:
		return
	var text := str(msg.get("text", "")).strip_edges()
	if text.is_empty():
		return  # 空白 final 可终态但不广播字幕
	transcript_final_broadcast.emit(msg.duplicate(true))
	finals_broadcast += 1
	last_broadcast_count += 1
	_broadcast_room_transcript(msg)


func _on_stt_failed(msg: Dictionary) -> void:
	if not _validate_failed_msg(msg):
		return
	var ukey := _utt_key(str(msg.get("room_id", "")), int(msg.get("seat", -1)), str(msg.get("utterance_id", "")))
	if not _pending.has(ukey):
		return
	var ctx: Dictionary = _pending[ukey] as Dictionary
	if not _ctx_matches_msg(ctx, msg, true):
		return
	_terminalize_pending(ukey, str(msg.get("reason", "FAILED")), "", "", false)


func _match_active_context(msg: Dictionary, require_ptt: bool) -> bool:
	var room_id := str(msg.get("room_id", ""))
	var seat: int = int(msg.get("seat", -1))
	var utt := str(msg.get("utterance_id", ""))
	var ukey := _utt_key(room_id, seat, utt)
	var hand: int = int(msg.get("hand_seq", -1))
	var wid := str(msg.get("window_id", ""))
	if _is_gen_cancelled(room_id, hand, wid):
		return false
	# 始终读 live 权威 phase/deadline/window
	var live: Dictionary = _read_live_window_auth(room_id)
	if live.is_empty():
		return false
	if str(live.get("window_id", "")) != wid or int(live.get("hand_seq", -1)) != hand:
		return false
	var phase := str(live.get("phase", ""))
	if phase != RewardWindowModule.PHASE_OPEN and phase != RewardWindowModule.PHASE_CLOSING:
		return false
	if phase == RewardWindowModule.PHASE_CLOSING:
		var grace_ms: int = int(live.get("grace_deadline_ms", 0))
		var now_ms: int = _authority_now_ms(room_id)
		if grace_ms > 0 and (now_ms < 0 or now_ms >= grace_ms):
			return false
	if _streams.has(ukey):
		var st: Dictionary = _streams[ukey] as Dictionary
		return str(st.get("room_id", "")) == room_id \
			and int(st.get("seat", -1)) == seat \
			and str(st.get("utterance_id", "")) == utt \
			and int(st.get("hand_seq", -1)) == hand \
			and str(st.get("window_id", "")) == wid
	if _pending.has(ukey):
		var ctx: Dictionary = _pending[ukey] as Dictionary
		return _ctx_matches_msg(ctx, msg, require_ptt)
	return false


func _ctx_matches_msg(ctx: Dictionary, msg: Dictionary, require_ptt: bool) -> bool:
	if str(ctx.get("room_id", "")) != str(msg.get("room_id", "")):
		return false
	if int(ctx.get("seat", -1)) != int(msg.get("seat", -1)):
		return false
	if str(ctx.get("utterance_id", "")) != str(msg.get("utterance_id", "")):
		return false
	if int(ctx.get("hand_seq", -1)) != int(msg.get("hand_seq", -1)):
		return false
	if str(ctx.get("window_id", "")) != str(msg.get("window_id", "")):
		return false
	if require_ptt:
		if int(ctx.get("ptt_end_server_seq", -1)) != int(msg.get("ptt_end_server_seq", -2)):
			return false
	return true


func _is_allowed_source(source: String, require_final: bool) -> bool:
	# partial 仅 faster_whisper；final 允许主备 source（#248 new_api）。
	if require_final:
		return source == SOURCE_FASTER_WHISPER or source == SOURCE_NEW_API
	return source == SOURCE_FASTER_WHISPER


func _validate_service_msg(msg: Dictionary, require_final: bool) -> bool:
	if not _is_json_int(msg.get("protocol_version", null)) or int(msg["protocol_version"]) != PROTOCOL_VERSION:
		return false
	if not _is_allowed_source(str(msg.get("source", "")), require_final):
		return false
	if require_final:
		if str(msg.get("kind", "")) != "TRANSCRIPT_FINAL":
			return false
		if typeof(msg.get("is_final", null)) != TYPE_BOOL or not bool(msg["is_final"]):
			return false
		if not _is_json_int(msg.get("ptt_end_server_seq", null)) or int(msg["ptt_end_server_seq"]) <= 0:
			return false
	else:
		if str(msg.get("kind", "")) != "TRANSCRIPT_PARTIAL":
			return false
		# partial 必须显式 is_final:false
		if typeof(msg.get("is_final", null)) != TYPE_BOOL or bool(msg["is_final"]):
			return false
	for k in ["room_id", "window_id", "utterance_id"]:
		if typeof(msg.get(k, null)) != TYPE_STRING or str(msg[k]).strip_edges().is_empty():
			return false
	if not _is_json_int(msg.get("seat", null)):
		return false
	var seat: int = int(msg["seat"])
	if seat < 0 or seat > 3:
		return false
	if not _is_json_int(msg.get("hand_seq", null)):
		return false
	if typeof(msg.get("text", null)) != TYPE_STRING and typeof(msg.get("text", null)) != TYPE_STRING_NAME:
		return false
	if typeof(msg.get("lang", null)) != TYPE_STRING and typeof(msg.get("lang", null)) != TYPE_STRING_NAME:
		return false
	return true


func _validate_failed_msg(msg: Dictionary) -> bool:
	if not _is_json_int(msg.get("protocol_version", null)) or int(msg["protocol_version"]) != PROTOCOL_VERSION:
		return false
	if str(msg.get("kind", "")) != "UTTERANCE_FAILED":
		return false
	if str(msg.get("source", "")) != SOURCE_FASTER_WHISPER:
		return false
	if typeof(msg.get("is_final", null)) != TYPE_BOOL or not bool(msg["is_final"]):
		return false
	if typeof(msg.get("reason", null)) != TYPE_STRING or str(msg["reason"]).strip_edges().is_empty():
		return false
	for k in ["room_id", "window_id", "utterance_id"]:
		if typeof(msg.get(k, null)) != TYPE_STRING or str(msg[k]).strip_edges().is_empty():
			return false
	if not _is_json_int(msg.get("seat", null)):
		return false
	if not _is_json_int(msg.get("hand_seq", null)):
		return false
	# pending 后权威 ptt 若存在必须一致
	var ukey := _utt_key(str(msg.get("room_id", "")), int(msg.get("seat", -1)), str(msg.get("utterance_id", "")))
	if _pending.has(ukey):
		var ctx: Dictionary = _pending[ukey] as Dictionary
		if msg.has("ptt_end_server_seq") and msg.get("ptt_end_server_seq") != null:
			if not _is_json_int(msg.get("ptt_end_server_seq", null)):
				return false
			if int(msg["ptt_end_server_seq"]) != int(ctx.get("ptt_end_server_seq", -1)):
				return false
	return true


## JSON 整型：仅 TYPE_INT 或整值 float（拒绝 1.5）。
func _is_json_int(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		var f: float = float(v)
		return f == floorf(f)
	return false


## 返回是否接受为合格 final（非空文本且 RW 接受）。
func _try_ingest_final(msg: Dictionary) -> bool:
	var room_id := str(msg.get("room_id", ""))
	var seat: int = int(msg.get("seat", -1))
	var utt := str(msg.get("utterance_id", ""))
	var ukey := _utt_key(room_id, seat, utt)
	if not _pending.has(ukey):
		last_reject_reason = "NO_PENDING"
		return false
	var ctx: Dictionary = _pending[ukey] as Dictionary
	if not _ctx_matches_msg(ctx, msg, true):
		last_reject_reason = "CONTEXT_MISMATCH"
		return false
	var window_id := str(ctx.get("window_id", ""))
	var hand_seq: int = int(ctx.get("hand_seq", -1))
	var ptt_ctx: int = int(ctx.get("ptt_end_server_seq", -2))
	if _is_gen_cancelled(room_id, hand_seq, window_id):
		_terminalize_pending(ukey, "CANCELLED", "", "", false)
		return false

	var live: Dictionary = _read_live_window_auth(room_id)
	if live.is_empty():
		_terminalize_pending(ukey, "NO_WINDOW", "", "", false)
		return false
	if str(live.get("window_id", "")) != window_id or int(live.get("hand_seq", -1)) != hand_seq:
		_terminalize_pending(ukey, "WINDOW_CHANGED", "", "", false)
		return false
	var phase := str(live.get("phase", ""))
	if phase != RewardWindowModule.PHASE_OPEN and phase != RewardWindowModule.PHASE_CLOSING:
		_terminalize_pending(ukey, "INVALID_PHASE", "", "", false)
		return false
	var closing = live.get("closing_boundary_server_seq", null)
	if closing != null and ptt_ctx > int(closing):
		_terminalize_pending(ukey, "PTT_AFTER_CLOSING_BOUNDARY", "", "", false)
		return false
	var now_ms: int = _authority_now_ms(room_id)
	var grace_ms: int = int(live.get("grace_deadline_ms", 0))
	if phase == RewardWindowModule.PHASE_CLOSING and grace_ms > 0 and (now_ms < 0 or now_ms >= grace_ms):
		_cancel_utterance_python(ctx)
		_terminalize_pending(ukey, "DEADLINE_EXCEEDED", "", "", false)
		return false

	var text := str(msg.get("text", "")).strip_edges()
	var lang := str(ctx.get("language", "zh"))
	if lang != "zh" and lang != "en" and lang != "ja":
		lang = "zh"
	var msg_lang := str(msg.get("lang", "")).strip_edges().to_lower()
	if (msg_lang == "zh" or msg_lang == "en" or msg_lang == "ja") and not text.is_empty():
		lang = msg_lang
	else:
		text = ""

	var rw: RewardWindowModule = _get_rw(room_id)
	if rw == null:
		_pending.erase(ukey)
		last_reject_reason = "NO_RW"
		return false
	var res: Dictionary = rw.ingest_utterance({
		"seat": seat, "utterance_id": utt, "text": text, "language": lang,
		"ptt_end_server_seq": ptt_ctx, "terminal": true,
	})
	last_ingest_result = res.duplicate(true)
	if not bool(res.get("accepted", false)):
		last_reject_reason = str(res.get("reason", "REJECTED"))
		_pending.erase(ukey)
		return false
	if text != "":
		finals_ingested += 1
	_pending.erase(ukey)
	utterance_terminalized.emit(room_id, seat, utt, str(res.get("reason", "OK")))
	return text != ""


func _terminalize_pending(key: String, reason: String, text: String, _lang_unused: String, _broadcast: bool) -> void:
	if not _pending.has(key):
		return
	var ctx: Dictionary = _pending[key] as Dictionary
	var room_id := str(ctx.get("room_id", ""))
	var seat: int = int(ctx.get("seat", -1))
	var utt := str(ctx.get("utterance_id", ""))
	var ptt: int = int(ctx.get("ptt_end_server_seq", 0))
	# 使用冻结上下文原语言，避免 en/ja pending 因 language conflict 无法 terminalize
	var use_lang := str(ctx.get("language", "zh"))
	if use_lang != "zh" and use_lang != "en" and use_lang != "ja":
		use_lang = "zh"
	var rw: RewardWindowModule = _get_rw(room_id)
	if rw != null and ptt > 0:
		var res: Dictionary = rw.ingest_utterance({
			"seat": seat, "utterance_id": utt, "text": text, "language": use_lang,
			"ptt_end_server_seq": ptt, "terminal": true,
		})
		if not bool(res.get("accepted", false)) and str(res.get("reason", "")) != "DUPLICATE":
			last_reject_reason = "TERM_FAIL:%s" % str(res.get("reason", ""))
			# 仍删除 bridge pending，避免死锁；RW 冲突由测试/上层可见
	_pending.erase(key)
	last_reject_reason = reason
	utterance_terminalized.emit(room_id, seat, utt, reason)


func _tick_deadlines() -> void:
	if _worker == null or _pending.is_empty():
		return
	var keys: Array = _pending.keys()
	for k in keys:
		var ctx: Dictionary = _pending[k] as Dictionary
		var room_id := str(ctx.get("room_id", ""))
		var window_id := str(ctx.get("window_id", ""))
		var hand_seq: int = int(ctx.get("hand_seq", -1))
		var now_ms: int = _authority_now_ms(room_id)
		if _is_gen_cancelled(room_id, hand_seq, window_id):
			_cancel_utterance_python(ctx)
			_terminalize_pending(str(k), "CANCELLED", "", "", false)
			continue
		var live: Dictionary = _read_live_window_auth(room_id)
		if live.is_empty():
			continue
		if str(live.get("window_id", "")) != window_id or int(live.get("hand_seq", -1)) != hand_seq:
			_cancel_utterance_python(ctx)
			_terminalize_pending(str(k), "WINDOW_CHANGED", "", "", false)
			continue
		var phase := str(live.get("phase", ""))
		if phase == RewardWindowModule.PHASE_CANCELLED or phase == RewardWindowModule.PHASE_SETTLED:
			_cancel_utterance_python(ctx)
			_terminalize_pending(str(k), "WINDOW_CLOSED", "", "", false)
			continue
		if phase == RewardWindowModule.PHASE_CLOSING:
			var rw_grace: int = int(live.get("grace_deadline_ms", 0))
			if rw_grace > 0 and (now_ms < 0 or now_ms >= rw_grace):
				_cancel_utterance_python(ctx)
				_terminalize_pending(str(k), "DEADLINE_EXCEEDED", "", "", false)


func _cancel_utterance_python(ctx: Dictionary) -> void:
	_send_utt_cancel(
		str(ctx.get("room_id", "")),
		int(ctx.get("seat", -1)),
		int(ctx.get("hand_seq", 0)),
		str(ctx.get("window_id", "")),
		str(ctx.get("utterance_id", ""))
	)


func _send_utt_cancel(room_id: String, seat: int, hand_seq: int, window_id: String, utt: String) -> void:
	if _client == null:
		return
	if _client.send_utterance_cancel(room_id, seat, hand_seq, window_id, utt):
		cancels_sent += 1


func _register_pending_empty(
	room_id: String, seat: int, utt: String, hand_seq: int, window_id: String,
	phase: String, ptt_seq: int, closing, grace_at: String, grace_ms: int, lang: String
) -> void:
	var ukey := _utt_key(room_id, seat, utt)
	_pending[ukey] = {
		"room_id": room_id, "seat": seat, "utterance_id": utt, "hand_seq": hand_seq,
		"window_id": window_id, "phase_at_ptt": phase, "ptt_end_server_seq": ptt_seq,
		"closing_boundary_server_seq": closing, "grace_deadline_at": grace_at,
		"grace_deadline_ms": grace_ms, "language": lang,
	}
	var rw: RewardWindowModule = _get_rw(room_id)
	if rw != null:
		rw.ingest_utterance({
			"seat": seat, "utterance_id": utt, "text": "", "language": lang,
			"ptt_end_server_seq": ptt_seq, "terminal": false,
		})


func _broadcast_room_transcript(msg: Dictionary) -> void:
	if _worker == null:
		return
	var relay: VoiceRelayServer = _worker.get_voice_relay()
	if relay == null:
		return
	var room_id := str(msg.get("room_id", ""))
	if room_id.is_empty():
		return
	var src := str(msg.get("source", SOURCE_FASTER_WHISPER))
	if not _is_allowed_source(src, bool(msg.get("is_final", false))):
		src = SOURCE_FASTER_WHISPER
	relay.broadcast_control_to_room(room_id, {
		"protocol_version": PROTOCOL_VERSION,
		"kind": str(msg.get("kind", "")),
		"room_id": room_id,
		"seat": int(msg.get("seat", -1)),
		"hand_seq": int(msg.get("hand_seq", 0)),
		"window_id": str(msg.get("window_id", "")),
		"utterance_id": str(msg.get("utterance_id", "")),
		"ptt_end_server_seq": msg.get("ptt_end_server_seq", null),
		"source": src,
		"lang": str(msg.get("lang", "")),
		"text": str(msg.get("text", "")),
		"is_final": bool(msg.get("is_final", false)),
	})


func _read_live_window_auth(room_id: String) -> Dictionary:
	var rw: RewardWindowModule = _get_rw(room_id)
	if rw == null:
		return {}
	return {
		"phase": str(rw.phase),
		"window_id": str(rw.window_id),
		"hand_seq": int(rw.hand_seq),
		"closing_boundary_server_seq": rw.closing_boundary_server_seq,
		"context_boundary_server_seq": rw.context_boundary_server_seq,
		"grace_deadline_at": str(rw.grace_deadline_at),
		"grace_deadline_ms": int(rw.get_grace_deadline_ms()),
		"language": str(rw.get_window_language()),
	}


## #252 RewardWindow 权威当前时间；不得使用 Worker 墙钟/lease 时钟。
func _authority_now_ms(room_id: String) -> int:
	if _worker == null:
		return -1
	var session: HeadlessRoomSession = _worker.get_room(room_id)
	if session == null or session.server == null:
		return -1
	if session.server.has_method("reward_authority_now_ms"):
		return int(session.server.reward_authority_now_ms())
	return -1


func _get_rw(room_id: String) -> RewardWindowModule:
	if _worker == null:
		return null
	var session: HeadlessRoomSession = _worker.get_room(room_id)
	if session == null or session.server == null or session.server.mode_modules == null:
		return null
	return session.server.mode_modules.reward_window


## 统一：停本地流、可选向 Python cancel、标记 drop 至权威 PTT_END。
func _stop_stream_and_drop(ukey: String, send_cancel: bool) -> void:
	if _streams.has(ukey):
		var st: Dictionary = _streams[ukey] as Dictionary
		if send_cancel and bool(st.get("started", false)):
			_send_utt_cancel(
				str(st.get("room_id", "")),
				int(st.get("seat", -1)),
				int(st.get("hand_seq", 0)),
				str(st.get("window_id", "")),
				str(st.get("utterance_id", ""))
			)
		_streams.erase(ukey)
	_mark_drop_until_end(ukey)


## 每 poll：离开 OPEN / 代际变化的 stream 立即清理（不依赖仅扫 CANCELLED）。
func _reconcile_streams_with_live() -> void:
	if _streams.is_empty() and _pending.is_empty():
		return
	var skeys: Array = _streams.keys()
	for sk in skeys:
		var st: Dictionary = _streams[sk] as Dictionary
		var room_id := str(st.get("room_id", ""))
		var live: Dictionary = _read_live_window_auth(room_id)
		if live.is_empty():
			_stop_stream_and_drop(str(sk), true)
			continue
		var phase := str(live.get("phase", ""))
		if phase != RewardWindowModule.PHASE_OPEN \
				or str(live.get("window_id", "")) != str(st.get("window_id", "")) \
				or int(live.get("hand_seq", -1)) != int(st.get("hand_seq", -1)) \
				or _is_gen_cancelled(room_id, int(st.get("hand_seq", -1)), str(st.get("window_id", ""))):
			_stop_stream_and_drop(str(sk), true)
	# SETTLED/CANCELLED：终态化匹配 pending 并 tombstone 代际
	var pkeys: Array = _pending.keys()
	for pk in pkeys:
		var ctx: Dictionary = _pending[pk] as Dictionary
		var rid := str(ctx.get("room_id", ""))
		var live2: Dictionary = _read_live_window_auth(rid)
		if live2.is_empty():
			continue
		var ph2 := str(live2.get("phase", ""))
		if ph2 == RewardWindowModule.PHASE_CANCELLED or ph2 == RewardWindowModule.PHASE_SETTLED:
			if str(live2.get("window_id", "")) == str(ctx.get("window_id", "")) \
					and int(live2.get("hand_seq", -1)) == int(ctx.get("hand_seq", -1)):
				_cancel_utterance_python(ctx)
				_terminalize_pending(str(pk), "WINDOW_CLOSED", "", "", false)


func _gen_key(room_id: String, hand_seq: int, window_id: String) -> String:
	return "%s|%d|%s" % [room_id, hand_seq, window_id]


func _utt_key(room_id: String, seat: int, utt: String) -> String:
	return "%s|%d|%s" % [room_id, seat, utt]


## 返回 true 表示此前已发送过 cancel（幂等）。
func _mark_gen_cancelled(gkey: String) -> bool:
	var already: bool = false
	if _gen_tombstones.has(gkey):
		already = bool((_gen_tombstones[gkey] as Dictionary).get("sent", false))
		(_gen_tombstones[gkey] as Dictionary)["cancelled"] = true
		(_gen_tombstones[gkey] as Dictionary)["sent"] = true
	else:
		_gen_tombstones[gkey] = {"cancelled": true, "sent": true}
		_gen_order.append(gkey)
	while _gen_order.size() > MAX_CANCEL_TOMBSTONES:
		var old: String = str(_gen_order.pop_front())
		_gen_tombstones.erase(old)
	return already


func _is_gen_cancelled(room_id: String, hand_seq: int, window_id: String) -> bool:
	var gkey := _gen_key(room_id, hand_seq, window_id)
	if not _gen_tombstones.has(gkey):
		return false
	return bool((_gen_tombstones[gkey] as Dictionary).get("cancelled", false))


func _on_stt_disconnected() -> void:
	# 传输断开：pending 终态；stream 标记 drop_until_end，禁止截断续传
	var pkeys: Array = _pending.keys()
	for k in pkeys:
		_terminalize_pending(str(k), "STT_DISCONNECTED", "", "", false)
	var skeys: Array = _streams.keys()
	for sk in skeys:
		_streams.erase(sk)
		_mark_drop_until_end(str(sk))
	# overflow 可保留到 END 清理


func _mark_drop_until_end(ukey: String) -> void:
	if ukey.is_empty():
		return
	if not _drop_until_end.has(ukey):
		_drop_order.append(ukey)
	_drop_until_end[ukey] = true
	while _drop_order.size() > MAX_DROP_TOMBSTONES:
		var old: String = str(_drop_order.pop_front())
		_drop_until_end.erase(old)


func _clear_drop_until_end(ukey: String) -> void:
	_drop_until_end.erase(ukey)
	_drop_order.erase(ukey)


func _mark_overflow(ukey: String) -> void:
	_overflowed[ukey] = true
	if not _overflow_order.has(ukey):
		_overflow_order.append(ukey)
	while _overflow_order.size() > MAX_OVERFLOW_TOMBSTONES:
		var old: String = str(_overflow_order.pop_front())
		_overflowed.erase(old)


func _clear_overflow(ukey: String) -> void:
	_overflowed.erase(ukey)
	_overflow_order.erase(ukey)
