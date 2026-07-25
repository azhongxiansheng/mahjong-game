extends GutTest

# E4-01（#243）：有界语音帧队列 — 背压丢最旧、拒重复/过期、允许跳帧。


func _meta(utt: String, seq: int, seat: int = 1) -> Dictionary:
	return {
		"protocol_version": 1,
		"room_id": "room-x",
		"session_id": "sess-x",
		"seat": seat,
		"utterance_id": utt,
		"frame_seq": seq,
		"sample_rate": 16000,
		"channels": 1,
		"sample_format": "PCM16_LE",
		"frame_duration_ms": 20,
		"pcm": PackedByteArray(),
	}


func test_capacity_drops_oldest() -> void:
	var q := VoiceFrameQueue.new(3)
	assert_eq(q.capacity(), 3)
	for i in range(4):
		var r: Dictionary = q.push(_meta("u1", i))
		assert_true(r.get("ok", false), "push %d" % i)
	assert_eq(q.size(), 3)
	assert_eq(q.dropped_count(), 1)
	var first: Dictionary = q.pop()
	assert_eq(int(first.get("frame_seq", -1)), 1, "应丢弃 frame_seq=0")


func test_reject_duplicate_frame_seq_same_utterance() -> void:
	var q := VoiceFrameQueue.new(8)
	assert_true(q.push(_meta("u1", 0)).get("ok", false))
	var dup: Dictionary = q.push(_meta("u1", 0))
	assert_false(dup.get("ok", true))
	assert_eq(String(dup.get("reason", "")), "DUPLICATE_FRAME")
	assert_eq(q.size(), 1)


func test_reject_stale_frame_seq() -> void:
	var q := VoiceFrameQueue.new(8)
	assert_true(q.push(_meta("u1", 0)).get("ok", false))
	assert_true(q.push(_meta("u1", 2)).get("ok", false), "允许跳帧 0→2")
	var stale: Dictionary = q.push(_meta("u1", 1))
	assert_false(stale.get("ok", true))
	assert_eq(String(stale.get("reason", "")), "STALE_FRAME")
	assert_eq(q.size(), 2)


func test_allow_gap_and_new_utterance_resets_tracking() -> void:
	var q := VoiceFrameQueue.new(8)
	assert_true(q.push(_meta("u1", 0)).get("ok", false))
	assert_true(q.push(_meta("u1", 5)).get("ok", false), "跳帧合法")
	assert_true(q.push(_meta("u2", 0)).get("ok", false), "新 utterance 从 0 重新开始")
	assert_eq(q.size(), 3)


func test_clear_empties_and_resets_state() -> void:
	var q := VoiceFrameQueue.new(4)
	q.push(_meta("u1", 0))
	q.push(_meta("u1", 1))
	q.clear()
	assert_eq(q.size(), 0)
	assert_eq(q.dropped_count(), 0)
	assert_true(q.push(_meta("u1", 0)).get("ok", false), "清空后可重新收 frame_seq=0")
