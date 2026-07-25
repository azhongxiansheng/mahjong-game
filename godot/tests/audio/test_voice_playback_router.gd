extends GutTest

# E4-01（#243）：远端分座位播放入口接到真实 VoicePort + AudioStreamGenerator 节点。


func _trash_config() -> GameSessionConfig:
	var intent := SessionIntent.new(&"PRACTICE", &"EAST", &"TRASH_TALK", &"lin_yeche")
	var converted := GameSessionConfig.from_intent(
		intent, 11, "play-sess", "e4-01-v1", {}
	)
	assert_true(converted.ok)
	return converted.config


func _sine_pcm16_frame(freq: float = 440.0) -> PackedByteArray:
	var pcm := PackedByteArray()
	pcm.resize(640)
	for i in range(320):
		var s: float = sin(TAU * freq * float(i) / 16000.0) * 0.5
		var q: int = clampi(int(round(s * 32767.0)), -32768, 32767)
		if q < 0:
			q += 65536
		pcm[i * 2] = q & 0xFF
		pcm[i * 2 + 1] = (q >> 8) & 0xFF
	return pcm


func test_bind_creates_players_for_remote_seats_only() -> void:
	var vp := VoicePortModule.new()
	vp.bind_context(_trash_config(), 0)
	var router := VoicePlaybackRouter.new()
	add_child_autofree(router)
	router.bind_voice_port(vp)
	await get_tree().process_frame
	assert_true(router.has_player_for_seat(1))
	assert_true(router.has_player_for_seat(2))
	assert_true(router.has_player_for_seat(3))
	assert_false(router.has_player_for_seat(0), "本席不建远端播放节点")


func test_remote_frame_via_voice_port_pushes_generator_frames() -> void:
	var vp := VoicePortModule.new()
	vp.bind_context(_trash_config(), 0)
	var router := VoicePlaybackRouter.new()
	add_child_autofree(router)
	router.bind_voice_port(vp)
	await get_tree().process_frame

	var frame := {
		"protocol_version": 1,
		"room_id": vp.room_id(),
		"session_id": vp.session_id(),
		"seat": 2,
		"utterance_id": "utt-play",
		"frame_seq": 0,
		"sample_rate": 16000,
		"channels": 1,
		"sample_format": "PCM16_LE",
		"frame_duration_ms": 20,
		"pcm": _sine_pcm16_frame(),
	}
	var r: Dictionary = vp.ingest_remote_audio_frame(frame)
	assert_true(r.get("ok", false), str(r))
	# 让 router process 消费队列
	for _i in range(5):
		await get_tree().process_frame
	assert_gt(router.frames_pushed_for_seat(2), 0, "须经真实入口推入 Generator")
	assert_eq(router.frames_pushed_for_seat(1), 0)


func test_release_stops_and_clears_players() -> void:
	var vp := VoicePortModule.new()
	vp.bind_context(_trash_config(), 0)
	var router := VoicePlaybackRouter.new()
	add_child_autofree(router)
	router.bind_voice_port(vp)
	await get_tree().process_frame
	router.release_all()
	assert_false(router.has_player_for_seat(1))
	assert_false(router.has_player_for_seat(2))
	assert_false(router.has_player_for_seat(3))


func test_local_seat_matrix_players_exclude_self() -> void:
	# local seat 0/1/2/3：本席无播放器，另外三席均有。
	for local in range(4):
		var vp := VoicePortModule.new()
		vp.bind_context(_trash_config(), local)
		var router := VoicePlaybackRouter.new()
		add_child_autofree(router)
		router.bind_voice_port(vp)
		await get_tree().process_frame
		for seat in range(4):
			if seat == local:
				assert_false(
					router.has_player_for_seat(seat),
					"local=%d 不得为本席建播放器" % local
				)
			else:
				assert_true(
					router.has_player_for_seat(seat),
					"local=%d 须为远端 seat=%d 建播放器" % [local, seat]
				)
		# 远端 seat0（当 local!=0）可接收并推帧
		if local != 0:
			var frame := {
				"protocol_version": 1,
				"room_id": vp.room_id(),
				"session_id": vp.session_id(),
				"seat": 0,
				"utterance_id": "utt-seat0-from-%d" % local,
				"frame_seq": 0,
				"sample_rate": 16000,
				"channels": 1,
				"sample_format": "PCM16_LE",
				"frame_duration_ms": 20,
				"pcm": _sine_pcm16_frame(),
			}
			assert_true(vp.ingest_remote_audio_frame(frame).get("ok", false))
			for _i in range(5):
				await get_tree().process_frame
			assert_gt(router.frames_pushed_for_seat(0), 0, "local=%d 应播放 seat0" % local)
		router.release_all()
