class_name VoiceBinaryCodec extends RefCounted

# E4-02（#244）：语音二进制帧编解码。
# 线格式：18 字节大端定长前缀 + UTF-8 utterance_id + 恰好 640 字节 PCM16LE。
# 前缀字段本身大端网络序；PCM 样本 little-endian。
# 二进制帧不携带 room_id/session_id/token。

const MAGIC := "MJVC"
const MAGIC_BYTES := [0x4D, 0x4A, 0x56, 0x43]  # M J V C
const PREFIX_LEN: int = 18
const PCM_BYTES: int = 640  # VoicePcmConverter.BYTES_PER_FRAME
const PROTOCOL_VERSION: int = 1
const SAMPLE_FORMAT_PCM16LE: int = 1
const CHANNELS: int = 1
const SAMPLE_RATE: int = 16000
const FRAME_DURATION_MS: int = 20
## utterance_id UTF-8 合理有界长度（不含 0）
const MAX_UTTERANCE_ID_BYTES: int = 128
const MIN_UTTERANCE_ID_BYTES: int = 1


static func encode_frame(meta: Dictionary, pcm: PackedByteArray) -> PackedByteArray:
	if pcm.size() != PCM_BYTES:
		return PackedByteArray()
	var utt: String = String(meta.get("utterance_id", ""))
	if utt.is_empty():
		return PackedByteArray()
	var utt_bytes: PackedByteArray = utt.to_utf8_buffer()
	if utt_bytes.size() < MIN_UTTERANCE_ID_BYTES or utt_bytes.size() > MAX_UTTERANCE_ID_BYTES:
		return PackedByteArray()
	var seat: int = int(meta.get("seat", -1))
	if seat < 0 or seat > 3:
		return PackedByteArray()
	var protocol_version: int = int(meta.get("protocol_version", PROTOCOL_VERSION))
	if protocol_version != PROTOCOL_VERSION:
		return PackedByteArray()
	var sample_format: int = int(meta.get("sample_format_code", SAMPLE_FORMAT_PCM16LE))
	if sample_format != SAMPLE_FORMAT_PCM16LE:
		return PackedByteArray()
	var channels: int = int(meta.get("channels", CHANNELS))
	if channels != CHANNELS:
		return PackedByteArray()
	var sample_rate: int = int(meta.get("sample_rate", SAMPLE_RATE))
	if sample_rate != SAMPLE_RATE:
		return PackedByteArray()
	var frame_duration_ms: int = int(meta.get("frame_duration_ms", FRAME_DURATION_MS))
	if frame_duration_ms != FRAME_DURATION_MS:
		return PackedByteArray()
	var frame_seq: int = int(meta.get("frame_seq", -1))
	if frame_seq < 0:
		return PackedByteArray()

	var sp := StreamPeerBuffer.new()
	sp.big_endian = true
	sp.put_data(PackedByteArray(MAGIC_BYTES))
	sp.put_u8(protocol_version)
	sp.put_u8(seat)
	sp.put_u8(sample_format)
	sp.put_u8(channels)
	sp.put_u16(sample_rate)
	sp.put_u16(frame_duration_ms)
	sp.put_u32(frame_seq)
	sp.put_u16(utt_bytes.size())
	sp.put_data(utt_bytes)
	sp.put_data(pcm)
	var out: PackedByteArray = sp.data_array
	var expected: int = PREFIX_LEN + utt_bytes.size() + PCM_BYTES
	if out.size() != expected:
		return PackedByteArray()
	return out


## 成功返回字典；失败返回 {}。
## 解码结果仅含线字段；room_id/session_id 由已鉴权连接绑定侧重建。
static func decode_frame(raw: PackedByteArray) -> Dictionary:
	if raw.size() < PREFIX_LEN + MIN_UTTERANCE_ID_BYTES + PCM_BYTES:
		return {}
	if raw[0] != MAGIC_BYTES[0] or raw[1] != MAGIC_BYTES[1] \
			or raw[2] != MAGIC_BYTES[2] or raw[3] != MAGIC_BYTES[3]:
		return {}
	var sp := StreamPeerBuffer.new()
	sp.big_endian = true
	sp.data_array = raw
	sp.seek(0)
	var _magic: PackedByteArray = sp.get_data(4)[1]
	var protocol_version: int = sp.get_u8()
	var seat: int = sp.get_u8()
	var sample_format: int = sp.get_u8()
	var channels: int = sp.get_u8()
	var sample_rate: int = sp.get_u16()
	var frame_duration_ms: int = sp.get_u16()
	var frame_seq: int = sp.get_u32()
	var utt_len: int = sp.get_u16()
	if protocol_version != PROTOCOL_VERSION:
		return {}
	if seat < 0 or seat > 3:
		return {}
	if sample_format != SAMPLE_FORMAT_PCM16LE:
		return {}
	if channels != CHANNELS:
		return {}
	if sample_rate != SAMPLE_RATE:
		return {}
	if frame_duration_ms != FRAME_DURATION_MS:
		return {}
	if utt_len < MIN_UTTERANCE_ID_BYTES or utt_len > MAX_UTTERANCE_ID_BYTES:
		return {}
	var expected_total: int = PREFIX_LEN + utt_len + PCM_BYTES
	if raw.size() != expected_total:
		return {}
	var utt_data: PackedByteArray = sp.get_data(utt_len)[1]
	var pcm: PackedByteArray = sp.get_data(PCM_BYTES)[1]
	if utt_data.size() != utt_len or pcm.size() != PCM_BYTES:
		return {}
	var utterance_id: String = utt_data.get_string_from_utf8()
	if utterance_id.is_empty() or utterance_id.to_utf8_buffer().size() != utt_len:
		return {}
	return {
		"protocol_version": protocol_version,
		"seat": seat,
		"sample_format_code": sample_format,
		"sample_format": VoicePcmConverter.SAMPLE_FORMAT,
		"channels": channels,
		"sample_rate": sample_rate,
		"frame_duration_ms": frame_duration_ms,
		"frame_seq": frame_seq,
		"utterance_id": utterance_id,
		"pcm": pcm,
	}


## 从 VoicePort 出站帧字典编码。
static func encode_from_voice_port_frame(frame: Dictionary) -> PackedByteArray:
	if frame.is_empty():
		return PackedByteArray()
	var pcm: Variant = frame.get("pcm", null)
	if not (pcm is PackedByteArray):
		return PackedByteArray()
	var meta := {
		"protocol_version": int(frame.get("protocol_version", PROTOCOL_VERSION)),
		"seat": int(frame.get("seat", -1)),
		"sample_format_code": SAMPLE_FORMAT_PCM16LE,
		"channels": int(frame.get("channels", CHANNELS)),
		"sample_rate": int(frame.get("sample_rate", SAMPLE_RATE)),
		"frame_duration_ms": int(frame.get("frame_duration_ms", FRAME_DURATION_MS)),
		"frame_seq": int(frame.get("frame_seq", -1)),
		"utterance_id": String(frame.get("utterance_id", "")),
	}
	return encode_frame(meta, pcm as PackedByteArray)


## 用连接绑定上下文重建 #243 VoicePortModule.ingest_remote_audio_frame 契约。
static func to_voice_port_frame(decoded: Dictionary, room_id: String, session_id: String) -> Dictionary:
	if decoded.is_empty() or room_id.is_empty() or session_id.is_empty():
		return {}
	return {
		"protocol_version": int(decoded.get("protocol_version", PROTOCOL_VERSION)),
		"room_id": room_id,
		"session_id": session_id,
		"seat": int(decoded.get("seat", -1)),
		"utterance_id": String(decoded.get("utterance_id", "")),
		"frame_seq": int(decoded.get("frame_seq", -1)),
		"sample_rate": int(decoded.get("sample_rate", SAMPLE_RATE)),
		"channels": int(decoded.get("channels", CHANNELS)),
		"sample_format": String(decoded.get("sample_format", VoicePcmConverter.SAMPLE_FORMAT)),
		"frame_duration_ms": int(decoded.get("frame_duration_ms", FRAME_DURATION_MS)),
		"pcm": decoded.get("pcm", PackedByteArray()),
	}
