extends GutTest

# E4-01（#243）：VoicePort 生产入口 — PTT、帧元数据、远端分座、PTT_END 无权威字段。


func _trash_config(session_id: String = "practice-voice-1") -> GameSessionConfig:
	var intent := SessionIntent.new(&"PRACTICE", &"EAST", &"TRASH_TALK", &"lin_yeche")
	var converted := GameSessionConfig.from_intent(
		intent, 7, session_id, "e4-01-v1", {}
	)
	assert_true(converted.ok)
	return converted.config


func _standard_config() -> GameSessionConfig:
	var intent := SessionIntent.new(&"PRACTICE", &"EAST", &"STANDARD", &"lin_yeche")
	var converted := GameSessionConfig.from_intent(
		intent, 3, "practice-std", "e4-01-v1", {}
	)
	assert_true(converted.ok)
	return converted.config


func _pcm_silence_frame() -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(VoicePcmConverter.BYTES_PER_FRAME)
	return b


func test_standard_bundle_keeps_voice_port_null() -> void:
	var bundle := ModeModuleBundle.from_config(_standard_config())
	assert_not_null(bundle)
	assert_null(bundle.voice_port)


func test_trash_talk_bundle_binds_context_from_config() -> void:
	var cfg := _trash_config("room-sess-9")
	var bundle := ModeModuleBundle.from_config(cfg)
	assert_not_null(bundle)
	assert_not_null(bundle.voice_port)
	var vp: VoicePortModule = bundle.voice_port
	assert_eq(vp.protocol_version(), ProtocolConstants.PROTOCOL_VERSION)
	assert_eq(vp.room_id(), "room-sess-9", "练习场 room_id=session_id")
	assert_eq(vp.session_id(), "room-sess-9")
	assert_eq(vp.local_seat(), 0)
	assert_false(vp.microphone_requested)
	assert_false(vp.is_ptt_pressed())
	assert_false(vp.is_capturing())


func test_ptt_start_end_and_frame_metadata() -> void:
	var vp := VoicePortModule.new()
	vp.bind_context(_trash_config("sess-meta"), 0)
	# 注入设备：不走真实麦克风
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	var controls: Array = []
	var frames: Array = []
	vp.outbound_control.connect(func(m: Dictionary): controls.append(m.duplicate(true)))
	vp.outbound_frame.connect(func(f: Dictionary): frames.append(f.duplicate(true)))

	assert_true(vp.press_ptt())
	assert_true(vp.is_ptt_pressed())
	assert_true(vp.microphone_requested)
	assert_eq(controls.size(), 1)
	var start_msg: Dictionary = controls[0]
	assert_eq(String(start_msg.get("kind", "")), "PTT_START")
	assert_eq(int(start_msg.get("protocol_version", -1)), 1)
	assert_eq(String(start_msg.get("room_id", "")), "sess-meta")
	assert_eq(String(start_msg.get("session_id", "")), "sess-meta")
	assert_eq(int(start_msg.get("seat", -1)), 0)
	var utt: String = String(start_msg.get("utterance_id", ""))
	assert_false(utt.is_empty())
	assert_false(start_msg.has("server_seq"))
	assert_false(start_msg.has("server_seq_ref"))

	# 喂 20ms @ 16k 单声道等价立体声
	var stereo := PackedVector2Array()
	for i in range(320):
		stereo.append(Vector2(0.1, 0.1))
	vp.feed_capture_samples(stereo, 16000)
	assert_eq(frames.size(), 1)
	var fr: Dictionary = frames[0]
	assert_eq(String(fr.get("utterance_id", "")), utt)
	assert_eq(int(fr.get("frame_seq", -1)), 0)
	assert_eq(int(fr.get("sample_rate", -1)), 16000)
	assert_eq(int(fr.get("channels", -1)), 1)
	assert_eq(String(fr.get("sample_format", "")), "PCM16_LE")
	assert_eq(int(fr.get("frame_duration_ms", -1)), 20)
	assert_eq((fr.get("pcm") as PackedByteArray).size(), 640)
	assert_eq(String(fr.get("room_id", "")), "sess-meta")
	assert_eq(int(fr.get("seat", -1)), 0)

	# 第二帧连续递增
	vp.feed_capture_samples(stereo, 16000)
	assert_eq(frames.size(), 2)
	assert_eq(int(frames[1].get("frame_seq", -1)), 1)

	vp.release_ptt()
	assert_false(vp.is_ptt_pressed())
	assert_false(vp.is_capturing())
	assert_eq(controls.size(), 2)
	var end_msg: Dictionary = controls[1]
	assert_eq(String(end_msg.get("kind", "")), "PTT_END")
	assert_eq(String(end_msg.get("utterance_id", "")), utt)
	assert_false(end_msg.has("server_seq"), "客户端 PTT_END 不得含 server_seq")
	assert_false(end_msg.has("server_seq_ref"), "客户端 PTT_END 不得含 server_seq_ref")
	# 松开后不再采集
	vp.feed_capture_samples(stereo, 16000)
	assert_eq(frames.size(), 2)


func test_new_utterance_resets_frame_seq_and_stable_id() -> void:
	var vp := VoicePortModule.new()
	vp.bind_context(_trash_config(), 0)
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	var frames: Array = []
	vp.outbound_frame.connect(func(f: Dictionary): frames.append(f.duplicate(true)))
	var controls: Array = []
	vp.outbound_control.connect(func(m: Dictionary): controls.append(m.duplicate(true)))

	assert_true(vp.press_ptt())
	var utt1: String = String(controls[0].get("utterance_id", ""))
	var stereo := PackedVector2Array()
	for i in range(320):
		stereo.append(Vector2(0.05, 0.05))
	vp.feed_capture_samples(stereo, 16000)
	vp.feed_capture_samples(stereo, 16000)
	vp.release_ptt()

	assert_true(vp.press_ptt())
	var utt2: String = String(controls[2].get("utterance_id", ""))
	assert_false(utt2.is_empty())
	assert_ne(utt1, utt2)
	vp.feed_capture_samples(stereo, 16000)
	assert_eq(int(frames[2].get("frame_seq", -1)), 0, "新 utterance frame_seq 从 0")
	assert_eq(String(frames[2].get("utterance_id", "")), utt2)
	vp.release_ptt()


func test_outbound_queue_is_bounded_drop_oldest() -> void:
	var vp := VoicePortModule.new()
	vp.bind_context(_trash_config(), 0)
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	vp.set_outbound_capacity(2)
	assert_true(vp.press_ptt())
	var stereo := PackedVector2Array()
	for i in range(320):
		stereo.append(Vector2(0.0, 0.0))
	for i in range(3):
		vp.feed_capture_samples(stereo, 16000)
	assert_eq(vp.outbound_queue_size(), 2)
	assert_eq(vp.outbound_dropped_count(), 1)
	var first: Dictionary = vp.pop_outbound_frame()
	assert_eq(int(first.get("frame_seq", -1)), 1)
	vp.release_ptt()


func test_remote_ingest_per_seat_and_reject_rules() -> void:
	var vp := VoicePortModule.new()
	vp.bind_context(_trash_config(), 0)
	var pcm := _pcm_silence_frame()
	var base := {
		"protocol_version": 1,
		"room_id": "sess-meta",
		"session_id": "sess-meta",
		"seat": 2,
		"utterance_id": "utt-r1",
		"frame_seq": 0,
		"sample_rate": 16000,
		"channels": 1,
		"sample_format": "PCM16_LE",
		"frame_duration_ms": 20,
		"pcm": pcm,
	}
	# 修 room 对齐
	base["room_id"] = vp.room_id()
	base["session_id"] = vp.session_id()

	var r0: Dictionary = vp.ingest_remote_audio_frame(base)
	assert_true(r0.get("ok", false), str(r0))
	assert_eq(vp.remote_queue_size(2), 1)

	var gap := base.duplicate(true)
	gap["frame_seq"] = 3
	assert_true(vp.ingest_remote_audio_frame(gap).get("ok", false), "允许跳帧")

	var dup := base.duplicate(true)
	dup["frame_seq"] = 3
	assert_eq(String(vp.ingest_remote_audio_frame(dup).get("reason", "")), "DUPLICATE_FRAME")

	var stale := base.duplicate(true)
	stale["frame_seq"] = 1
	assert_eq(String(vp.ingest_remote_audio_frame(stale).get("reason", "")), "STALE_FRAME")

	# 本席 0 远端入口拒绝（本地采集走 outbound）
	var local_seat_frame := base.duplicate(true)
	local_seat_frame["seat"] = 0
	assert_false(vp.ingest_remote_audio_frame(local_seat_frame).get("ok", true))

	# seat 1 / 3 各自独立队列
	var s1 := base.duplicate(true)
	s1["seat"] = 1
	s1["utterance_id"] = "utt-s1"
	assert_true(vp.ingest_remote_audio_frame(s1).get("ok", false))
	assert_eq(vp.remote_queue_size(1), 1)
	assert_eq(vp.remote_queue_size(2), 2)


func test_release_all_clears_buffers_and_stops() -> void:
	var vp := VoicePortModule.new()
	vp.bind_context(_trash_config(), 0)
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	assert_true(vp.press_ptt())
	var stereo := PackedVector2Array()
	for i in range(320):
		stereo.append(Vector2(0.0, 0.0))
	vp.feed_capture_samples(stereo, 16000)
	var pcm := _pcm_silence_frame()
	vp.ingest_remote_audio_frame({
		"protocol_version": 1,
		"room_id": vp.room_id(),
		"session_id": vp.session_id(),
		"seat": 1,
		"utterance_id": "utt-x",
		"frame_seq": 0,
		"sample_rate": 16000,
		"channels": 1,
		"sample_format": "PCM16_LE",
		"frame_duration_ms": 20,
		"pcm": pcm,
	})
	vp.release_all()
	assert_false(vp.is_ptt_pressed())
	assert_false(vp.is_capturing())
	assert_eq(vp.outbound_queue_size(), 0)
	assert_eq(vp.remote_queue_size(1), 0)
	assert_eq(vp.remote_queue_size(2), 0)
	assert_eq(vp.remote_queue_size(3), 0)
	assert_eq(vp.current_utterance_id(), "")


func test_ptt_end_payload_has_no_authority_fields() -> void:
	var vp := VoicePortModule.new()
	vp.bind_context(_trash_config(), 0)
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	# GDScript lambda 对外层 Dictionary 赋值不可靠，用 Array 收集。
	var ends: Array = []
	vp.outbound_control.connect(func(m: Dictionary):
		if String(m.get("kind", "")) == "PTT_END":
			ends.append(m.duplicate(true))
	)
	assert_true(vp.press_ptt())
	vp.release_ptt()
	assert_eq(ends.size(), 1)
	var end_payload: Dictionary = ends[0]
	assert_false(end_payload.has("server_seq"))
	assert_false(end_payload.has("server_seq_ref"))
	assert_true(end_payload.has("protocol_version"))
	assert_true(end_payload.has("room_id"))
	assert_true(end_payload.has("session_id"))
	assert_true(end_payload.has("seat"))
	assert_true(end_payload.has("kind"))
	assert_true(end_payload.has("utterance_id"))
	assert_eq(
		end_payload.keys().size(), 6,
		"仅 protocol_version/room_id/session_id/seat/kind/utterance_id"
	)


func test_fixture_backend_never_creates_godot_mic_nodes() -> void:
	var vp := VoicePortModule.new()
	vp.bind_context(_trash_config(), 0)
	vp.set_capture_backend(VoicePortModule.CaptureBackend.FIXTURE)
	assert_true(vp.press_ptt())
	assert_false(vp.has_live_microphone_nodes())
	vp.release_ptt()


func test_live_backend_without_pipeline_fails_closed() -> void:
	# 无设备/无 pipeline：不得假装采集；不算真实麦克风通过。
	var vp := VoicePortModule.new()
	vp.bind_context(_trash_config(), 0)
	vp.set_capture_backend(VoicePortModule.CaptureBackend.LIVE)
	var unavailable: Array = []
	vp.microphone_unavailable.connect(func(): unavailable.append(true))
	assert_false(vp.press_ptt(), "无 pipeline 时 LIVE 必须 fail-closed")
	assert_false(vp.is_capturing())
	assert_false(vp.is_ptt_pressed())
	assert_false(vp.has_live_microphone_nodes())
	assert_eq(unavailable.size(), 1)
	assert_eq(vp.outbound_queue_size(), 0)


func test_remote_rejects_cross_room_and_cross_session() -> void:
	var vp := VoicePortModule.new()
	vp.bind_context(_trash_config("room-A"), 0, "room-A")
	# session_id 来自 config；显式 room 绑定 room-A
	assert_eq(vp.room_id(), "room-A")
	assert_eq(vp.session_id(), "room-A")
	var accepted: Array = []
	vp.remote_frame_accepted.connect(func(_f: Dictionary): accepted.append(true))
	var pcm := _pcm_silence_frame()
	var cross_room := {
		"protocol_version": 1,
		"room_id": "room-B",
		"session_id": "room-A",
		"seat": 2,
		"utterance_id": "utt-x",
		"frame_seq": 0,
		"sample_rate": 16000,
		"channels": 1,
		"sample_format": "PCM16_LE",
		"frame_duration_ms": 20,
		"pcm": pcm,
	}
	var r1: Dictionary = vp.ingest_remote_audio_frame(cross_room)
	assert_false(r1.get("ok", true))
	assert_eq(String(r1.get("reason", "")), "ROOM_MISMATCH")
	assert_eq(vp.remote_queue_size(2), 0)
	assert_eq(accepted.size(), 0)

	var cross_sess := cross_room.duplicate(true)
	cross_sess["room_id"] = "room-A"
	cross_sess["session_id"] = "session-B"
	var r2: Dictionary = vp.ingest_remote_audio_frame(cross_sess)
	assert_false(r2.get("ok", true))
	assert_eq(String(r2.get("reason", "")), "SESSION_MISMATCH")
	assert_eq(vp.remote_queue_size(2), 0)
	assert_eq(accepted.size(), 0)


func test_remote_rejects_bad_types_empty_utt_and_non_int_seq() -> void:
	var vp := VoicePortModule.new()
	vp.bind_context(_trash_config("ctx-1"), 0)
	var pcm := _pcm_silence_frame()
	var base := {
		"protocol_version": 1,
		"room_id": vp.room_id(),
		"session_id": vp.session_id(),
		"seat": 1,
		"utterance_id": "utt-ok",
		"frame_seq": 0,
		"sample_rate": 16000,
		"channels": 1,
		"sample_format": "PCM16_LE",
		"frame_duration_ms": 20,
		"pcm": pcm,
	}
	var empty_utt := base.duplicate(true)
	empty_utt["utterance_id"] = ""
	assert_eq(String(vp.ingest_remote_audio_frame(empty_utt).get("reason", "")), "EMPTY_UTTERANCE")

	var bad_seq := base.duplicate(true)
	bad_seq["frame_seq"] = "garbage"
	assert_eq(
		String(vp.ingest_remote_audio_frame(bad_seq).get("reason", "")),
		"BAD_FRAME_SEQ_TYPE",
		"不得 int(\"garbage\") 静默归零"
	)
	assert_eq(vp.remote_queue_size(1), 0)

	var float_seq := base.duplicate(true)
	float_seq["frame_seq"] = 0.0
	assert_eq(String(vp.ingest_remote_audio_frame(float_seq).get("reason", "")), "BAD_FRAME_SEQ_TYPE")

	var bad_rate := base.duplicate(true)
	bad_rate["sample_rate"] = "16000"
	assert_eq(String(vp.ingest_remote_audio_frame(bad_rate).get("reason", "")), "BAD_SAMPLE_RATE_TYPE")
	assert_eq(vp.remote_queue_size(1), 0)


func test_local_seat_matrix_remote_queues_dynamic() -> void:
	# 四席：本席拒绝远端输入；另外三席均有独立队列并可接收。
	for local in range(4):
		var vp := VoicePortModule.new()
		vp.bind_context(_trash_config("seat-matrix-%d" % local), local)
		assert_eq(vp.local_seat(), local)
		var pcm := _pcm_silence_frame()
		for seat in range(4):
			var frame := {
				"protocol_version": 1,
				"room_id": vp.room_id(),
				"session_id": vp.session_id(),
				"seat": seat,
				"utterance_id": "utt-l%d-s%d" % [local, seat],
				"frame_seq": 0,
				"sample_rate": 16000,
				"channels": 1,
				"sample_format": "PCM16_LE",
				"frame_duration_ms": 20,
				"pcm": pcm,
			}
			var r: Dictionary = vp.ingest_remote_audio_frame(frame)
			if seat == local:
				assert_false(r.get("ok", true), "local=%d 拒绝 seat=%d" % [local, seat])
				assert_eq(String(r.get("reason", "")), "INVALID_REMOTE_SEAT")
				assert_eq(vp.remote_queue_size(seat), 0)
			else:
				assert_true(r.get("ok", false), "local=%d 应接受 seat=%d: %s" % [local, seat, str(r)])
				assert_eq(vp.remote_queue_size(seat), 1)


func test_live_pipeline_dummy_driver_fails_closed_no_ptt_start() -> void:
	# 真实 VoiceCapturePipeline + VoicePort；headless 常为 Dummy，必须 fail-closed。
	var driver: String = AudioServer.get_driver_name()
	var vp := VoicePortModule.new()
	vp.bind_context(_trash_config("dummy-fc"), 0)
	vp.set_capture_backend(VoicePortModule.CaptureBackend.LIVE)
	var pipe := VoiceCapturePipeline.new()
	add_child_autofree(pipe)
	pipe.bind_voice_port(vp)
	var controls: Array = []
	vp.outbound_control.connect(func(m: Dictionary): controls.append(m.duplicate(true)))
	var unavailable: Array = []
	vp.microphone_unavailable.connect(func(): unavailable.append(true))

	if driver == "Dummy":
		assert_false(pipe.start_capture(), "Dummy 驱动不得 start_capture 成功")
		assert_false(pipe.is_active())
		assert_false(vp.press_ptt(), "Dummy 下 press_ptt 必须 false")
		assert_false(vp.is_ptt_pressed())
		assert_false(vp.is_capturing())
		assert_false(vp.has_live_microphone_nodes())
		assert_eq(controls.size(), 0, "不得发出 PTT_START")
		assert_eq(unavailable.size(), 1)
		assert_eq(vp.outbound_queue_size(), 0)
	else:
		# 非 Dummy 环境：至少保证接口可调用；不宣称真实麦克风已验证
		gut.p("AUDIO_DRIVER=%s — skip Dummy-only assertions" % driver)
