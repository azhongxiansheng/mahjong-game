class_name VoiceFrameQueue extends RefCounted

# E4-01（#243）：有界语音帧队列。背压丢最旧；同 utterance 拒重复/过期；允许跳帧。

var _capacity: int = 64
var _items: Array = []
var _dropped: int = 0
## utterance_id -> 已接受的最大 frame_seq（含）
var _max_seq_by_utt: Dictionary = {}


func _init(p_capacity: int = 64) -> void:
	_capacity = maxi(1, p_capacity)


func capacity() -> int:
	return _capacity


func size() -> int:
	return _items.size()


func dropped_count() -> int:
	return _dropped


func clear() -> void:
	_items.clear()
	_dropped = 0
	_max_seq_by_utt.clear()


func push(frame: Dictionary) -> Dictionary:
	if frame.is_empty():
		return {"ok": false, "reason": "EMPTY_FRAME"}
	var utt: String = String(frame.get("utterance_id", ""))
	if utt.is_empty():
		return {"ok": false, "reason": "EMPTY_UTTERANCE"}
	if not frame.has("frame_seq"):
		return {"ok": false, "reason": "MISSING_FRAME_SEQ"}
	var seq: int = int(frame["frame_seq"])
	if seq < 0:
		return {"ok": false, "reason": "NEGATIVE_FRAME_SEQ"}

	if _max_seq_by_utt.has(utt):
		var prev: int = int(_max_seq_by_utt[utt])
		if seq == prev:
			return {"ok": false, "reason": "DUPLICATE_FRAME"}
		if seq < prev:
			return {"ok": false, "reason": "STALE_FRAME"}
		# seq > prev：允许跳帧
		_max_seq_by_utt[utt] = seq
	else:
		_max_seq_by_utt[utt] = seq

	_items.append(frame.duplicate(true))
	while _items.size() > _capacity:
		_items.pop_front()
		_dropped += 1
	return {"ok": true, "reason": ""}


func pop() -> Dictionary:
	if _items.is_empty():
		return {}
	return _items.pop_front()


func peek() -> Dictionary:
	if _items.is_empty():
		return {}
	return _items[0]
