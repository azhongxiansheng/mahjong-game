extends GutTest

# E4-02（#244）：语音二进制帧编解码契约。


func _pcm640(fill: int = 0x11) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(VoiceBinaryCodec.PCM_BYTES)
	for i in range(p.size()):
		p[i] = fill & 0xFF
	return p


func test_roundtrip_exact_length_and_fields() -> void:
	var pcm := _pcm640(0xAB)
	var raw: PackedByteArray = VoiceBinaryCodec.encode_frame({
		"protocol_version": 1,
		"seat": 2,
		"sample_format_code": 1,
		"channels": 1,
		"sample_rate": 16000,
		"frame_duration_ms": 20,
		"frame_seq": 7,
		"utterance_id": "utt-abc",
	}, pcm)
	assert_false(raw.is_empty())
	var utt_len: int = "utt-abc".to_utf8_buffer().size()
	assert_eq(raw.size(), 18 + utt_len + 640)
	# magic MJVC big-endian prefix start
	assert_eq(raw[0], 0x4D)
	assert_eq(raw[1], 0x4A)
	assert_eq(raw[2], 0x56)
	assert_eq(raw[3], 0x43)
	var dec: Dictionary = VoiceBinaryCodec.decode_frame(raw)
	assert_false(dec.is_empty())
	assert_eq(int(dec["seat"]), 2)
	assert_eq(int(dec["frame_seq"]), 7)
	assert_eq(String(dec["utterance_id"]), "utt-abc")
	assert_eq(int(dec["sample_rate"]), 16000)
	assert_eq(int(dec["channels"]), 1)
	assert_eq(int(dec["frame_duration_ms"]), 20)
	assert_eq(String(dec["sample_format"]), "PCM16_LE")
	assert_eq((dec["pcm"] as PackedByteArray).size(), 640)
	assert_eq((dec["pcm"] as PackedByteArray)[0], 0xAB)


func test_reject_wrong_total_length_and_empty_utt() -> void:
	var pcm := _pcm640()
	var ok: PackedByteArray = VoiceBinaryCodec.encode_frame({
		"protocol_version": 1,
		"seat": 0,
		"sample_format_code": 1,
		"channels": 1,
		"sample_rate": 16000,
		"frame_duration_ms": 20,
		"frame_seq": 0,
		"utterance_id": "u1",
	}, pcm)
	assert_false(ok.is_empty())
	var truncated: PackedByteArray = ok.slice(0, ok.size() - 1)
	assert_true(VoiceBinaryCodec.decode_frame(truncated).is_empty())
	var padded: PackedByteArray = ok.duplicate()
	padded.append(0)
	assert_true(VoiceBinaryCodec.decode_frame(padded).is_empty())
	assert_true(VoiceBinaryCodec.encode_frame({
		"protocol_version": 1,
		"seat": 0,
		"sample_format_code": 1,
		"channels": 1,
		"sample_rate": 16000,
		"frame_duration_ms": 20,
		"frame_seq": 0,
		"utterance_id": "",
	}, pcm).is_empty())


func test_to_voice_port_frame_rebuilds_session_contract() -> void:
	var pcm := _pcm640(0x22)
	var raw: PackedByteArray = VoiceBinaryCodec.encode_frame({
		"protocol_version": 1,
		"seat": 1,
		"sample_format_code": 1,
		"channels": 1,
		"sample_rate": 16000,
		"frame_duration_ms": 20,
		"frame_seq": 3,
		"utterance_id": "utt-x",
	}, pcm)
	var dec: Dictionary = VoiceBinaryCodec.decode_frame(raw)
	var rebuilt: Dictionary = VoiceBinaryCodec.to_voice_port_frame(dec, "room-a", "sess-b")
	assert_eq(String(rebuilt["room_id"]), "room-a")
	assert_eq(String(rebuilt["session_id"]), "sess-b")
	assert_eq(int(rebuilt["seat"]), 1)
	assert_eq(int(rebuilt["frame_seq"]), 3)
	assert_eq(String(rebuilt["sample_format"]), "PCM16_LE")
	assert_eq((rebuilt["pcm"] as PackedByteArray).size(), 640)
