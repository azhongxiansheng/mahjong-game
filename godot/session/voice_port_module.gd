class_name VoicePortModule extends RefCounted

# E4-01（#243）：欢乐场语音生产模块。
# PTT 状态、PCM 帧元数据、有界出站/入站队列、远端分座位入口（#244 可调用）。
# 不实现 WebSocket / STT / 静音 / 音量 / 举报。客户端 PTT_END 不含权威序号字段。

signal outbound_control(msg: Dictionary)
signal outbound_frame(frame: Dictionary)
signal ptt_state_changed(state: StringName)
signal microphone_unavailable()
signal remote_frame_accepted(frame: Dictionary)

enum CaptureBackend {
	LIVE = 0,
	FIXTURE = 1,
}

const DEFAULT_QUEUE_CAPACITY: int = 64
const SAMPLE_FORMAT := VoicePcmConverter.SAMPLE_FORMAT

var microphone_requested: bool = false

var _protocol_version: int = ProtocolConstants.PROTOCOL_VERSION
var _room_id: String = ""
var _session_id: String = ""
var _local_seat: int = 0

var _backend: int = CaptureBackend.LIVE
var _ptt_pressed: bool = false
var _capturing: bool = false
var _utterance_id: String = ""
var _frame_seq: int = 0
var _utt_counter: int = 0

var _converter: VoicePcmConverter = VoicePcmConverter.new()
var _capture_mix_rate: int = VoicePcmConverter.TARGET_SAMPLE_RATE
var _outbound: VoiceFrameQueue = VoiceFrameQueue.new(DEFAULT_QUEUE_CAPACITY)
var _remote: Dictionary = {}  # seat(int) -> VoiceFrameQueue

var _live_mic_nodes: bool = false
var _capture_pipeline: Node = null  # VoiceCapturePipeline，由 UI 注入


func _init() -> void:
	_rebuild_remote_queues()


func bind_context(config: GameSessionConfig, seat: int = 0, p_room_id: String = "") -> void:
	if config == null:
		return
	_protocol_version = ProtocolConstants.PROTOCOL_VERSION
	_session_id = config.session_id
	# 练习场可用 session_id 作为本地 room_id；公共场由 authority 注入覆盖。
	if p_room_id.is_empty():
		_room_id = config.session_id
	else:
		_room_id = p_room_id
	_local_seat = clampi(seat, 0, 3)
	_rebuild_remote_queues()


## 本席之外的 0–3 各建有界远端队列（随 local_seat 动态变化）。
func _rebuild_remote_queues() -> void:
	_remote.clear()
	for s in range(4):
		if s != _local_seat:
			_remote[s] = VoiceFrameQueue.new(DEFAULT_QUEUE_CAPACITY)


func remote_seats() -> Array:
	var seats: Array = []
	for s in range(4):
		if s != _local_seat:
			seats.append(s)
	return seats


func protocol_version() -> int:
	return _protocol_version


func room_id() -> String:
	return _room_id


func session_id() -> String:
	return _session_id


func local_seat() -> int:
	return _local_seat


func set_capture_backend(backend: int) -> void:
	_backend = backend


func capture_backend() -> int:
	return _backend


func set_outbound_capacity(capacity: int) -> void:
	var kept: Array = []
	while _outbound.size() > 0:
		kept.append(_outbound.pop())
	_outbound = VoiceFrameQueue.new(capacity)
	for f in kept:
		_outbound.push(f)


func attach_capture_pipeline(pipeline: Node) -> void:
	_capture_pipeline = pipeline


func has_live_microphone_nodes() -> bool:
	return _live_mic_nodes


func mark_live_microphone_nodes(active: bool) -> void:
	_live_mic_nodes = active


func is_ptt_pressed() -> bool:
	return _ptt_pressed


func is_capturing() -> bool:
	return _capturing


func current_utterance_id() -> String:
	return _utterance_id


func outbound_queue_size() -> int:
	return _outbound.size()


func outbound_dropped_count() -> int:
	return _outbound.dropped_count()


func pop_outbound_frame() -> Dictionary:
	return _outbound.pop()


func remote_queue_size(seat: int) -> int:
	var q: VoiceFrameQueue = _remote.get(seat, null)
	if q == null:
		return 0
	return q.size()


func pop_remote_frame(seat: int) -> Dictionary:
	var q: VoiceFrameQueue = _remote.get(seat, null)
	if q == null:
		return {}
	return q.pop()


## PTT 按下：创建 utterance，发 PTT_START；首次启动采集链路。
func press_ptt() -> bool:
	if _ptt_pressed:
		return true
	if not _ensure_capture_started():
		microphone_unavailable.emit()
		ptt_state_changed.emit(&"unavailable")
		return false
	_ptt_pressed = true
	_capturing = true
	_utt_counter += 1
	_utterance_id = "utt-%s-%d-%d" % [_session_id, _local_seat, _utt_counter]
	_frame_seq = 0
	_capture_mix_rate = _converter_source_rate()
	_converter.reset(_capture_mix_rate)
	microphone_requested = true
	var msg := _control_msg("PTT_START")
	outbound_control.emit(msg)
	ptt_state_changed.emit(&"speaking")
	return true


## 松开：发 PTT_END、停当前 utterance、清捕获 pending（保留出站已发出帧直至消费）。
func release_ptt() -> void:
	if not _ptt_pressed:
		return
	var end_utt := _utterance_id
	_ptt_pressed = false
	_capturing = false
	_converter.flush()
	if not end_utt.is_empty():
		var msg := _control_msg("PTT_END")
		# 显式保证无权威字段
		msg.erase("server_seq")
		msg.erase("server_seq_ref")
		outbound_control.emit(msg)
	_utterance_id = ""
	_frame_seq = 0
	_stop_capture_hardware()
	ptt_state_changed.emit(&"idle")


## 离房 / exit_tree / 返回大厅：释放全部缓冲与采集。
func release_all() -> void:
	if _ptt_pressed:
		release_ptt()
	else:
		_capturing = false
		_utterance_id = ""
		_frame_seq = 0
		_converter.flush()
		_stop_capture_hardware()
	_outbound.clear()
	for seat in _remote.keys():
		(_remote[seat] as VoiceFrameQueue).clear()
	# 保持当前 local_seat 的远端队列结构，仅清空内容
	_live_mic_nodes = false
	ptt_state_changed.emit(&"idle")


## 采集管线或测试注入：stereo float @ mix_rate → 帧。
func feed_capture_samples(stereo: PackedVector2Array, mix_rate: int) -> void:
	if not _capturing or not _ptt_pressed:
		return
	if mix_rate <= 0:
		return
	# 同 utterance 内 rate 应稳定；仅在尚无输出帧时允许对齐一次。
	if mix_rate != _capture_mix_rate and _frame_seq == 0 and _converter.pending_sample_count() == 0:
		_capture_mix_rate = mix_rate
		_converter.reset(mix_rate)
	var frames: Array = _converter.push_stereo(stereo)
	for pcm in frames:
		_emit_local_frame(pcm as PackedByteArray)


## #244 远端帧生产入口：分座位有界缓冲。
## room_id/session_id 必须与绑定上下文精确一致；严格类型，禁止静默转换。
func ingest_remote_audio_frame(frame: Dictionary) -> Dictionary:
	if frame.is_empty():
		return {"ok": false, "reason": "EMPTY_FRAME"}

	var room_v: Variant = frame.get("room_id", null)
	if typeof(room_v) != TYPE_STRING and typeof(room_v) != TYPE_STRING_NAME:
		return {"ok": false, "reason": "BAD_ROOM_ID_TYPE"}
	var room: String = String(room_v)
	if room.is_empty():
		return {"ok": false, "reason": "EMPTY_ROOM_ID"}
	if room != _room_id:
		return {"ok": false, "reason": "ROOM_MISMATCH"}

	var sess_v: Variant = frame.get("session_id", null)
	if typeof(sess_v) != TYPE_STRING and typeof(sess_v) != TYPE_STRING_NAME:
		return {"ok": false, "reason": "BAD_SESSION_ID_TYPE"}
	var sess: String = String(sess_v)
	if sess.is_empty():
		return {"ok": false, "reason": "EMPTY_SESSION_ID"}
	if sess != _session_id:
		return {"ok": false, "reason": "SESSION_MISMATCH"}

	var seat_v: Variant = frame.get("seat", null)
	if typeof(seat_v) != TYPE_INT:
		return {"ok": false, "reason": "BAD_SEAT_TYPE"}
	var seat: int = int(seat_v)
	if seat < 0 or seat > 3 or seat == _local_seat or not _remote.has(seat):
		return {"ok": false, "reason": "INVALID_REMOTE_SEAT"}

	var utt_v: Variant = frame.get("utterance_id", null)
	if typeof(utt_v) != TYPE_STRING and typeof(utt_v) != TYPE_STRING_NAME:
		return {"ok": false, "reason": "BAD_UTTERANCE_ID_TYPE"}
	if String(utt_v).is_empty():
		return {"ok": false, "reason": "EMPTY_UTTERANCE"}

	var seq_v: Variant = frame.get("frame_seq", null)
	if typeof(seq_v) != TYPE_INT:
		return {"ok": false, "reason": "BAD_FRAME_SEQ_TYPE"}
	if int(seq_v) < 0:
		return {"ok": false, "reason": "NEGATIVE_FRAME_SEQ"}

	var pv: Variant = frame.get("protocol_version", null)
	if typeof(pv) != TYPE_INT:
		return {"ok": false, "reason": "BAD_PROTOCOL_VERSION_TYPE"}
	if int(pv) != _protocol_version:
		return {"ok": false, "reason": "PROTOCOL_MISMATCH"}

	var fmt_v: Variant = frame.get("sample_format", null)
	if typeof(fmt_v) != TYPE_STRING and typeof(fmt_v) != TYPE_STRING_NAME:
		return {"ok": false, "reason": "BAD_SAMPLE_FORMAT_TYPE"}
	if String(fmt_v) != SAMPLE_FORMAT:
		return {"ok": false, "reason": "BAD_SAMPLE_FORMAT"}

	var rate_v: Variant = frame.get("sample_rate", null)
	if typeof(rate_v) != TYPE_INT:
		return {"ok": false, "reason": "BAD_SAMPLE_RATE_TYPE"}
	if int(rate_v) != VoicePcmConverter.TARGET_SAMPLE_RATE:
		return {"ok": false, "reason": "BAD_SAMPLE_RATE"}

	var ch_v: Variant = frame.get("channels", null)
	if typeof(ch_v) != TYPE_INT:
		return {"ok": false, "reason": "BAD_CHANNELS_TYPE"}
	if int(ch_v) != 1:
		return {"ok": false, "reason": "BAD_CHANNELS"}

	var dur_v: Variant = frame.get("frame_duration_ms", null)
	if typeof(dur_v) != TYPE_INT:
		return {"ok": false, "reason": "BAD_DURATION_TYPE"}
	if int(dur_v) != VoicePcmConverter.FRAME_DURATION_MS:
		return {"ok": false, "reason": "BAD_DURATION"}

	var pcm: Variant = frame.get("pcm", null)
	if not (pcm is PackedByteArray) or (pcm as PackedByteArray).size() != VoicePcmConverter.BYTES_PER_FRAME:
		return {"ok": false, "reason": "BAD_PCM_SIZE"}

	var q: VoiceFrameQueue = _remote[seat]
	var r: Dictionary = q.push(frame)
	if r.get("ok", false):
		remote_frame_accepted.emit(frame.duplicate(true))
	return r


func build_client_ptt_end_for_test(utterance_id: String) -> Dictionary:
	# 仅测试辅助：构造客户端请求形态
	var msg := {
		"protocol_version": _protocol_version,
		"room_id": _room_id,
		"session_id": _session_id,
		"seat": _local_seat,
		"kind": "PTT_END",
		"utterance_id": utterance_id,
	}
	return msg


func _ensure_capture_started() -> bool:
	if _backend == CaptureBackend.FIXTURE:
		# 确定性 fixture：不创建麦克风节点
		_live_mic_nodes = false
		_converter.reset(VoicePcmConverter.TARGET_SAMPLE_RATE)
		return true
	if _capture_pipeline != null and _capture_pipeline.has_method("start_capture"):
		var ok: bool = bool(_capture_pipeline.call("start_capture"))
		if ok:
			_live_mic_nodes = true
			var rate: int = VoicePcmConverter.TARGET_SAMPLE_RATE
			if _capture_pipeline.has_method("mix_rate"):
				rate = int(_capture_pipeline.call("mix_rate"))
			_converter.reset(rate)
		return ok
	# 无 pipeline 时 LIVE 失败关闭（无设备环境）
	return false


func _stop_capture_hardware() -> void:
	if _capture_pipeline != null and _capture_pipeline.has_method("stop_capture"):
		_capture_pipeline.call("stop_capture")
	_live_mic_nodes = false


func _converter_source_rate() -> int:
	# 内部：通过 reset 时写入；用 pending 路径时从 converter 不可读 rate，
	# 这里用后端约定：fixture=16k，live 由 pipeline 决定。
	if _backend == CaptureBackend.FIXTURE:
		return VoicePcmConverter.TARGET_SAMPLE_RATE
	if _capture_pipeline != null and _capture_pipeline.has_method("mix_rate"):
		return int(_capture_pipeline.call("mix_rate"))
	return VoicePcmConverter.TARGET_SAMPLE_RATE


func _emit_local_frame(pcm: PackedByteArray) -> void:
	if _utterance_id.is_empty():
		return
	var frame := {
		"protocol_version": _protocol_version,
		"room_id": _room_id,
		"session_id": _session_id,
		"seat": _local_seat,
		"utterance_id": _utterance_id,
		"frame_seq": _frame_seq,
		"sample_rate": VoicePcmConverter.TARGET_SAMPLE_RATE,
		"channels": VoicePcmConverter.CHANNELS,
		"sample_format": SAMPLE_FORMAT,
		"frame_duration_ms": VoicePcmConverter.FRAME_DURATION_MS,
		"pcm": pcm,
	}
	_frame_seq += 1
	_outbound.push(frame)
	outbound_frame.emit(frame)


func _control_msg(kind: String) -> Dictionary:
	return {
		"protocol_version": _protocol_version,
		"room_id": _room_id,
		"session_id": _session_id,
		"seat": _local_seat,
		"kind": kind,
		"utterance_id": _utterance_id,
	}
