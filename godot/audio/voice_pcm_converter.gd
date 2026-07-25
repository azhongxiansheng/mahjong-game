class_name VoicePcmConverter extends RefCounted

# E4-01（#243）：立体声 float32 → mono → 流式重采样到 16kHz → PCM16 LE 20ms 帧。
# 保留相位/余数，适配实际 mix rate（不假设固定 48k）。

const TARGET_SAMPLE_RATE: int = 16000
const CHANNELS: int = 1
const FRAME_DURATION_MS: int = 20
const SAMPLES_PER_FRAME: int = 320  # 16000 * 0.02
const BYTES_PER_FRAME: int = 640  # 320 * 2
const SAMPLE_FORMAT: String = "PCM16_LE"

var _src_rate: int = TARGET_SAMPLE_RATE
var _mono_buf: PackedFloat32Array = PackedFloat32Array()
var _read_pos: float = 0.0
var _out_mono: PackedFloat32Array = PackedFloat32Array()


func reset(source_sample_rate: int) -> void:
	_src_rate = maxi(1, source_sample_rate)
	_mono_buf = PackedFloat32Array()
	_read_pos = 0.0
	_out_mono = PackedFloat32Array()


func pending_sample_count() -> int:
	return _out_mono.size()


## 推入 stereo float32（[-1,1]），返回完整 20ms PCM16 LE 帧数组（PackedByteArray）。
func push_stereo(stereo: PackedVector2Array) -> Array:
	if stereo.is_empty():
		return []
	for v in stereo:
		_mono_buf.append((v.x + v.y) * 0.5)
	_resample_available()
	return _drain_complete_frames()


## 清空 pending；不足一帧的数据丢弃（不补零帧）。
func flush() -> Array:
	var frames: Array = _drain_complete_frames()
	_mono_buf = PackedFloat32Array()
	_read_pos = 0.0
	_out_mono = PackedFloat32Array()
	return frames


func _resample_available() -> void:
	if _src_rate == TARGET_SAMPLE_RATE:
		# 1:1：直接消费 mono
		while int(_read_pos) < _mono_buf.size():
			_out_mono.append(_mono_buf[int(_read_pos)])
			_read_pos += 1.0
		_compact_mono_buf()
		return

	var step: float = float(_src_rate) / float(TARGET_SAMPLE_RATE)
	# 需要 _read_pos 与 _read_pos+1 都在缓冲内才能线性插值
	while _read_pos + 1.0 < float(_mono_buf.size()):
		var i0: int = int(floor(_read_pos))
		var frac: float = _read_pos - float(i0)
		var s0: float = _mono_buf[i0]
		var s1: float = _mono_buf[i0 + 1]
		_out_mono.append(s0 + (s1 - s0) * frac)
		_read_pos += step
	_compact_mono_buf()


func _compact_mono_buf() -> void:
	var drop: int = int(floor(_read_pos))
	if drop <= 0:
		return
	if drop >= _mono_buf.size():
		_mono_buf = PackedFloat32Array()
		_read_pos = 0.0
		return
	var kept := PackedFloat32Array()
	for i in range(drop, _mono_buf.size()):
		kept.append(_mono_buf[i])
	_mono_buf = kept
	_read_pos -= float(drop)


func _drain_complete_frames() -> Array:
	var frames: Array = []
	while _out_mono.size() >= SAMPLES_PER_FRAME:
		var pcm := PackedByteArray()
		pcm.resize(BYTES_PER_FRAME)
		for i in range(SAMPLES_PER_FRAME):
			var q: int = _float_to_pcm16(_out_mono[i])
			pcm.encode_s16(i * 2, q)
		frames.append(pcm)
		var rest := PackedFloat32Array()
		for i in range(SAMPLES_PER_FRAME, _out_mono.size()):
			rest.append(_out_mono[i])
		_out_mono = rest
	return frames


static func _float_to_pcm16(s: float) -> int:
	var c: float = clampf(s, -1.0, 1.0)
	if c >= 1.0:
		return 32767
	if c <= -1.0:
		return -32768
	return int(round(c * 32767.0))


## PCM16 LE mono 帧 → stereo float frames（播放侧）。
static func pcm16_mono_to_stereo_frames(pcm: PackedByteArray) -> PackedVector2Array:
	var out := PackedVector2Array()
	if pcm == null or pcm.size() < 2:
		return out
	# 显式整除，避免 integer_division warning
	var n: int = int(pcm.size() >> 1)
	out.resize(n)
	for i in range(n):
		var s: int = pcm.decode_s16(i * 2)
		var f: float = float(s) / 32768.0
		out[i] = Vector2(f, f)
	return out
