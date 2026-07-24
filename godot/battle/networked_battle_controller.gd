class_name NetworkedBattleController extends IBattleController

# E2-02 / #232：纯投影消费端。
# 只接受 NetworkedEvent / 事件流，维护本 recipient 公共投影。
# 不继承 IAuthoritativeBattleController，不实例化/重跑 TurnEngine/AI/牌墙。
# 冻结状态机：committed 与 pending/resync 分离；
# 非 snapshot 若 view_hash==committed 则直接 journal commit（投影不变），
# 否则只进 pending，匹配 ROOM_SNAPSHOT 才一次提交；stream 整批原子回滚。
# #241：snapshot_registry 预检后原子 restore；失败整份零应用。

var room_id: String = ""
var recipient_seat: int = 0
## #241：客户端 module provider 注册表（STANDARD 仅 core_table）
var snapshot_registry: SnapshotModuleRegistry = null

# committed 投影态
var _current_seq: int = 0
var _public_view: Dictionary = {}
var _view_hash: String = ""
var _journal: Array = []  # Array[NetworkedEvent] 深拷贝存储
var _applied_modules: Dictionary = {}  # module_key -> payload

# 非 committed：至多一条 pending；resync 标志
var _pending_event = null  # NetworkedEvent | null
var _resync_required: bool = false
var _last_snapshot_error: String = ""


func _init(p_room_id: String = "", p_recipient_seat: int = 0) -> void:
	room_id = p_room_id
	recipient_seat = p_recipient_seat
	snapshot_registry = SnapshotModuleRegistry.make_standard()
	_current_seq = 0
	_public_view = {}
	_view_hash = ""
	_journal = []
	_applied_modules = {}
	_pending_event = null
	_resync_required = false
	_last_snapshot_error = ""


func resync_required() -> bool:
	return _resync_required


# exact NetworkedEvent：is 接受子类；get_script()==NetworkedEvent 才是基类实例。
func _is_exact_networked_event(ev: Variant) -> bool:
	return ev is NetworkedEvent and (ev as Object).get_script() == NetworkedEvent


func ingest_networked_event(ev: Variant) -> bool:
	if ev == null:
		return false
	if not _is_exact_networked_event(ev):
		return false
	var ne: NetworkedEvent = ev as NetworkedEvent
	if ne.room_id != room_id:
		return false

	match ne.kind:
		"ROOM_SNAPSHOT":
			return _ingest_room_snapshot(ne)
		"ACTION_APPLIED", "TURN_PROMPT", "CLAIM_WINDOW", "PLAYER_JOINED", \
		"HAND_SETTLED", "MATCH_SETTLED", "REWARD_WINDOW_OPENED", \
		"REWARD_WINDOW_CLOSING", "REWARD_WINDOW_SETTLED", "REWARD_WINDOW_CANCELLED", \
		"ITEM_GRANTED", "ITEM_CONSUMED", "ITEM_APPLIED", \
		"CHARACTER_ABILITY_ARMED", "CHARACTER_ABILITY_DISARMED":
			return _ingest_non_snapshot(ne)
		_:
			return false


func ingest_event_stream(events: Variant) -> bool:
	if typeof(events) != TYPE_ARRAY:
		return false
	var arr: Array = events
	var saved: Dictionary = _capture_state()
	for item in arr:
		if not _is_exact_networked_event(item):
			_restore_state(saved)
			return false
		if not ingest_networked_event(item):
			_restore_state(saved)
			return false
	return true


func get_public_view() -> Dictionary:
	return _public_view.duplicate(true)


func get_core_table_view() -> Dictionary:
	if _applied_modules.has("core_table"):
		var ap = _applied_modules["core_table"]
		if typeof(ap) == TYPE_DICTIONARY:
			return (ap as Dictionary).duplicate(true)
	if _public_view.is_empty():
		return {}
	var mods: Variant = _public_view.get("modules", [])
	if typeof(mods) != TYPE_ARRAY:
		return {}
	for m in mods:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var md: Dictionary = m
		if str(md.get("module_key", "")) == "core_table":
			var pay = md.get("payload", {})
			if typeof(pay) == TYPE_DICTIONARY:
				return (pay as Dictionary).duplicate(true)
	return {}


## #241：provider restore 回调；仅 registry 预检通过后调用。
func apply_restored_module(
	module_key: String,
	_schema_version: int,
	payload: Dictionary,
	seat: int
) -> bool:
	if seat != recipient_seat:
		return false
	if module_key.is_empty():
		return false
	_applied_modules[module_key] = payload.duplicate(true)
	return true


## registry 两阶段原子 restore：commit 失败整份回滚。
func capture_module_restore_state() -> Dictionary:
	return _applied_modules.duplicate(true)


func restore_module_restore_state(prev: Variant) -> void:
	_applied_modules = {}
	if typeof(prev) == TYPE_DICTIONARY:
		_applied_modules = (prev as Dictionary).duplicate(true)


func last_snapshot_error() -> String:
	return _last_snapshot_error


func expected_next_server_seq() -> int:
	# 应用快照后：已应用上限 = snapshot_server_seq；下一条 = next_server_seq
	if _public_view.has("next_server_seq"):
		var n: int = int(_public_view["next_server_seq"])
		if n == _current_seq + 1:
			return n
	return _current_seq + 1


func get_event_journal() -> Array:
	var out: Array = []
	for item in _journal:
		if item is NetworkedEvent:
			var cloned: NetworkedEvent = NetworkedEvent.from_dict(
				(item as NetworkedEvent).to_dict()
			)
			if cloned != null:
				out.append(cloned)
	return out


func current_seq() -> int:
	return _current_seq


func desync_check(remote_view_hash: Variant) -> bool:
	if typeof(remote_view_hash) != TYPE_STRING:
		return false
	var h: String = remote_view_hash
	if h.length() != 64:
		return false
	if _view_hash.is_empty():
		return false
	# 只比 committed；pending 不冒充已提交
	return h == _view_hash


func _ingest_room_snapshot(ne: NetworkedEvent) -> bool:
	var payload: Dictionary = ne.payload
	var seq: int = int(ne.server_seq)
	_last_snapshot_error = ""

	# SNAP-02：envelope.server_seq == snapshot_server_seq；next == snapshot + 1
	if int(payload.get("snapshot_server_seq", -1)) != seq:
		_last_snapshot_error = "SNAP_SEQ_MISMATCH"
		return false
	if int(payload.get("next_server_seq", -1)) != seq + 1:
		_last_snapshot_error = "SNAP_NEXT_MISMATCH"
		return false

	var seat_ok: bool = int(payload.get("seat_view", -1)) == recipient_seat
	if not seat_ok:
		_last_snapshot_error = "SNAPSHOT_SEAT_MISMATCH"
	var expected: String = ProtocolViewCodec.compute_view_hash(payload)
	var hash_ok: bool = not expected.is_empty() and expected == ne.view_hash
	if seat_ok and not hash_ok:
		_last_snapshot_error = "SNAPSHOT_VIEW_HASH_MISMATCH"
	var modules_ok: bool = _modules_ok(payload.get("modules", null))
	var core_ok: bool = false
	if modules_ok:
		for m in payload["modules"]:
			if str((m as Dictionary).get("module_key", "")) == "core_table":
				var cp = (m as Dictionary).get("payload", {})
				if typeof(cp) == TYPE_DICTIONARY \
						and int((cp as Dictionary).get("recipient_seat", -1)) == recipient_seat:
					core_ok = true
					break
		if not core_ok:
			_last_snapshot_error = SnapshotModuleRegistry.ERR_REQUIRED_MISSING
	var schema_ok: bool = seat_ok and hash_ok and modules_ok and core_ok

	# 有 pending：唯一允许匹配的下一跳 snapshot
	if _pending_event != null:
		var pending_seq: int = int((_pending_event as NetworkedEvent).server_seq)
		var pending_vh: String = (_pending_event as NetworkedEvent).view_hash
		var match_ok: bool = schema_ok \
				and seq == pending_seq + 1 \
				and ne.view_hash == pending_vh
		if not match_ok:
			_pending_event = null
			_resync_required = true
			if _last_snapshot_error.is_empty():
				_last_snapshot_error = "SNAPSHOT_PENDING_MISMATCH"
			return false
		if not _atomic_registry_restore(payload):
			_pending_event = null
			_resync_required = true
			return false
		# 一次提交：pending 再 snapshot
		_append_journal(_pending_event as NetworkedEvent)
		_public_view = payload.duplicate(true)
		_view_hash = ne.view_hash
		_current_seq = seq
		_append_journal(ne)
		_pending_event = null
		_resync_required = false
		_last_snapshot_error = ""
		return true

	# 无 pending：既有 schema 校验；seq>committed 可作为初始/跳号 resync
	if not schema_ok:
		return false
	if seq <= _current_seq:
		_last_snapshot_error = "SNAPSHOT_SEQ_NOT_FORWARD"
		return false
	if not _atomic_registry_restore(payload):
		return false
	_public_view = payload.duplicate(true)
	_view_hash = ne.view_hash
	_current_seq = seq
	_append_journal(ne)
	_resync_required = false
	_last_snapshot_error = ""
	return true


## #241：registry 预检 + 原子 restore；失败恢复 _applied_modules，整份零应用。
func _atomic_registry_restore(payload: Dictionary) -> bool:
	if snapshot_registry == null:
		_last_snapshot_error = "NO_REGISTRY"
		return false
	var prev_mods: Dictionary = _applied_modules.duplicate(true)
	_applied_modules.clear()
	var rr: Dictionary = snapshot_registry.restore_modules(
		payload.get("modules", []), recipient_seat, self
	)
	if not bool(rr.get("ok", false)):
		_applied_modules = prev_mods
		_last_snapshot_error = str(rr.get("code", SnapshotModuleRegistry.ERR_RESTORE_FAILED))
		return false
	return true


func _ingest_non_snapshot(ne: NetworkedEvent) -> bool:
	# room 已在入口校验
	if _resync_required:
		return false
	if _pending_event != null:
		# pending 时任何非 snapshot → mismatch
		_pending_event = null
		_resync_required = true
		return false
	if ne.view_hash.length() != 64:
		return false
	var seq: int = int(ne.server_seq)
	# SNAP-03：仅从 next_server_seq（= current+1）消费；小于为重复/过期，大于为缺口
	var expected_next: int = expected_next_server_seq()
	if seq < expected_next:
		# 重复/过期：幂等忽略（不推进、不 resync）
		return true
	if seq > expected_next:
		_pending_event = null
		_resync_required = true
		return false
	if seq != _current_seq + 1:
		_pending_event = null
		_resync_required = true
		return false
	# 先深拷贝；失败不得半提交
	var cloned: NetworkedEvent = NetworkedEvent.from_dict(ne.to_dict())
	if cloned == null:
		return false
	# 与 committed view_hash 相同：事件不改变公共投影 → 直接 journal commit
	if ne.view_hash == _view_hash:
		_journal.append(cloned)
		_current_seq = seq
		# _public_view / _view_hash 不变；不设 pending；resync 保持 false
		return true
	# 异 hash：只进 pending，等待匹配 ROOM_SNAPSHOT
	_pending_event = cloned
	return true


func _append_journal(ne: NetworkedEvent) -> void:
	var cloned: NetworkedEvent = NetworkedEvent.from_dict(ne.to_dict())
	if cloned != null:
		_journal.append(cloned)


func _capture_state() -> Dictionary:
	var journal_dicts: Array = []
	for item in _journal:
		if item is NetworkedEvent:
			journal_dicts.append((item as NetworkedEvent).to_dict())
	var pending_dict = null
	if _pending_event != null and _pending_event is NetworkedEvent:
		pending_dict = (_pending_event as NetworkedEvent).to_dict()
	return {
		"current_seq": _current_seq,
		"public_view": _public_view.duplicate(true),
		"view_hash": _view_hash,
		"journal": journal_dicts,
		"pending": pending_dict,
		"resync": _resync_required,
		"applied_modules": _applied_modules.duplicate(true),
		"last_snapshot_error": _last_snapshot_error,
	}


func _restore_state(s: Dictionary) -> void:
	_current_seq = int(s["current_seq"])
	_public_view = (s["public_view"] as Dictionary).duplicate(true)
	_view_hash = str(s["view_hash"])
	_journal = []
	for d in s["journal"]:
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var cloned: NetworkedEvent = NetworkedEvent.from_dict(d)
		if cloned != null:
			_journal.append(cloned)
	_pending_event = null
	var pending_raw = s.get("pending", null)
	if pending_raw != null and typeof(pending_raw) == TYPE_DICTIONARY:
		_pending_event = NetworkedEvent.from_dict(pending_raw)
	_resync_required = bool(s["resync"])
	_applied_modules = {}
	var am: Variant = s.get("applied_modules", {})
	if typeof(am) == TYPE_DICTIONARY:
		_applied_modules = (am as Dictionary).duplicate(true)
	_last_snapshot_error = str(s.get("last_snapshot_error", ""))


func _modules_ok(raw: Variant) -> bool:
	if typeof(raw) != TYPE_ARRAY:
		_last_snapshot_error = SnapshotModuleRegistry.ERR_INVALID
		return false
	var mods: Array = raw
	if mods.is_empty():
		_last_snapshot_error = SnapshotModuleRegistry.ERR_REQUIRED_MISSING
		return false
	var keys: Array = []
	var seen: Dictionary = {}
	for m in mods:
		if typeof(m) != TYPE_DICTIONARY:
			_last_snapshot_error = SnapshotModuleRegistry.ERR_INVALID
			return false
		var md: Dictionary = m
		if md.keys().size() != 3:
			_last_snapshot_error = SnapshotModuleRegistry.ERR_INVALID
			return false
		if not md.has("module_key") or not md.has("schema_version") or not md.has("payload"):
			_last_snapshot_error = SnapshotModuleRegistry.ERR_INVALID
			return false
		var k: String = str(md["module_key"])
		if seen.has(k):
			_last_snapshot_error = SnapshotModuleRegistry.ERR_DUPLICATE_KEY
			return false
		seen[k] = true
		keys.append(k)
	var sorted_keys := keys.duplicate()
	sorted_keys.sort()
	if JSON.stringify(keys) != JSON.stringify(sorted_keys):
		_last_snapshot_error = SnapshotModuleRegistry.ERR_INVALID
		return false
	if not seen.has("core_table"):
		_last_snapshot_error = SnapshotModuleRegistry.ERR_REQUIRED_MISSING
		return false
	return true
