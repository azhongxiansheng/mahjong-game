extends GutTest

# E4-01（#243）：PCM 下混、流式重采样、量化与 20ms 分帧。
# 真实 VoicePcmConverter；不 mock 核心转换逻辑。


func test_frame_constants() -> void:
	assert_eq(VoicePcmConverter.TARGET_SAMPLE_RATE, 16000)
	assert_eq(VoicePcmConverter.CHANNELS, 1)
	assert_eq(VoicePcmConverter.FRAME_DURATION_MS, 20)
	assert_eq(VoicePcmConverter.SAMPLES_PER_FRAME, 320)
	assert_eq(VoicePcmConverter.BYTES_PER_FRAME, 640)
	assert_eq(VoicePcmConverter.SAMPLE_FORMAT, "PCM16_LE")


func test_stereo_downmix_to_mono_average() -> void:
	var c := VoicePcmConverter.new()
	c.reset(16000)
	# L=1.0 R=-1.0 → mono 0.0
	var stereo := PackedVector2Array([Vector2(1.0, -1.0), Vector2(0.5, 0.5)])
	var frames: Array = c.push_stereo(stereo)
	# 2 samples @ 16k already mono but not enough for a 320-sample frame
	assert_eq(frames.size(), 0)
	assert_eq(c.pending_sample_count(), 2)


func test_quantization_clamps_and_pcm16_le() -> void:
	var c := VoicePcmConverter.new()
	c.reset(16000)
	var samples := PackedVector2Array()
	for i in range(320):
		var v: float = 2.0 if i < 160 else -2.0
		samples.append(Vector2(v, v))
	var frames: Array = c.push_stereo(samples)
	assert_eq(frames.size(), 1)
	var pcm: PackedByteArray = frames[0]
	assert_eq(pcm.size(), 640)
	# first sample +1.0 → 32767 little-endian
	assert_eq(pcm[0], 0xFF)
	assert_eq(pcm[1], 0x7F)
	# sample 160 = -1.0 → -32768 little-endian
	assert_eq(pcm[320], 0x00)
	assert_eq(pcm[321], 0x80)


func test_exactly_one_frame_at_16k_for_20ms() -> void:
	var c := VoicePcmConverter.new()
	c.reset(16000)
	var samples := PackedVector2Array()
	for i in range(320):
		var t: float = sin(float(i) * 0.1) * 0.25
		samples.append(Vector2(t, t))
	var frames: Array = c.push_stereo(samples)
	assert_eq(frames.size(), 1)
	assert_eq((frames[0] as PackedByteArray).size(), 640)
	assert_eq(c.pending_sample_count(), 0)


func test_resample_48k_to_16k_frame_count() -> void:
	# 20ms @ 48k = 960 stereo samples → 320 @ 16k = 1 frame
	var c := VoicePcmConverter.new()
	c.reset(48000)
	var samples := PackedVector2Array()
	for i in range(960):
		var t: float = sin(float(i) * 0.05) * 0.5
		samples.append(Vector2(t, t * 0.8))
	var frames: Array = c.push_stereo(samples)
	assert_eq(frames.size(), 1)
	assert_eq((frames[0] as PackedByteArray).size(), 640)


func test_resample_44100_chunk_continuity() -> void:
	# 流式两段：保留相位/余数，合起来应与一次推入等价帧数
	var c1 := VoicePcmConverter.new()
	c1.reset(44100)
	var c2 := VoicePcmConverter.new()
	c2.reset(44100)
	var all := PackedVector2Array()
	# ~60ms @ 44.1k ≈ 2646 samples → ~960 @ 16k → 3 frames
	for i in range(2646):
		var t: float = sin(float(i) * 0.03) * 0.4
		all.append(Vector2(t, t))
	var once: Array = c1.push_stereo(all)
	var mid: int = 1323
	var part_a := PackedVector2Array()
	var part_b := PackedVector2Array()
	for i in range(mid):
		part_a.append(all[i])
	for i in range(mid, all.size()):
		part_b.append(all[i])
	var streamed: Array = []
	streamed.append_array(c2.push_stereo(part_a))
	streamed.append_array(c2.push_stereo(part_b))
	assert_eq(streamed.size(), once.size())
	assert_true(streamed.size() >= 2, "应产出多帧以验证分块连续性")
	# 逐帧字节应一致（确定性线性插值）
	for i in range(once.size()):
		assert_eq(
			(streamed[i] as PackedByteArray),
			(once[i] as PackedByteArray),
			"分块重采样帧 %d 必须与一次推入一致" % i
		)


func test_partial_frame_held_across_pushes() -> void:
	var c := VoicePcmConverter.new()
	c.reset(16000)
	var a := PackedVector2Array()
	for i in range(100):
		a.append(Vector2(0.1, 0.1))
	assert_eq(c.push_stereo(a).size(), 0)
	var b := PackedVector2Array()
	for i in range(220):
		b.append(Vector2(0.1, 0.1))
	var frames: Array = c.push_stereo(b)
	assert_eq(frames.size(), 1)
	assert_eq(c.pending_sample_count(), 0)


func test_flush_does_not_pad_incomplete_frame() -> void:
	var c := VoicePcmConverter.new()
	c.reset(16000)
	var a := PackedVector2Array()
	for i in range(100):
		a.append(Vector2(0.2, 0.2))
	c.push_stereo(a)
	var flushed: Array = c.flush()
	assert_eq(flushed.size(), 0, "不足 20ms 不得强行补帧")
	assert_eq(c.pending_sample_count(), 0)
