class_name LocalLoopbackServer
extends RefCounted

# E2-02 / #232：本地 loopback 权威桩。
# 包裹 BattleController 唯一 apply_action(Action, ActionSource) 入口。
# 对外核心 API：new(config, dealer_seat)、start、submit_action、publish_snapshot、
# events_since、event_journal、current_server_seq。
# 不保留 PASS 特判 / NYI / 旧构造 / 旧裸 Dictionary 路径。

const MAX_AI_STEPS := 2000
const ERROR_NOT_STARTED := "NOT_STARTED"
const ERROR_UNAUTHORIZED := "UNAUTHORIZED"
const ERROR_COMMAND_ID_CONFLICT := "COMMAND_ID_CONFLICT"
const ERROR_EVENT_PUBLISH_FAILED := "EVENT_PUBLISH_FAILED"

var _config: GameSessionConfig = null
var _dealer_seat: int = 0
var _bc: BattleController = null
var _room_id: String = ""
var _server_seq: int = 0
var _started: bool = false
# restore 失败后不可再证明权威状态；实例永久 fail-closed，只能丢弃重建。
var _rollback_failed: bool = false
# 每席独立 NetworkedEvent 日志（同逻辑 seq 可有不同 view_hash）
var _journals: Array = [[], [], [], []]
# command_id → { "fingerprint": String, "result": CommandResult }
var _command_cache: Dictionary = {}
# seat → participant wire ("HUMAN"/"AI")
var _participants: Array = []
# 本局起始分：仅 start 成功后冻结；失败 start 不得污染（空 = 未冻结）
var _hand_start_scores: Array = []
# E2-04：构造期模式模块包（STANDARD 四零 / TRASH_TALK 最小对象）
var mode_modules: ModeModuleBundle = null
# #241：快照 module provider 注册表（STANDARD 仅 core_table）
var snapshot_registry: SnapshotModuleRegistry = null
# #241：HUMAN 席临时 AI 接管（不改 participants 配置）
var _ai_control_seats: Dictionary = {}  # seat(int) -> bool
# 测试：下一次 publish_snapshot 强制失败（不改业务路径）
var _fail_next_snapshot: bool = false
# 测试：下一次 ACTION_APPLIED/SNAP 发布强制失败（AI step / submit 共用 emit）
var _fail_next_action_publish: bool = false
# #241：本局 HAND_SETTLED 是否已发布（幂等，禁止重复 seq/journal）
var _hand_settled_emitted: bool = false


func _init(config: GameSessionConfig = null, dealer_seat: int = 0) -> void:
	_config = config
	_dealer_seat = dealer_seat
	_server_seq = 0
	_started = false
	_rollback_failed = false
	_journals = [[], [], [], []]
	_command_cache = {}
	_hand_start_scores = []
	_participants = [&"HUMAN", &"AI", &"AI", &"AI"]
	mode_modules = null
	snapshot_registry = SnapshotModuleRegistry.make_standard()
	_ai_control_seats = {}
	_fail_next_snapshot = false
	_fail_next_action_publish = false
	_hand_settled_emitted = false
	if config != null:
		_room_id = config.session_id
		var parts: Array = config.participants
		if parts.size() == 4:
			_participants = parts.duplicate()
		mode_modules = ModeModuleBundle.from_config(config)
		_bc = BattleController.new(config.seed, dealer_seat, false, TileId.E, 0)
		if _bc != null:
			_bc.bind_mode_modules(mode_modules)
	else:
		_room_id = ""
		_bc = null


func start() -> bool:
	if _rollback_failed:
		return false
	if _started:
		return false
	if _bc == null or _bc.state == null:
		return false
	# 任何 mutation 前捕获 ARS 并冻结服务端副作用字段
	var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(_bc)
	if snap == null:
		return false
	var auth_h: String = snap.sha256()
	if auth_h.is_empty() or auth_h.length() != 64 or not snap.can_restore():
		return false
	# 无副作用时点：mutation 前读取本局起始分候选；仅 start 成功后提交
	var start_scores_candidate: Array = _capture_scores_array()
	if start_scores_candidate.size() != 4:
		return false
	var frozen_seq: int = _server_seq
	var frozen_journals: Array = []
	for s in range(4):
		frozen_journals.append(_clone_events(_journals[s] as Array))
	var frozen_cache: Dictionary = _command_cache.duplicate(true)
	var frozen_started: bool = _started
	var frozen_hand_start: Array = _hand_start_scores.duplicate()

	# DRAW → 摸牌进入 TURN；ROOM_SNAPSHOT → private prompt
	_ensure_drawn()
	if not publish_snapshot() or not _emit_private_prompt():
		if _rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache):
			_started = frozen_started
			_hand_start_scores = frozen_hand_start
		return false
	_hand_start_scores = start_scores_candidate
	_hand_settled_emitted = false
	_started = true
	return true


func fail_next_snapshot_for_test() -> void:
	_fail_next_snapshot = true


func fail_next_action_publish_for_test() -> void:
	_fail_next_action_publish = true


func publish_snapshot() -> bool:
	if _rollback_failed:
		return false
	if _bc == null or _bc.state == null:
		return false
	if _fail_next_snapshot:
		_fail_next_snapshot = false
		return false
	# 候选 seq：构造/校验全部成功前不得 _alloc_seq / 写 journal
	var candidate: int = _server_seq + 1
	var prepared: Array = []
	for seat in range(4):
		var payload: Dictionary = _build_room_snapshot_payload(seat, candidate)
		if payload.is_empty():
			return false
		var vh: String = ProtocolViewCodec.compute_view_hash(payload)
		if vh.is_empty() or vh.length() != 64:
			return false
		var ne: NetworkedEvent = NetworkedEvent.make(
			"ROOM_SNAPSHOT", candidate, _room_id, payload, vh
		)
		if ne == null:
			return false
		var cloned: NetworkedEvent = NetworkedEvent.from_dict(ne.to_dict())
		if cloned == null:
			return false
		prepared.append(cloned)
	# 四席全部成功后单线程提交
	_server_seq = candidate
	for seat2 in range(4):
		(_journals[seat2] as Array).append(prepared[seat2])
	return true


func current_server_seq() -> int:
	return _server_seq


func event_journal(recipient_seat: int) -> Array:
	if recipient_seat < 0 or recipient_seat > 3:
		return []
	return _clone_events(_journals[recipient_seat] as Array)


func events_since(recipient_seat: int, after_server_seq: int) -> Array:
	if recipient_seat < 0 or recipient_seat > 3:
		return []
	var out: Array = []
	for ne in _journals[recipient_seat] as Array:
		if ne is NetworkedEvent and int((ne as NetworkedEvent).server_seq) > after_server_seq:
			var cloned: NetworkedEvent = NetworkedEvent.from_dict(
				(ne as NetworkedEvent).to_dict()
			)
			if cloned != null:
				out.append(cloned)
	return out


## E2-04 真实生产事件发布边界。
## STANDARD 拒绝欢乐 kind 且 server_seq/journal 零变化；
## TRASH_TALK 仅在 NetworkedEvent schema 合法时写入四席 journal（不实现 E5 业务副作用）。
func try_publish_business_event(kind: String, payload: Dictionary) -> bool:
	if _rollback_failed:
		return false
	if not _started:
		return false
	if kind.is_empty():
		return false
	if mode_modules != null and not mode_modules.accepts_event_kind(kind):
		return false
	# 候选 seq：校验全部成功前不得推进 _server_seq / 写 journal
	var candidate: int = _server_seq + 1
	var pl: Dictionary = payload.duplicate(true) if typeof(payload) == TYPE_DICTIONARY else {}
	var prepared: Array = []
	for seat in range(4):
		var vh: String = ProtocolViewCodec.compute_view_hash(pl)
		if vh.is_empty() or vh.length() != 64:
			return false
		var ne: NetworkedEvent = NetworkedEvent.make(kind, candidate, _room_id, pl, vh)
		if ne == null:
			return false
		var cloned: NetworkedEvent = NetworkedEvent.from_dict(ne.to_dict())
		if cloned == null:
			return false
		prepared.append(cloned)
	_server_seq = candidate
	for seat2 in range(4):
		(_journals[seat2] as Array).append(prepared[seat2])
	return true


func submit_action(action: Action) -> CommandResult:
	if action == null:
		return _reject_result("", "INVALID_ACTION")
	if _rollback_failed:
		return _reject_result(action.command_id, ERROR_EVENT_PUBLISH_FAILED)
	# 无副作用早拒绝：不写 command cache / seq / journal / BC
	if not _started:
		return _reject_result(action.command_id, ERROR_NOT_STARTED)
	if not _is_human(int(action.seat)):
		return _reject_result(action.command_id, ERROR_UNAUTHORIZED)

	# 业务指纹：在 room/BC/领域处理之前计算；失败 → INVALID_ACTION 且不缓存
	var fp: String = _business_fingerprint(action)
	if fp.is_empty():
		return _reject_result(action.command_id, "INVALID_ACTION")

	var cmd: String = action.command_id
	if _command_cache.has(cmd):
		var entry: Dictionary = _command_cache[cmd] as Dictionary
		var cached_fp: String = str(entry.get("fingerprint", ""))
		if cached_fp == fp:
			return _clone_cr(entry.get("result") as CommandResult)
		# 异指纹：不覆盖 cache、不分配 seq、不改 journal/BC
		return _reject_result(cmd, ERROR_COMMAND_ID_CONFLICT)

	# 房间校验
	if action.room_id != _room_id:
		var cr_room := _reject_result(cmd, "WRONG_ROOM")
		_cache_command(cmd, fp, cr_room)
		return _clone_cr(cr_room)

	if _bc == null or _bc.state == null:
		var cr_st := _reject_result(cmd, "INVALID_ACTION")
		_cache_command(cmd, fp, cr_st)
		return _clone_cr(cr_st)

	# E2-04：STANDARD 模式门控拒绝欢乐命令（MODE_FORBIDDEN，与 E5 NOT_ENABLED 可区分）
	if mode_modules != null and not mode_modules.accepts_command_kind(action.kind):
		var cr_mode := _reject_result(cmd, "MODE_FORBIDDEN")
		_cache_command(cmd, fp, cr_mode)
		return _clone_cr(cr_mode)

	# apply 前捕获 ARS；capture/hash 失败 → 非缓存 EVENT_PUBLISH_FAILED 且不 apply
	var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(_bc)
	if snap == null:
		return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
	var auth_h: String = snap.sha256()
	if auth_h.is_empty() or auth_h.length() != 64 or not snap.can_restore():
		return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
	var frozen_seq: int = _server_seq
	var frozen_journals: Array = []
	for s in range(4):
		frozen_journals.append(_clone_events(_journals[s] as Array))
	var frozen_cache: Dictionary = _command_cache.duplicate(true)

	# 捕获弃牌源（DISCARD/RIICHI）
	var discard_source := "HAND"
	var discarded_tile: Tile = null
	if action.kind == "DISCARD" or action.kind == "RIICHI":
		var iid: int = int(action.payload.get("tile_instance_id", -1))
		var seat_obj: Seat = _bc.state.seats[action.seat] as Seat
		if seat_obj != null:
			discarded_tile = seat_obj.hand.find_by_instance_id(iid)
			if discarded_tile != null \
					and int(seat_obj.last_drawn_instance_id) == iid:
				discard_source = "DRAWN"

	var res: ActionResolution = _bc.apply_action(action, ActionSource.HUMAN)
	if res == null or not res.accepted:
		var code := "INVALID_ACTION"
		if res != null:
			code = str(res.error_code)
		var cr_rej := _reject_result(cmd, code)
		# 非法动作不分配 server_seq，仍缓存幂等
		_cache_command(cmd, fp, cr_rej)
		return _clone_cr(cr_rej)

	# 接受：ACTION_APPLIED → ROOM_SNAPSHOT 原子批次；失败则 restore BC 与服务端副作用
	var aa_seq: int = _emit_action_applied_then_snapshot(
		action, discarded_tile, discard_source
	)
	if aa_seq < 1:
		_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
		return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)

	# HUMAN apply 起至 AI 链 / 最终 prompt|settlement 为同一事务
	if not _auto_advance_ai():
		_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
		return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)

	if not bool(_bc.get("_settled")):
		# 回到真人 DRAW：领域 server-draw 推进；若荒牌 settle 则直接 HAND_SETTLED
		var human_draw_path := false
		if int(_bc.state.phase) == BattlePhase.Kind.DRAW:
			var cur_seat: int = int(_bc.state.current_seat)
			if _is_human(cur_seat):
				human_draw_path = true
				_ensure_drawn()
		# 领域 draw 后必须重检 settled（不得继续 snapshot/private prompt）
		if bool(_bc.get("_settled")):
			if not _emit_settled_if_needed():
				_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
				return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
		else:
			if human_draw_path:
				if not publish_snapshot():
					_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
					return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
			if not _emit_private_prompt():
				_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
				return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
	else:
		if not _emit_settled_if_needed():
			_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
			return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)

	var cr_ok := CommandResult.from_dict({
		"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
		"command_id": cmd,
		"status": "ACCEPTED",
		"server_seq": _server_seq,
		"error_code": "",
	})
	_cache_command(cmd, fp, cr_ok)
	return _clone_cr(cr_ok)


# ---- 内部 ----

## 只有权威 controller 完整恢复成功后，才回退服务端 seq/journal/cache。
## mutation 前已用 can_restore 预检；若运行时仍失败则关闭提交入口，避免继续分叉。
func _rollback_transaction(
	snap: AuthorityReplaySnapshot,
	frozen_seq: int,
	frozen_journals: Array,
	frozen_cache: Dictionary
) -> bool:
	if snap == null or not snap.restore_into(_bc):
		_rollback_failed = true
		_started = false
		return false
	_server_seq = frozen_seq
	_journals = frozen_journals
	_command_cache = frozen_cache
	return true

## 业务指纹：session/room/seat/hand/decision/kind + 规范 payload 的 SHA-256。
## 仅 client_seq 属于可变化的传输重试序号；窗口或局变化必须视为 command_id 冲突。
func _business_fingerprint(action: Action) -> String:
	if action == null or _config == null:
		return ""
	var kind_str: String = str(action.kind)
	var raw_payload: Dictionary = action.payload if typeof(action.payload) == TYPE_DICTIONARY else {}
	var canon_pl: Variant = Action.normalize_payload(kind_str, raw_payload)
	if canon_pl == null or typeof(canon_pl) != TYPE_DICTIONARY:
		return ""
	var payload_sha: String = ProtocolViewCodec.compute_view_hash(canon_pl)
	if payload_sha.is_empty() or payload_sha.length() != 64:
		return ""
	var material := {
		"session_id": str(_config.session_id),
		"room_id": str(action.room_id),
		"seat": int(action.seat),
		"hand_seq": int(action.hand_seq),
		"decision_id": str(action.decision_id),
		"kind": kind_str,
		"payload_sha256": payload_sha,
	}
	var fp: String = ProtocolViewCodec.compute_view_hash(material)
	if fp.is_empty() or fp.length() != 64:
		return ""
	return fp


func _cache_command(cmd: String, fingerprint: String, cr: CommandResult) -> void:
	_command_cache[cmd] = {
		"fingerprint": fingerprint,
		"result": cr,
	}


## 若合法 DRAW：走 IAuth typed server-draw progression（唯一 _step_draw）。
## true = 正常摸牌或荒牌 settle 等领域推进成功；false = 未推进。
func _ensure_drawn() -> bool:
	if _bc == null:
		return false
	return _bc.progress_server_draw()


func _alloc_seq() -> int:
	_server_seq += 1
	return _server_seq


func _append_event(seat: int, ne: NetworkedEvent) -> void:
	var cloned: NetworkedEvent = NetworkedEvent.from_dict(ne.to_dict())
	if cloned != null:
		(_journals[seat] as Array).append(cloned)


func _clone_events(src: Array) -> Array:
	var out: Array = []
	for ne in src:
		if ne is NetworkedEvent:
			var c: NetworkedEvent = NetworkedEvent.from_dict((ne as NetworkedEvent).to_dict())
			if c != null:
				out.append(c)
	return out


func _clone_cr(cr: CommandResult) -> CommandResult:
	if cr == null:
		return null
	return CommandResult.from_dict(cr.to_dict())


func _reject_result(cmd: String, code: String) -> CommandResult:
	var use_cmd: String = cmd
	if use_cmd.is_empty() or not ProtocolUuid.is_canonical_v4(use_cmd):
		use_cmd = "550e8400-e29b-41d4-a716-000000000099"
	var err: String = code if not code.is_empty() else "INVALID_ACTION"
	return CommandResult.from_dict({
		"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
		"command_id": use_cmd,
		"status": "REJECTED",
		"server_seq": _server_seq,
		"error_code": err,
	})


func _build_room_snapshot_payload(seat: int, seq: int) -> Dictionary:
	# #241：经 registry 组合 modules；组合器不改写模块业务 payload
	if snapshot_registry == null or _bc == null:
		return {}
	var ser: Dictionary = snapshot_registry.serialize_modules(
		{"state": _bc.state}, seat
	)
	if not bool(ser.get("ok", false)):
		return {}
	var modules: Array = ser.get("modules", [])
	if typeof(modules) != TYPE_ARRAY or (modules as Array).is_empty():
		return {}
	return {
		"snapshot_server_seq": seq,
		"next_server_seq": seq + 1,
		"seat_view": seat,
		"modules": modules,
	}


## #241：临时 AI 接管/归还。仅影响有效控制，不改 participants 配置。
func set_seat_ai_control(seat: int, enabled: bool) -> void:
	if seat < 0 or seat > 3:
		return
	if enabled:
		_ai_control_seats[seat] = true
	else:
		_ai_control_seats.erase(seat)


func is_seat_ai_controlled(seat: int) -> bool:
	return bool(_ai_control_seats.get(seat, false))


## 配置为 HUMAN 且当前未被 AI 接管。
func is_effectively_human(seat: int) -> bool:
	return _is_human(seat)


## #241：重连 resync——发布当前 ROOM_SNAPSHOT；仅当存在有效真人决策窗时再发 prompt。
## 无真人窗时只发快照仍成功（避免 AI 席 TURN 使 _emit_private_prompt 假失败）。
## 需要 prompt 时与快照原子：失败则 ARS/seq/journal 回滚。
func publish_resync_snapshot_and_prompt() -> Dictionary:
	if _rollback_failed or not _started or _bc == null or _bc.state == null:
		return {"ok": false, "advanced": false, "code": ERROR_EVENT_PUBLISH_FAILED}
	var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(_bc)
	if snap == null or not snap.can_restore():
		return {"ok": false, "advanced": false, "code": ERROR_EVENT_PUBLISH_FAILED}
	var auth_h: String = snap.sha256()
	if auth_h.is_empty() or auth_h.length() != 64:
		return {"ok": false, "advanced": false, "code": ERROR_EVENT_PUBLISH_FAILED}
	var frozen_seq: int = _server_seq
	var frozen_journals: Array = []
	for s in range(4):
		frozen_journals.append(_clone_events(_journals[s] as Array))
	var frozen_cache: Dictionary = _command_cache.duplicate(true)
	if bool(_bc.get("_settled")):
		# 重连：始终先发新鲜 ROOM_SNAPSHOT（首条业务事件）
		if not publish_snapshot():
			return {"ok": false, "advanced": false, "code": ERROR_EVENT_PUBLISH_FAILED}
		# 幂等：若本局尚未 HAND_SETTLED 则补发一次；已发则零副作用
		if not _emit_settled_if_needed():
			_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
			return {"ok": false, "advanced": false, "code": ERROR_EVENT_PUBLISH_FAILED}
		return {"ok": true, "advanced": true, "code": ""}
	if not publish_snapshot():
		return {"ok": false, "advanced": false, "code": ERROR_EVENT_PUBLISH_FAILED}
	# 打开窗以判定是否需要真人 prompt
	for s2 in range(4):
		_bc.decision_context_for_seat(s2)
	if not _needs_human_private_prompt():
		return {"ok": true, "advanced": true, "code": ""}
	if not _emit_private_prompt():
		_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
		return {"ok": false, "advanced": false, "code": ERROR_EVENT_PUBLISH_FAILED}
	return {"ok": true, "advanced": true, "code": ""}


func _needs_human_private_prompt() -> bool:
	if _bc == null or bool(_bc.get("_settled")):
		return false
	var win = _bc.get("_active_window")
	if win == null or not (win is DecisionWindow):
		return false
	var dw: DecisionWindow = win as DecisionWindow
	if dw.kind == DecisionWindow.KIND_TURN:
		return _is_human(int(dw.subject_seat))
	if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
		for s in dw.seats():
			var si: int = int(s)
			if _is_human(si) and not dw.has_responded(si):
				return true
	return false


## #241：AI 接管单步——至多一个权威 Action（含其 AA+SNAP 原子发布），然后返回。
## 与 submit_action 同级 ARS 事务；失败全量回滚。无动作时不重复发 snapshot/prompt。
## 返回 {ok, advanced, waiting_human, settled, code}。
func step_ai_once() -> Dictionary:
	if _rollback_failed or not _started or _bc == null or _bc.state == null:
		return {
			"ok": false, "advanced": false, "waiting_human": false,
			"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
		}
	if bool(_bc.get("_settled")):
		return {
			"ok": true, "advanced": false, "waiting_human": false,
			"settled": true, "code": "",
		}

	var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(_bc)
	if snap == null or not snap.can_restore():
		return {
			"ok": false, "advanced": false, "waiting_human": false,
			"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
		}
	var auth_h: String = snap.sha256()
	if auth_h.is_empty() or auth_h.length() != 64:
		return {
			"ok": false, "advanced": false, "waiting_human": false,
			"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
		}
	var frozen_seq: int = _server_seq
	var frozen_journals: Array = []
	for s in range(4):
		frozen_journals.append(_clone_events(_journals[s] as Array))
	var frozen_cache: Dictionary = _command_cache.duplicate(true)

	# 仅 AI 席 DRAW 可在本步摸牌；真人 DRAW 等待
	if int(_bc.state.phase) == BattlePhase.Kind.DRAW:
		var cur: int = int(_bc.state.current_seat)
		if _is_human(cur):
			return {
				"ok": true, "advanced": false, "waiting_human": true,
				"settled": false, "code": "",
			}
		if not _ensure_drawn():
			return {
				"ok": true, "advanced": false, "waiting_human": false,
				"settled": bool(_bc.get("_settled")), "code": "",
			}
		if bool(_bc.get("_settled")):
			if not _emit_settled_if_needed():
				_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
				return {
					"ok": false, "advanced": false, "waiting_human": false,
					"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
				}
			return {
				"ok": true, "advanced": true, "waiting_human": false,
				"settled": true, "code": "",
			}
		# AI 摸牌后只发 ROOM_SNAPSHOT；TURN_PROMPT 仅真人（_emit_private_prompt 对 AI 席返回 false）
		# 下一 poll 再选 Action。与 _auto_advance_ai 循环语义一致。
		if not publish_snapshot():
			_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
			return {
				"ok": false, "advanced": false, "waiting_human": false,
				"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
			}
		return {
			"ok": true, "advanced": true, "waiting_human": false,
			"settled": false, "code": "",
		}

	for s in range(4):
		_bc.decision_context_for_seat(s)
	var win = _bc.get("_active_window")
	if win == null or not (win is DecisionWindow):
		if int(_bc.state.phase) == BattlePhase.Kind.SETTLE:
			_bc.set("_settled", true)
			if not _emit_settled_if_needed():
				_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
				return {
					"ok": false, "advanced": false, "waiting_human": false,
					"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
				}
			return {
				"ok": true, "advanced": true, "waiting_human": false,
				"settled": true, "code": "",
			}
		return {
			"ok": true, "advanced": false, "waiting_human": false,
			"settled": false, "code": "",
		}

	var dw: DecisionWindow = win as DecisionWindow
	if dw.kind == DecisionWindow.KIND_TURN:
		var actor: int = int(dw.subject_seat)
		if _is_human(actor):
			return {
				"ok": true, "advanced": false, "waiting_human": true,
				"settled": false, "code": "",
			}
		var act: Action = _build_ai_turn_action(actor)
		if act == null:
			return {
				"ok": true, "advanced": false, "waiting_human": false,
				"settled": false, "code": "",
			}
		var disc_tile: Tile = null
		var dsrc := "HAND"
		if act.kind == "DISCARD" or act.kind == "RIICHI":
			var iid: int = int(act.payload.get("tile_instance_id", -1))
			var so: Seat = _bc.state.seats[actor] as Seat
			if so != null:
				disc_tile = so.hand.find_by_instance_id(iid)
				if disc_tile != null and int(so.last_drawn_instance_id) == iid:
					dsrc = "DRAWN"
		var res: ActionResolution = _bc.apply_action(act, ActionSource.AI)
		if res == null or not res.accepted:
			# 领域拒绝：不推进；回滚任何意外
			_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
			return {
				"ok": true, "advanced": false, "waiting_human": false,
				"settled": false, "code": "",
			}
		if _emit_action_applied(act, disc_tile, dsrc) < 1:
			_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
			return {
				"ok": false, "advanced": false, "waiting_human": false,
				"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
			}
		# 终局 Action：同一 ARS 事务内必须完成 HAND_SETTLED
		if bool(_bc.get("_settled")):
			if not _emit_settled_if_needed():
				_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
				return {
					"ok": false, "advanced": false, "waiting_human": false,
					"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
				}
		return {
			"ok": true, "advanced": true, "waiting_human": false,
			"settled": bool(_bc.get("_settled")), "code": "",
		}

	if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
		for s2 in dw.seats():
			var si: int = int(s2)
			if _is_human(si) and not dw.has_responded(si):
				return {
					"ok": true, "advanced": false, "waiting_human": true,
					"settled": false, "code": "",
				}
		for s3 in dw.seats():
			var si3: int = int(s3)
			if dw.has_responded(si3):
				continue
			var pass_act: Action = _build_ai_claim_action(si3)
			if pass_act == null:
				continue
			var r2: ActionResolution = _bc.apply_action(pass_act, ActionSource.AI)
			if r2 == null or not r2.accepted:
				continue
			if _emit_action_applied(pass_act, null, "HAND") < 1:
				_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
				return {
					"ok": false, "advanced": false, "waiting_human": false,
					"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
				}
			if bool(_bc.get("_settled")):
				if not _emit_settled_if_needed():
					_rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache)
					return {
						"ok": false, "advanced": false, "waiting_human": false,
						"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
					}
			return {
				"ok": true, "advanced": true, "waiting_human": false,
				"settled": bool(_bc.get("_settled")), "code": "",
			}
		return {
			"ok": true, "advanced": false, "waiting_human": false,
			"settled": false, "code": "",
		}

	return {
		"ok": true, "advanced": false, "waiting_human": false,
		"settled": false, "code": "",
	}


## 权威状态 sha256（测试/失败注入对照）；不可用时空串。
func authority_hash_for_test() -> String:
	if _bc == null:
		return ""
	var snap: AuthorityReplaySnapshot = AuthorityReplaySnapshot.capture(_bc)
	if snap == null:
		return ""
	return snap.sha256()


func _public_view_hash_for_seq(seat: int, snap_seq: int) -> String:
	var payload: Dictionary = _build_room_snapshot_payload(seat, snap_seq)
	return ProtocolViewCodec.compute_view_hash(payload)


## 从 recipient 席 journal 倒序取最后一条已提交 ROOM_SNAPSHOT 的 view_hash。
## seat 非法 / 未找到 / hash 非法 → 空串。禁止按新 seq 重建 snapshot payload。
func _last_committed_snapshot_view_hash(recipient_seat: int) -> String:
	if recipient_seat < 0 or recipient_seat > 3:
		return ""
	var journal: Array = _journals[recipient_seat] as Array
	for i in range(journal.size() - 1, -1, -1):
		var item = journal[i]
		if not (item is NetworkedEvent):
			continue
		var ne: NetworkedEvent = item as NetworkedEvent
		if ne.kind != "ROOM_SNAPSHOT":
			continue
		var vh: String = str(ne.view_hash)
		if vh.is_empty() or vh.length() != 64:
			return ""
		return vh
	return ""


## 可 override 的逐席事件构建 seam：make → null 即 null；再 from_dict 严格 roundtrip clone。
## recipient 仅供测试/子类逐席失败注入；正常实现不使用。
func _build_recipient_event(
	kind: String, _recipient_seat: int, seq: int, payload: Dictionary, view_hash: String
) -> NetworkedEvent:
	var ne: NetworkedEvent = NetworkedEvent.make(kind, seq, _room_id, payload, view_hash)
	if ne == null:
		return null
	return NetworkedEvent.from_dict(ne.to_dict())


## ACTION_APPLIED 与紧随的 ROOM_SNAPSHOT 共用 post-apply public view_hash。
## 两阶段：prepare 四席 AA+SNAP clone → 全部成功后 _server_seq=snap_seq 再 append；失败零 mutation。
## 逻辑：aa_seq = N，snap_seq = N+1；hash = hash(ROOM_SNAPSHOT payload @ N+1)。
func _emit_action_applied_then_snapshot(
	action: Action, discarded_tile: Tile, discard_source: String
) -> int:
	if _fail_next_action_publish:
		_fail_next_action_publish = false
		return -1
	var aa_seq: int = _server_seq + 1
	var snap_seq: int = aa_seq + 1
	var resolved: Dictionary = _build_resolved_payload(action, discarded_tile, discard_source)
	var aa_payload := {
		"causation_command_id": action.command_id,
		"hand_seq": int(action.hand_seq),
		"decision_id": action.decision_id,
		"seat": int(action.seat),
		"action_kind": action.kind,
		"resolved_payload": resolved,
	}
	# 阶段 1：四席逐席构造非空 snapshot / 64 位 hash / AA clone / SNAP clone；任一步失败零 mutation
	var prepared: Array = []
	for seat in range(4):
		var sp: Dictionary = _build_room_snapshot_payload(seat, snap_seq)
		if sp.is_empty():
			return -1
		var vh: String = ProtocolViewCodec.compute_view_hash(sp)
		if vh.is_empty() or vh.length() != 64:
			return -1
		var aa_ev: NetworkedEvent = _build_recipient_event(
			"ACTION_APPLIED", seat, aa_seq, aa_payload, vh
		)
		if aa_ev == null:
			return -1
		var snap_ev: NetworkedEvent = _build_recipient_event(
			"ROOM_SNAPSHOT", seat, snap_seq, sp, vh
		)
		if snap_ev == null:
			return -1
		prepared.append({"aa": aa_ev, "snap": snap_ev})
	# 阶段 2：全部成功后单线程提交（直接 append 严格 clone，禁止半提交 _append_event）
	_server_seq = snap_seq
	for seat2 in range(4):
		var pair: Dictionary = prepared[seat2] as Dictionary
		(_journals[seat2] as Array).append(pair["aa"])
		(_journals[seat2] as Array).append(pair["snap"])
	return aa_seq


func _emit_action_applied(action: Action, discarded_tile: Tile, discard_source: String) -> int:
	# AI 自动推进路径：同样保证 AA 与随后 SNAP 同 hash
	return _emit_action_applied_then_snapshot(action, discarded_tile, discard_source)


func _build_resolved_payload(action: Action, discarded_tile: Tile, discard_source: String) -> Dictionary:
	match action.kind:
		"DISCARD", "RIICHI":
			var tile_v: Variant = null
			if discarded_tile != null:
				tile_v = ProtocolViewCodec.tile_view_from_tile(discarded_tile)
			if tile_v == null:
				# 兜底：从河取最后一张
				var river: Array = _bc.state.discards_per_seat[action.seat]
				if not river.is_empty():
					tile_v = ProtocolViewCodec.tile_view_from_tile(river[river.size() - 1])
			if tile_v == null:
				return {}
			return {
				"tile": (tile_v as Dictionary).duplicate(true),
				"discard_source": discard_source if discard_source in ["DRAWN", "HAND"] else "HAND",
			}
		"PASS":
			return {}
		"TSUMO":
			var seat: Seat = _bc.state.seats[action.seat] as Seat
			var wt: Tile = null
			if seat != null:
				wt = seat.hand.find_by_instance_id(seat.last_drawn_instance_id)
			if wt == null:
				return {}
			var tv: Variant = ProtocolViewCodec.tile_view_from_tile(wt)
			if tv == null:
				return {}
			return {"winning_tile": (tv as Dictionary).duplicate(true)}
		"RON":
			var last: Tile = _bc.get("_last_discarded_tile") as Tile
			var from_s: int = int(_bc.get("_last_discarder_seat"))
			if last == null:
				return {}
			var rtv: Variant = ProtocolViewCodec.tile_view_from_tile(last)
			if rtv == null:
				return {}
			return {
				"winning_tile": (rtv as Dictionary).duplicate(true),
				"from_seat": from_s,
			}
		"CHI", "PON", "KAN":
			var actor_seat: Seat = _bc.state.seats[action.seat] as Seat
			if actor_seat == null:
				return {}
			# ADDED_KAN 的首条 ACTION_APPLIED 是加杠声明；抢杠窗结束前领域仍为 PON。
			# 从权威 PON + 手中第四张构造只读候选 MeldView，不能提前 promote。
			if action.kind == "KAN" \
					and str(action.payload.get("kan_kind", "")) == "ADDED_KAN":
				var meld_id: int = int(action.payload.get("meld_id", -1))
				var added_iid: int = int(action.payload.get("added_tile_instance_id", -1))
				var target: Meld = null
				for existing in actor_seat.melds:
					if existing is Meld and int((existing as Meld).meld_id) == meld_id:
						target = existing as Meld
						break
				var added_tile: Tile = actor_seat.hand.find_by_instance_id(added_iid)
				if target == null or target.kind != Meld.Kind.PON or added_tile == null:
					return {}
				var candidate_tiles: Array = []
				for existing_tile in target.tiles:
					var existing_view: Variant = ProtocolViewCodec.tile_view_from_tile(existing_tile)
					if existing_view == null:
						return {}
					candidate_tiles.append(existing_view)
				var added_view: Variant = ProtocolViewCodec.tile_view_from_tile(added_tile)
				if added_view == null:
					return {}
				candidate_tiles.append(added_view)
				var candidate: Variant = ProtocolViewCodec.meld_view_from_dict({
					"meld_id": target.meld_id,
					"kind": "ADDED_KAN",
					"from_seat": target.from_seat,
					"called_tile_instance_id": target.called_tile_instance_id,
					"added_tile_instance_id": added_iid,
					"tiles": candidate_tiles,
				})
				if candidate == null:
					return {}
				return {"meld": (candidate as Dictionary).duplicate(true)}
			# 其它鸣牌已在领域提交，取 actor 最新副露。
			if actor_seat.melds.is_empty():
				return {}
			var meld: Meld = actor_seat.melds[actor_seat.melds.size() - 1] as Meld
			var mv: Variant = ProtocolViewCodec.meld_view_from_meld(meld)
			if mv == null:
				return {}
			return {"meld": (mv as Dictionary).duplicate(true)}
		"DECLARE_ABORTIVE_DRAW":
			return {"reason": "KYUUSYU_KYUUHAI"}
		_:
			return {}


func _emit_private_prompt() -> bool:
	if _bc == null or _bc.state == null:
		return false
	if bool(_bc.get("_settled")):
		return false
	# 不在此处摸牌：DRAW→摸牌→ROOM_SNAPSHOT 由 start/submit 最终路径负责，
	# 保证 TURN_PROMPT.view_hash 对齐含 last_drawn 的 snapshot。
	# typed API：直接打开决策窗（禁止 has_method 兼容 fallback）
	for s in range(4):
		_bc.decision_context_for_seat(s)

	var win = _bc.get("_active_window")
	if win == null or not (win is DecisionWindow):
		return false
	var dw: DecisionWindow = win as DecisionWindow

	if dw.kind == DecisionWindow.KIND_TURN:
		var seat: int = int(dw.subject_seat)
		if not _is_human(seat):
			return false
		var ctx: DecisionContext = dw.context_for_seat(seat)
		if ctx == null:
			return false
		var payload := _build_turn_prompt_payload(ctx, seat)
		if payload.is_empty():
			return false
		# 复用该席最后 committed ROOM_SNAPSHOT.view_hash；禁止按新 seq 重建
		var vh: String = _last_committed_snapshot_view_hash(seat)
		if vh.is_empty():
			return false
		var candidate: int = _server_seq + 1
		var ne: NetworkedEvent = NetworkedEvent.make(
			"TURN_PROMPT", candidate, _room_id, payload, vh
		)
		if ne == null:
			return false
		var cloned: NetworkedEvent = NetworkedEvent.from_dict(ne.to_dict())
		if cloned == null:
			return false
		# #240：同一 candidate 上非目标席发 ROOM_SNAPSHOT filler，保证每席可见流连续
		var prepared: Array = [{"seat": seat, "clone": cloned}]
		for other in range(4):
			if other == seat:
				continue
			var fill: NetworkedEvent = _prepare_snapshot_filler(other, candidate)
			if fill == null:
				return false
			prepared.append({"seat": other, "clone": fill})
		_server_seq = candidate
		for item in prepared:
			(_journals[int(item["seat"])] as Array).append(item["clone"])
		return true

	if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
		# 同一逻辑 seq，多 recipient variant（仅 human 未响应席）+ 非目标 filler
		var targets: Array = []
		for s in dw.seats():
			var si: int = int(s)
			if not _is_human(si):
				continue
			if dw.has_responded(si):
				continue
			targets.append(si)
		if targets.is_empty():
			return false
		# 候选 seq：全部 seat 构造/roundtrip 成功前不得推进 _server_seq / 写 journal
		var candidate: int = _server_seq + 1
		var prepared: Array = []
		var covered: Dictionary = {}
		for si2 in targets:
			var seat_i: int = int(si2)
			var ctx2: DecisionContext = dw.context_for_seat(seat_i)
			if ctx2 == null:
				return false
			var pay2 := _build_claim_window_payload(ctx2, dw)
			if pay2.is_empty():
				return false
			# 复用该席最后 committed ROOM_SNAPSHOT.view_hash；禁止按新 seq 重建
			var vh2: String = _last_committed_snapshot_view_hash(seat_i)
			if vh2.is_empty() or vh2.length() != 64:
				return false
			var ne2: NetworkedEvent = NetworkedEvent.make(
				"CLAIM_WINDOW", candidate, _room_id, pay2, vh2
			)
			if ne2 == null:
				return false
			var cloned2: NetworkedEvent = NetworkedEvent.from_dict(ne2.to_dict())
			if cloned2 == null:
				return false
			prepared.append({"seat": seat_i, "clone": cloned2})
			covered[seat_i] = true
		for other2 in range(4):
			if covered.has(other2):
				continue
			var fill2: NetworkedEvent = _prepare_snapshot_filler(other2, candidate)
			if fill2 == null:
				return false
			prepared.append({"seat": other2, "clone": fill2})
		# 全部席成功后单线程提交：共享 candidate，每席恰好一条
		_server_seq = candidate
		for item in prepared:
			var seat_j: int = int(item["seat"])
			(_journals[seat_j] as Array).append(item["clone"])
		return true

	return false


## 私有 prompt 序号上非目标席的 ROOM_SNAPSHOT filler（#240 每席可见流连续）。
## 与 TURN_PROMPT/CLAIM_WINDOW 共享同一 candidate server_seq；失败返回 null。
func _prepare_snapshot_filler(seat: int, candidate_seq: int) -> NetworkedEvent:
	if seat < 0 or seat > 3:
		return null
	var sp: Dictionary = _build_room_snapshot_payload(seat, candidate_seq)
	if sp.is_empty():
		return null
	var vh: String = ProtocolViewCodec.compute_view_hash(sp)
	if vh.is_empty() or vh.length() != 64:
		return null
	var ne: NetworkedEvent = NetworkedEvent.make(
		"ROOM_SNAPSHOT", candidate_seq, _room_id, sp, vh
	)
	if ne == null:
		return null
	return NetworkedEvent.from_dict(ne.to_dict())


func _build_turn_prompt_payload(ctx: DecisionContext, seat: int) -> Dictionary:
	var seat_obj: Seat = _bc.state.seats[seat] as Seat
	if seat_obj == null:
		return {}
	var hand_out: Array = []
	for t in seat_obj.hand._tiles:
		var tv: Variant = ProtocolViewCodec.tile_view_from_tile(t)
		if tv == null:
			return {}
		hand_out.append(tv)
	var last_drawn: int = -1
	if Tile.is_valid_instance_id(seat_obj.last_drawn_instance_id):
		last_drawn = int(seat_obj.last_drawn_instance_id)
	return {
		"hand_seq": int(ctx.hand_seq),
		"decision_id": ctx.decision_id,
		"seat": seat,
		"hand": hand_out,
		"last_drawn_tile_instance_id": last_drawn,
		"allowed_actions": ctx.allowed_actions,
	}


func _build_claim_window_payload(ctx: DecisionContext, dw: DecisionWindow) -> Dictionary:
	var discarded: Tile = _bc.get("_last_discarded_tile") as Tile
	if discarded == null:
		return {}
	var tv: Variant = ProtocolViewCodec.tile_view_from_tile(discarded)
	if tv == null:
		return {}
	return {
		"hand_seq": int(ctx.hand_seq),
		"decision_id": ctx.decision_id,
		"discarded_by_seat": int(dw.discarder_seat),
		"discarded_tile": (tv as Dictionary).duplicate(true),
		"allowed_actions": ctx.allowed_actions,
	}


func _is_human(seat: int) -> bool:
	if seat < 0 or seat > 3:
		return false
	# #241：AI 接管中视为非真人（走 ActionSource.AI 自动推进）
	if bool(_ai_control_seats.get(seat, false)):
		return false
	return str(_participants[seat]) == str(GameSessionConfig.PARTICIPANT_HUMAN)


func _is_configured_human(seat: int) -> bool:
	if seat < 0 or seat > 3:
		return false
	return str(_participants[seat]) == str(GameSessionConfig.PARTICIPANT_HUMAN)


## AI 自动推进。成功/正常停在真人决策入口 → true；任一步 AA/SNAP 发布失败 → false。
## DRAW 且 current 为真人时绝不摸牌，交 submit 最终路径：draw → SNAP → TURN_PROMPT。
func _auto_advance_ai() -> bool:
	if _bc == null or _bc.state == null:
		return true
	var steps := 0
	while steps < MAX_AI_STEPS:
		steps += 1
		if bool(_bc.get("_settled")):
			return true
		# 真人 DRAW：禁止提前摸牌
		if int(_bc.state.phase) == BattlePhase.Kind.DRAW:
			var cur: int = int(_bc.state.current_seat)
			if _is_human(cur):
				return true
			if not _ensure_drawn():
				# 非合法 DRAW 等：无法推进则正常停（非发布失败）
				return true
		# facade 后重检：荒牌 settle 等由 submit 统一 HAND_SETTLED
		if bool(_bc.get("_settled")):
			return true
		# 打开窗
		for s in range(4):
			_bc.decision_context_for_seat(s)
		var win = _bc.get("_active_window")
		if win == null or not (win is DecisionWindow):
			if int(_bc.state.phase) == BattlePhase.Kind.SETTLE:
				_bc.set("_settled", true)
				return true
			# DRAW+human 已在上方返回；其余无窗视为正常停
			return true

		var dw: DecisionWindow = win as DecisionWindow
		if dw.kind == DecisionWindow.KIND_TURN:
			var actor: int = int(dw.subject_seat)
			if _is_human(actor):
				return true
			var act: Action = _build_ai_turn_action(actor)
			if act == null:
				return true
			var disc_tile: Tile = null
			var dsrc := "HAND"
			if act.kind == "DISCARD" or act.kind == "RIICHI":
				var iid: int = int(act.payload.get("tile_instance_id", -1))
				var so: Seat = _bc.state.seats[actor] as Seat
				if so != null:
					disc_tile = so.hand.find_by_instance_id(iid)
					if disc_tile != null and int(so.last_drawn_instance_id) == iid:
						dsrc = "DRAWN"
			var res: ActionResolution = _bc.apply_action(act, ActionSource.AI)
			if res == null or not res.accepted:
				return true
			if _emit_action_applied(act, disc_tile, dsrc) < 1:
				return false
			continue

		if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
			# 若有 human 未响应 → 停，交给 private prompt
			var need_human := false
			for s2 in dw.seats():
				var si: int = int(s2)
				if _is_human(si) and not dw.has_responded(si):
					need_human = true
					break
			if need_human:
				return true
			# 全部 AI：逐席自动 PASS（简化；不 mock 引擎）
			var progressed := false
			for s3 in dw.seats():
				var si3: int = int(s3)
				if dw.has_responded(si3):
					continue
				var pass_act: Action = _build_ai_claim_action(si3)
				if pass_act == null:
					continue
				var r2: ActionResolution = _bc.apply_action(pass_act, ActionSource.AI)
				if r2 == null or not r2.accepted:
					continue
				if _emit_action_applied(pass_act, null, "HAND") < 1:
					return false
				progressed = true
				break  # 一次一步，循环重取窗
			if not progressed:
				return true
			continue

		return true
	return true


func _build_ai_turn_action(actor: int) -> Action:
	var ctx: DecisionContext = _bc.decision_context_for_seat(actor)
	if ctx == null:
		return null
	var cmd: String = _next_cmd()
	var did: String = ctx.decision_id
	var hs: int = int(_bc.state.hand_seq)
	if ctx.has_kind("TSUMO"):
		return Action.tsumo(actor, _room_id, cmd, did, hs, _server_seq + 1)
	# 取首个 DISCARD offer
	for offer in ctx.allowed_actions:
		if typeof(offer) != TYPE_DICTIONARY:
			continue
		if str(offer.get("kind", "")) != "DISCARD":
			continue
		var opts: Array = offer.get("payload_options", [])
		if opts.is_empty():
			continue
		var opt: Dictionary = opts[0]
		var iid: int = int(opt.get("tile_instance_id", -1))
		return Action.discard(actor, iid, _room_id, cmd, did, hs, _server_seq + 1)
	return null


func _build_ai_claim_action(seat: int) -> Action:
	var ctx: DecisionContext = _bc.decision_context_for_seat(seat)
	if ctx == null:
		return null
	# AI 有 RON 时仍 PASS（loopback 简化；不 mock 引擎）
	if ctx.has_kind("PASS"):
		return Action.make_pass(
			seat, _room_id, _next_cmd(), ctx.decision_id,
			int(_bc.state.hand_seq), _server_seq + 1
		)
	return null


func _next_cmd() -> String:
	# 与 BC 风格一致的确定性 uuid
	var n: int = _server_seq * 10 + 1 + _command_cache.size()
	return "550e8400-e29b-41d4-a716-%012d" % (n + 1000)


## 从 BC.state.scores 捕获 4 席整数分；非法 → 空 Array。
func _capture_scores_array() -> Array:
	if _bc == null or _bc.state == null:
		return []
	var out: Array = []
	for s in _bc.state.scores:
		out.append(int(s))
	if out.size() != 4:
		return []
	return out


## 从真实 BC.events + state.scores + 冻结起始分推导 HAND_SETTLED payload。
## WIN：scores = state.scores 应用 WIN_DECLARED.extra.payout / winner_total（GameDriver 语义）。
## 流局：scores = state.scores（#232 不应用 noten / 整场规则）。
## 失败 → {}。
func _build_hand_settled_payload() -> Dictionary:
	if _bc == null or _bc.state == null:
		return {}
	if _hand_start_scores.size() != 4:
		return {}
	var outcome: String = ""
	var winner_seats: Array = []
	var loser_seat: int = -1
	var win_extra: Dictionary = {}
	var winner_actor: int = -1
	# 倒序找最末结算相关事件（真实 BattleEvent，非伪装）
	for i in range(_bc.events.size() - 1, -1, -1):
		var ev: BattleEvent = _bc.events[i]
		if ev == null:
			continue
		if ev.type == &"WIN_DECLARED":
			win_extra = ev.extra if typeof(ev.extra) == TYPE_DICTIONARY else {}
			winner_actor = int(ev.actor_seat)
			if bool(win_extra.get("is_tsumo", false)):
				outcome = "TSUMO"
				winner_seats = [winner_actor]
				loser_seat = -1
			else:
				outcome = "RON"
				winner_seats = [winner_actor]
				loser_seat = int(win_extra.get("discarder_seat", -1))
			break
		if ev.type == &"ABORTIVE_DRAW":
			outcome = "ABORTIVE_DRAW"
			winner_seats = []
			loser_seat = -1
			break
		if ev.type == &"EXHAUSTIVE_DRAW":
			outcome = "EXHAUSTIVE_DRAW"
			winner_seats = []
			loser_seat = -1
			break
	if outcome.is_empty():
		return {}

	var final_scores: Array = _capture_scores_array()
	if final_scores.size() != 4:
		return {}
	if outcome == "RON" or outcome == "TSUMO":
		# GameDriver.apply_result：loser -= payout[seat]；winner += winner_total
		var payout: Dictionary = win_extra.get("payout", {})
		if typeof(payout) != TYPE_DICTIONARY:
			return {}
		for seat_id in payout:
			var si: int = int(seat_id)
			if si < 0 or si > 3:
				return {}
			final_scores[si] = int(final_scores[si]) - int(payout[seat_id])
		if winner_actor < 0 or winner_actor > 3:
			return {}
		final_scores[winner_actor] = int(final_scores[winner_actor]) \
			+ int(win_extra.get("winner_total", 0))
		if outcome == "RON" and (loser_seat < 0 or loser_seat > 3 or loser_seat == winner_actor):
			return {}

	var deltas: Array = []
	for i2 in range(4):
		deltas.append(int(final_scores[i2]) - int(_hand_start_scores[i2]))

	return {
		"hand_seq": int(_bc.state.hand_seq),
		"outcome": outcome,
		"winner_seats": winner_seats,
		"loser_seat": loser_seat,
		"score_deltas": deltas,
		"scores": final_scores,
	}


## 四席 HAND_SETTLED 原子发布：先全部 make+strict roundtrip，再同一 server_seq 提交。
## 任一 recipient 失败 → false，零 mutation（不增 seq、无半条）。
## 未 settled → true（无需发布）；payload/hash 失败 → false。
## #241：本局幂等——已成功发布后再次调用不得分配 seq / 重复 journal。
func _emit_settled_if_needed() -> bool:
	if _bc == null or _bc.state == null:
		return false
	if not bool(_bc.get("_settled")):
		return true
	if _hand_settled_emitted:
		return true
	var payload: Dictionary = _build_hand_settled_payload()
	if payload.is_empty():
		return false
	var candidate: int = _server_seq + 1
	var prepared: Array = []
	for seat in range(4):
		# 仅接受该席已提交 ROOM_SNAPSHOT.view_hash；禁止按新 seq 重建 fallback
		var vh: String = _last_committed_snapshot_view_hash(seat)
		if vh.is_empty() or vh.length() != 64:
			return false
		var ne: NetworkedEvent = _build_recipient_event(
			"HAND_SETTLED", seat, candidate, payload, vh
		)
		if ne == null:
			return false
		prepared.append(ne)
	# 四席全部成功后单线程提交
	_server_seq = candidate
	for seat2 in range(4):
		(_journals[seat2] as Array).append(prepared[seat2])
	_hand_settled_emitted = true
	return true
