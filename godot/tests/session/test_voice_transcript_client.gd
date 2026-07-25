extends GutTest

# #247：VoiceRelayClient 必须接受 TRANSCRIPT_* 并发出 transcript_caption。


func test_client_emits_transcript_caption_for_same_room() -> void:
	var c := VoiceRelayClient.new()
	add_child_autofree(c)
	# 注入已 join 身份（不经真实 WS）
	c._room_id = "room_cap"
	c._seat = 0
	c._session_id = "s0"
	c._joined = true
	var got: Array = []
	c.transcript_caption.connect(func(m): got.append(m))
	c._handle_text(JSON.stringify({
		"protocol_version": 1,
		"kind": "TRANSCRIPT_FINAL",
		"room_id": "room_cap",
		"seat": 1,
		"hand_seq": 0,
		"window_id": "w1",
		"utterance_id": "u1",
		"ptt_end_server_seq": 9,
		"source": "faster_whisper",
		"lang": "zh",
		"text": "字幕",
		"is_final": true,
	}))
	assert_eq(got.size(), 1)
	assert_eq(str(got[0].get("text", "")), "字幕")


func test_client_drops_cross_room_transcript() -> void:
	var c := VoiceRelayClient.new()
	add_child_autofree(c)
	c._room_id = "room_a"
	c._joined = true
	var got: Array = []
	c.transcript_caption.connect(func(m): got.append(m))
	c._handle_text(JSON.stringify({
		"protocol_version": 1,
		"kind": "TRANSCRIPT_PARTIAL",
		"room_id": "room_b",
		"seat": 0,
		"hand_seq": 0,
		"window_id": "w",
		"utterance_id": "u",
		"source": "faster_whisper",
		"lang": "zh",
		"text": "x",
		"is_final": false,
	}))
	assert_eq(got.size(), 0)


func test_client_accepts_new_api_final_and_keeps_source() -> void:
	# #248：final source=new_api 须接受且不改写
	var c := VoiceRelayClient.new()
	add_child_autofree(c)
	c._room_id = "room_napi"
	c._seat = 0
	c._session_id = "s0"
	c._joined = true
	var got: Array = []
	c.transcript_caption.connect(func(m): got.append(m))
	c._handle_text(JSON.stringify({
		"protocol_version": 1,
		"kind": "TRANSCRIPT_FINAL",
		"room_id": "room_napi",
		"seat": 2,
		"hand_seq": 1,
		"window_id": "w1",
		"utterance_id": "u_napi",
		"ptt_end_server_seq": 12,
		"source": "new_api",
		"lang": "en",
		"text": "backup caption",
		"is_final": true,
	}))
	assert_eq(got.size(), 1)
	assert_eq(str(got[0].get("source", "")), "new_api")
	assert_eq(str(got[0].get("text", "")), "backup caption")


func test_client_rejects_new_api_partial() -> void:
	# partial 永不走备份；伪造 new_api partial 必须拒绝
	var c := VoiceRelayClient.new()
	add_child_autofree(c)
	c._room_id = "room_napi"
	c._joined = true
	var got: Array = []
	c.transcript_caption.connect(func(m): got.append(m))
	c._handle_text(JSON.stringify({
		"protocol_version": 1,
		"kind": "TRANSCRIPT_PARTIAL",
		"room_id": "room_napi",
		"seat": 1,
		"hand_seq": 0,
		"window_id": "w1",
		"utterance_id": "u_p",
		"source": "new_api",
		"lang": "zh",
		"text": "fake partial",
		"is_final": false,
	}))
	assert_eq(got.size(), 0)


func test_client_rejects_unknown_source() -> void:
	var c := VoiceRelayClient.new()
	add_child_autofree(c)
	c._room_id = "room_napi"
	c._joined = true
	var got: Array = []
	c.transcript_caption.connect(func(m): got.append(m))
	c._handle_text(JSON.stringify({
		"protocol_version": 1,
		"kind": "TRANSCRIPT_FINAL",
		"room_id": "room_napi",
		"seat": 0,
		"hand_seq": 0,
		"window_id": "w1",
		"utterance_id": "u_bad",
		"ptt_end_server_seq": 3,
		"source": "evil_vendor",
		"lang": "zh",
		"text": "nope",
		"is_final": true,
	}))
	assert_eq(got.size(), 0)
