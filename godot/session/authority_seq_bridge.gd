class_name AuthoritySeqBridge extends RefCounted

# E4-02（#244 round-3）：跨通道权威序号唯一所有权在 Bridge。
# - 未来 game 事件与 side marker 只在此 hold；
# - NBC 仅接受恰好 expected_next 的 side marker / game 事件；
# - 可注入时钟 + tick：有界等待后触发 NBC 既有 gap→resync 语义。
# 网络端到端未验证。

const MAX_HELD: int = 32
## 默认等待窗口（毫秒）；测试可改
const DEFAULT_HOLD_WINDOW_MS: int = 500

var _nbc: NetworkedBattleController = null
## server_seq -> NetworkedEvent
var _held_game: Dictionary = {}
var _held_game_order: Array = []
## server_seq -> true（侧通道 marker，不进 journal）
var _held_side: Dictionary = {}
var _held_side_order: Array = []
## 最早 pending 的截止时刻；-1 表示无等待
var _hold_deadline_ms: int = -1
var _hold_window_ms: int = DEFAULT_HOLD_WINDOW_MS
## 可注入单调时钟；-1 用 Time.get_ticks_msec()
var clock_now_ms: int = -1
var _epoch: int = 0


func bind_networked_controller(nbc: NetworkedBattleController) -> void:
	_nbc = nbc
	clear()


func set_hold_window_ms(ms: int) -> void:
	_hold_window_ms = maxi(1, ms)


func set_clock_ms_for_test(ms: int) -> void:
	clock_now_ms = ms


func now_ms() -> int:
	if clock_now_ms >= 0:
		return clock_now_ms
	return Time.get_ticks_msec()


func clear() -> void:
	_held_game.clear()
	_held_game_order.clear()
	_held_side.clear()
	_held_side_order.clear()
	_hold_deadline_ms = -1
	_epoch += 1


func held_game_count() -> int:
	return _held_game.size()


func held_side_count() -> int:
	return _held_side.size()


func hold_deadline_ms() -> int:
	return _hold_deadline_ms


## 语音权威 PTT_END 等：仅当 seq==expected 时推进 NBC；否则 Bridge 持有。
func on_side_channel_authority_seq(seq: int) -> Dictionary:
	if _nbc == null:
		return {"ok": false, "reason": "NO_NBC"}
	if _nbc.resync_required():
		return {"ok": false, "reason": "RESYNC_REQUIRED"}
	if seq <= 0:
		return {"ok": false, "reason": "INVALID_SEQ"}
	var expected: int = _nbc.expected_next_server_seq()
	if seq < expected or seq <= _nbc.current_seq():
		return {"ok": true, "advanced": false, "reason": "ALREADY_PASSED"}
	if seq == expected:
		var r: Dictionary = _nbc.observe_side_channel_authority_seq(seq)
		_drain()
		return r
	# 未来 marker
	if _held_side.has(seq):
		return {"ok": true, "advanced": false, "reason": "ALREADY_HELD_SIDE"}
	if _held_side.size() + _held_game.size() >= MAX_HELD:
		return _timeout_force_resync("SIDE_OVERFLOW")
	_held_side[seq] = true
	_held_side_order.append(seq)
	_arm_deadline()
	_drain()
	if _nbc.current_seq() >= seq:
		return {"ok": true, "advanced": true, "reason": "DRAINED"}
	return {"ok": true, "advanced": false, "reason": "HELD_SIDE"}


## 牌局事件：仅 expected 时 ingest；未来有界 hold；超时 tick 触发 resync。
func on_game_networked_event(ev: Variant) -> Dictionary:
	if _nbc == null:
		return {"ok": false, "reason": "NO_NBC", "applied": false}
	var ne: NetworkedEvent = null
	if ev is NetworkedEvent:
		ne = ev as NetworkedEvent
	elif typeof(ev) == TYPE_DICTIONARY:
		ne = NetworkedEvent.from_dict(ev)
	if ne == null:
		return {"ok": false, "reason": "BAD_EVENT", "applied": false}
	if _nbc.resync_required():
		return {"ok": false, "reason": "RESYNC_REQUIRED", "applied": false}

	var seq: int = int(ne.server_seq)
	var expected: int = _nbc.expected_next_server_seq()

	# ROOM_SNAPSHOT：先尝试提交；失败不得先破坏 pending。
	# 成功后仅清理 seq <= committed 的 hold，保留更高序号 future side/game 再 drain。
	if ne.kind == "ROOM_SNAPSHOT":
		if ne.room_id != _nbc.room_id:
			# 跨房：新 epoch，整清
			clear()
		var ok_snap: bool = _nbc.ingest_networked_event(ne)
		if not ok_snap:
			return {
				"ok": false,
				"reason": "SNAPSHOT_REJECTED",
				"applied": false,
				"error": _nbc.last_snapshot_error() if _nbc.has_method("last_snapshot_error") else "",
			}
		_prune_held_upto(_nbc.current_seq())
		_drain()
		return {"ok": true, "reason": "SNAPSHOT", "applied": true}

	if seq < expected:
		var ig: bool = _nbc.ingest_networked_event(ne)
		return {"ok": ig, "reason": "STALE_OR_DUP", "applied": ig}
	if seq == expected:
		var ok: bool = _nbc.ingest_networked_event(ne)
		if ok:
			_drain()
		return {"ok": ok, "reason": "", "applied": ok}

	# 未来非 snapshot 业务事件：hold，等待 side 填洞
	if _held_game.has(seq):
		return {"ok": true, "reason": "ALREADY_HELD_GAME", "applied": false}
	if _held_side.size() + _held_game.size() >= MAX_HELD:
		return _timeout_force_resync("GAME_OVERFLOW")
	_held_game[seq] = ne
	_held_game_order.append(seq)
	_arm_deadline()
	_drain()
	if not _held_game.has(seq):
		return {"ok": true, "reason": "APPLIED_AFTER_DRAIN", "applied": true}
	return {"ok": true, "reason": "HELD_FOR_SIDE_CHANNEL", "applied": false}


## 显式时钟推进：窗口超时且仍缺 seq → 强制 resync。
func tick(p_now_ms: int = -1) -> Dictionary:
	if _nbc == null:
		return {"ok": false, "reason": "NO_NBC"}
	if p_now_ms >= 0:
		clock_now_ms = p_now_ms
	if _hold_deadline_ms < 0:
		return {"ok": true, "reason": "NO_PENDING", "resync": _nbc.resync_required()}
	if now_ms() < _hold_deadline_ms:
		return {"ok": true, "reason": "WAITING", "resync": false}
	return _timeout_force_resync("TIMEOUT")


func _arm_deadline() -> void:
	if _hold_deadline_ms < 0:
		_hold_deadline_ms = now_ms() + _hold_window_ms


func _clear_deadline_if_idle() -> void:
	if _held_game.is_empty() and _held_side.is_empty():
		_hold_deadline_ms = -1


## 清理已被 snapshot/committed 覆盖的 hold；保留更高序号 future。
func _prune_held_upto(committed: int) -> void:
	var side_keys: Array = _held_side.keys()
	for k in side_keys:
		if int(k) <= committed:
			_held_side.erase(k)
	_held_side_order = _held_side_order.filter(func(s): return int(s) > committed)
	var game_keys: Array = _held_game.keys()
	for k2 in game_keys:
		if int(k2) <= committed:
			_held_game.erase(k2)
	_held_game_order = _held_game_order.filter(func(s2): return int(s2) > committed)
	_clear_deadline_if_idle()


func _drain() -> void:
	if _nbc == null or _nbc.resync_required():
		return
	var guard: int = 0
	while guard < MAX_HELD:
		guard += 1
		var expected: int = _nbc.expected_next_server_seq()
		if _held_side.has(expected):
			_held_side.erase(expected)
			_held_side_order.erase(expected)
			var r: Dictionary = _nbc.observe_side_channel_authority_seq(expected)
			if not bool(r.get("ok", false)):
				break
			continue
		if _held_game.has(expected):
			var ne: NetworkedEvent = _held_game[expected] as NetworkedEvent
			_held_game.erase(expected)
			_held_game_order.erase(expected)
			if not _nbc.ingest_networked_event(ne):
				break
			continue
		break
	_clear_deadline_if_idle()


func _timeout_force_resync(reason: String) -> Dictionary:
	if _nbc == null:
		return {"ok": false, "reason": reason, "applied": false, "resync": true}
	# 优先用最小 future game 事件触发 NBC 原生 gap resync
	var forced: NetworkedEvent = null
	if not _held_game_order.is_empty():
		var s0: int = int(_held_game_order[0])
		forced = _held_game.get(s0) as NetworkedEvent
		_held_game.erase(s0)
		_held_game_order.pop_front()
	clear()
	var applied := false
	if forced != null:
		applied = _nbc.ingest_networked_event(forced)
	if not _nbc.resync_required():
		# 无 game 可灌时直接置 resync（等价于丢失业务缺口）
		_nbc.force_resync_for_authority_gap()
	return {
		"ok": false,
		"reason": reason,
		"applied": applied,
		"resync": _nbc.resync_required(),
	}
