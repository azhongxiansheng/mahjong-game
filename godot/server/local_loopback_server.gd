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
## E5-04：可回放权威时钟基线（ms）；grace_deadline_at 不得依赖墙钟。
const REWARD_CLOCK_BASE_MS := 1_700_000_000_000

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
# #241：快照 module provider 注册表（STANDARD 仅 core_table；TRASH_TALK + reward_window）
var snapshot_registry: SnapshotModuleRegistry = null
# #241：HUMAN 席临时 AI 接管（不改 participants 配置）
var _ai_control_seats: Dictionary = {}  # seat(int) -> bool
# 测试：下一次 publish_snapshot 强制失败（不改业务路径）
var _fail_next_snapshot: bool = false
# 测试：下一次 ACTION_APPLIED/SNAP 发布强制失败（AI step / submit 共用 emit）
var _fail_next_action_publish: bool = false
# #241：本局 HAND_SETTLED 是否已发布（幂等，禁止重复 seq/journal；多局不得靠全局 journal 粗查）
var _hand_settled_emitted: bool = false
## E5-04：权威奖励时钟（仅 advance_reward_time 单调推进；禁止墙钟/伪造跳跃）
var _reward_authority_now_ms: int = REWARD_CLOCK_BASE_MS
## 整场是否结束：仅显式注入；默认 null=未知→流局按 match 继续(FULL_GRANT)
var _reward_match_ended = null
## CLOSING 后是否曾见过开放 CLAIM/ROB 窗（用于区分「尚未开 CLAIM」与「CLAIM 已终态」）
var _reward_claim_seen_open: bool = false
## 流局/终场 scoring close 因 grace 延迟：须先 SETTLED 再 HAND_SETTLED
var _reward_hand_settled_deferred: bool = false


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
	_reward_authority_now_ms = REWARD_CLOCK_BASE_MS
	_reward_match_ended = null
	_reward_claim_seen_open = false
	_reward_hand_settled_deferred = false
	if config != null:
		_room_id = config.session_id
		var parts: Array = config.participants
		if parts.size() == 4:
			_participants = parts.duplicate()
		mode_modules = ModeModuleBundle.from_config(config)
		# #252：仅 TRASH_TALK 注册 reward_window；STANDARD 严格仅 core_table
		if mode_modules != null and mode_modules.is_trash_talk():
			snapshot_registry = SnapshotModuleRegistry.make_trash_talk()
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

	# DRAW → 摸牌；ROOM_SNAPSHOT(IDLE) → OPENED → ROOM_SNAPSHOT(OPEN) → TURN_PROMPT
	# 开窗后补发新鲜 SNAP，供 prompt/重连持有 OPEN 投影（非仅 IDLE）
	_ensure_drawn()
	if not publish_snapshot():
		_reward_hard_reset()
		if _rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache):
			_started = frozen_started
			_hand_start_scores = frozen_hand_start
		return false
	# E5-04 / #252：权威开局快照后、首条 TURN_PROMPT 前开窗
	if not _maybe_open_reward_window():
		_reward_hard_reset()
		if _rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache):
			_started = frozen_started
			_hand_start_scores = frozen_hand_start
		return false
	# 开窗后 OPEN 投影 SNAP（seq 连续；失败全回滚）
	if _reward_module() != null:
		if not publish_snapshot():
			_reward_hard_reset()
			if _rollback_transaction(snap, frozen_seq, frozen_journals, frozen_cache):
				_started = frozen_started
				_hand_start_scores = frozen_hand_start
			return false
	if not _emit_private_prompt():
		_reward_hard_reset()
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
## TRASH_TALK 仅在 NetworkedEvent schema 合法时写入四席 journal。
## 对外要求已 start；开局路径用 `_publish_business_event_core`（快照后、标记 started 前）。
func try_publish_business_event(kind: String, payload: Dictionary) -> bool:
	if _rollback_failed:
		return false
	if not _started:
		return false
	return _publish_business_event_core(kind, payload)


## 内部发布：不检查 _started（供 start 事务内 OPEN 等）。
func _publish_business_event_core(kind: String, payload: Dictionary) -> bool:
	if _rollback_failed:
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


## bound_session_id：Worker 已验签 JOIN 后绑定的客户端 session_id。
## 公共房不得用等于 room_id 的 GameSessionConfig.session_id 冒充；空串时练习/直连退回 config。
func submit_action(action: Action, bound_session_id: String = "") -> CommandResult:
	if action == null:
		return _reject_result("", "INVALID_ACTION")
	if _rollback_failed:
		return _reject_result(action.command_id, ERROR_EVENT_PUBLISH_FAILED)

	# 业务指纹：仅 Action v1 exact-schema + 可规范化 payload 后形成；失败 → 不缓存
	var fp: String = _business_fingerprint(action, bound_session_id)
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

	# 指纹形成后：未开局/越权/错房/模式拒绝等首次结果均缓存
	if not _started:
		var cr_ns := _reject_result(cmd, ERROR_NOT_STARTED)
		_cache_command(cmd, fp, cr_ns)
		return _clone_cr(cr_ns)
	if not _is_human(int(action.seat)):
		var cr_un := _reject_result(cmd, ERROR_UNAUTHORIZED)
		_cache_command(cmd, fp, cr_un)
		return _clone_cr(cr_un)

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

	# apply 前捕获 ARS + RewardWindow；capture/hash 失败 → 非缓存 EVENT_PUBLISH_FAILED
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
	var frozen_rw: Dictionary = _reward_capture_state()
	var frozen_rw_clock: int = _reward_authority_now_ms
	var frozen_claim_seen: bool = _reward_claim_seen_open
	var frozen_hand_deferred: bool = _reward_hand_settled_deferred
	var frozen_hand_settled: bool = _hand_settled_emitted

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

	# 接受：RW 预消费 → ACTION_APPLIED+ROOM_SNAPSHOT（含动作后投影）→ 待发 CLOSING
	# 失败则 restore BC 与服务端副作用（含 RW/#241 flags）
	var aa_seq: int = _emit_action_applied_then_snapshot(
		action, discarded_tile, discard_source
	)
	if aa_seq < 1:
		_rollback_transaction(
			snap, frozen_seq, frozen_journals, frozen_cache,
			frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled
		)
		return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)

	# HUMAN apply 起至 AI 链 / 最终 prompt|settlement 为同一事务
	if not _auto_advance_ai():
		_rollback_transaction(
			snap, frozen_seq, frozen_journals, frozen_cache,
			frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled
		)
		return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)

	# 和牌/流局优先：BC 已 settled 时必须先 HAND 结果路径（RON/TSUMO → cancel），
	# 禁止先 _reward_try_release_barrier 误 FULL_GRANT（出口优先级 CANCELLED > DISPLAY > FULL）。
	if bool(_bc.get("_settled")):
		if not _emit_settled_if_needed():
			_rollback_transaction(
				snap, frozen_seq, frozen_journals, frozen_cache,
				frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
				frozen_hand_settled
			)
			return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
	else:
		# 未终局：评分屏障（满 24 CLAIM 全过等）
		if not _reward_try_release_barrier():
			_rollback_transaction(
				snap, frozen_seq, frozen_journals, frozen_cache,
				frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
				frozen_hand_settled
			)
			return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
		# 屏障释放后可能已 settle 窗口并 OPEN 下一窗；再处理摸打
		if bool(_bc.get("_settled")):
			if not _emit_settled_if_needed():
				_rollback_transaction(
					snap, frozen_seq, frozen_journals, frozen_cache,
					frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
					frozen_hand_settled
				)
				return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
		else:
			var human_draw_path := false
			if int(_bc.state.phase) == BattlePhase.Kind.DRAW:
				var cur_seat: int = int(_bc.state.current_seat)
				if _is_human(cur_seat) and _reward_allows_normal_progress():
					human_draw_path = true
					_ensure_drawn()
			if bool(_bc.get("_settled")):
				if not _emit_settled_if_needed():
					_rollback_transaction(
						snap, frozen_seq, frozen_journals, frozen_cache,
						frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
						frozen_hand_settled
					)
					return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
			else:
				if human_draw_path:
					if not publish_snapshot():
						_rollback_transaction(
							snap, frozen_seq, frozen_journals, frozen_cache,
							frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
							frozen_hand_settled
						)
						return _reject_result(cmd, ERROR_EVENT_PUBLISH_FAILED)
				# CLAIM 在 CLOSING 屏障期间仍须对真人可见；普通 TURN 受屏障阻止
				if not _emit_prompt_respecting_reward_barrier():
					_rollback_transaction(
						snap, frozen_seq, frozen_journals, frozen_cache,
						frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
						frozen_hand_settled
					)
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

## 只有权威 controller 完整恢复成功后，才回退服务端 seq/journal/cache/RewardWindow。
## mutation 前已用 can_restore 预检；若运行时仍失败则关闭提交入口，避免继续分叉。
## #241+#252：冻结覆盖 hand_settled_emitted / 奖励时钟 / claim_seen / deferred。
func _rollback_transaction(
	snap: AuthorityReplaySnapshot,
	frozen_seq: int,
	frozen_journals: Array,
	frozen_cache: Dictionary,
	frozen_rw: Dictionary = {},
	frozen_rw_clock: int = -1,
	frozen_claim_seen: bool = false,
	frozen_hand_deferred: Variant = null,
	frozen_hand_settled: Variant = null
) -> bool:
	if snap == null or not snap.restore_into(_bc):
		_rollback_failed = true
		_started = false
		return false
	_server_seq = frozen_seq
	_journals = frozen_journals
	_command_cache = frozen_cache
	if not frozen_rw.is_empty():
		if not _reward_restore_state(frozen_rw):
			_rollback_failed = true
			_started = false
			return false
	if frozen_rw_clock >= 0:
		_reward_authority_now_ms = frozen_rw_clock
	_reward_claim_seen_open = frozen_claim_seen
	if typeof(frozen_hand_deferred) == TYPE_BOOL:
		_reward_hand_settled_deferred = bool(frozen_hand_deferred)
	if typeof(frozen_hand_settled) == TYPE_BOOL:
		_hand_settled_emitted = bool(frozen_hand_settled)
	return true

## 业务指纹（ADR 全文唯一）：session_id + room_id + seat + hand_seq + decision_id
## + kind + 规范化 payload 摘要（payload_sha256）。client_seq 不参与。
## bound_session_id：JOIN 绑定的客户端 session；空串时退回 config.session_id（练习/直连）。
## 公共 Worker 路径必须传入已验签 session，不得依赖 room_id 冒充。
func _business_fingerprint(action: Action, bound_session_id: String = "") -> String:
	if action == null:
		return ""
	var sid: String = bound_session_id.strip_edges()
	if sid.is_empty():
		if _config == null:
			return ""
		sid = str(_config.session_id)
	if sid.is_empty():
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
		"session_id": sid,
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


## #242：确定性核心事件摘要（固定 recipient seat；排除 view_hash 与 Reward/Item/Ability）。
## 材料：每项仅 server_seq + kind + payload；数组 canonical JSON → SHA-256。
const CORE_EVENT_DIGEST_KINDS := [
	"ROOM_SNAPSHOT", "TURN_PROMPT", "CLAIM_WINDOW",
	"ACTION_APPLIED", "HAND_SETTLED", "MATCH_SETTLED",
]


func core_event_digest(recipient_seat: int = 0) -> String:
	if recipient_seat < 0 or recipient_seat > 3:
		return ""
	var items: Array = []
	var journal: Array = event_journal(recipient_seat)
	for item in journal:
		if not (item is NetworkedEvent):
			continue
		var ne: NetworkedEvent = item as NetworkedEvent
		if not CORE_EVENT_DIGEST_KINDS.has(ne.kind):
			continue
		items.append({
			"server_seq": int(ne.server_seq),
			"kind": str(ne.kind),
			"payload": ne.payload.duplicate(true) if typeof(ne.payload) == TYPE_DICTIONARY else {},
		})
	var digest: String = ProtocolViewCodec.compute_view_hash(items)
	if digest.is_empty() or digest.length() != 64:
		return ""
	return digest


## #242：指纹可形成后的会话层拒绝缓存入口（越权/过期连接等由 RoomSession 调用）。
## 无法形成指纹时原样拒绝且不写 cache。
func reject_action_cached(
	action: Action,
	bound_session_id: String,
	code: String
) -> CommandResult:
	if action == null:
		return _reject_result("", code if not code.is_empty() else "INVALID_ACTION")
	var fp: String = _business_fingerprint(action, bound_session_id)
	if fp.is_empty():
		return _reject_result(action.command_id, code if not code.is_empty() else "INVALID_ACTION")
	var cmd: String = action.command_id
	if _command_cache.has(cmd):
		var entry: Dictionary = _command_cache[cmd] as Dictionary
		var cached_fp: String = str(entry.get("fingerprint", ""))
		if cached_fp == fp:
			return _clone_cr(entry.get("result") as CommandResult)
		return _reject_result(cmd, ERROR_COMMAND_ID_CONFLICT)
	var err: String = code if not code.is_empty() else "INVALID_ACTION"
	var cr := _reject_result(cmd, err)
	_cache_command(cmd, fp, cr)
	return _clone_cr(cr)


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
	# #252：TRASH_TALK 时把真实 RewardWindowModule 传入 ctx（公开 DTO，无 seed/ARS）
	if snapshot_registry == null or _bc == null:
		return {}
	var ctx: Dictionary = {"state": _bc.state}
	var rw: RewardWindowModule = _reward_module()
	if rw != null:
		ctx["reward_window"] = rw
	var ser: Dictionary = snapshot_registry.serialize_modules(ctx, seat)
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
	var frozen_rw: Dictionary = _reward_capture_state()
	var frozen_rw_clock: int = _reward_authority_now_ms
	var frozen_claim_seen: bool = _reward_claim_seen_open
	var frozen_hand_deferred: bool = _reward_hand_settled_deferred
	var frozen_hand_settled: bool = _hand_settled_emitted
	if bool(_bc.get("_settled")):
		# 重连：始终先发新鲜 ROOM_SNAPSHOT（首条业务事件）
		if not publish_snapshot():
			return {"ok": false, "advanced": false, "code": ERROR_EVENT_PUBLISH_FAILED}
		# 幂等：若本局尚未 HAND_SETTLED 则补发一次；已发则零副作用
		if not _emit_settled_if_needed():
			_rollback_transaction(
				snap, frozen_seq, frozen_journals, frozen_cache,
				frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
				frozen_hand_settled
			)
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
		_rollback_transaction(
			snap, frozen_seq, frozen_journals, frozen_cache,
			frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
			frozen_hand_settled
		)
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
	var frozen_rw: Dictionary = _reward_capture_state()
	var frozen_rw_clock: int = _reward_authority_now_ms
	var frozen_claim_seen: bool = _reward_claim_seen_open
	var frozen_hand_deferred: bool = _reward_hand_settled_deferred
	var frozen_hand_settled: bool = _hand_settled_emitted

	# CLOSING 屏障：先刷新窗；普通 DRAW/TURN 不得越过；CLAIM/ROB 可推进
	for s0 in range(4):
		_bc.decision_context_for_seat(s0)
	_reward_note_claim_visibility()

	# 仅 AI 席 DRAW 可在本步摸牌；真人 DRAW 等待；CLOSING 屏障禁止普通摸牌
	if int(_bc.state.phase) == BattlePhase.Kind.DRAW:
		var cur: int = int(_bc.state.current_seat)
		if _is_human(cur):
			return {
				"ok": true, "advanced": false, "waiting_human": true,
				"settled": false, "code": "",
			}
		if not _reward_allows_normal_progress():
			return {
				"ok": true, "advanced": false, "waiting_human": false,
				"settled": false, "code": "",
			}
		if not _ensure_drawn():
			return {
				"ok": true, "advanced": false, "waiting_human": false,
				"settled": bool(_bc.get("_settled")), "code": "",
			}
		if bool(_bc.get("_settled")):
			if not _emit_settled_if_needed():
				_rollback_transaction(
					snap, frozen_seq, frozen_journals, frozen_cache,
					frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
					frozen_hand_settled
				)
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
			_rollback_transaction(
				snap, frozen_seq, frozen_journals, frozen_cache,
				frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
				frozen_hand_settled
			)
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
				_rollback_transaction(
					snap, frozen_seq, frozen_journals, frozen_cache,
					frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
					frozen_hand_settled
				)
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
		# CLOSING 屏障：禁止普通 TURN 越过
		if not _reward_allows_normal_progress():
			return {
				"ok": true, "advanced": false, "waiting_human": false,
				"settled": false, "code": "",
			}
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
			_rollback_transaction(
				snap, frozen_seq, frozen_journals, frozen_cache,
				frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
				frozen_hand_settled
			)
			return {
				"ok": true, "advanced": false, "waiting_human": false,
				"settled": false, "code": "",
			}
		# 含 RW 预消费：DISCARD 计入 24、SNAP 投影同步
		if _emit_action_applied(act, disc_tile, dsrc) < 1:
			_rollback_transaction(
				snap, frozen_seq, frozen_journals, frozen_cache,
				frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
				frozen_hand_settled
			)
			return {
				"ok": false, "advanced": false, "waiting_human": false,
				"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
			}
		# 终局 Action：同一 ARS 事务内必须完成 HAND_SETTLED
		if bool(_bc.get("_settled")):
			if not _emit_settled_if_needed():
				_rollback_transaction(
					snap, frozen_seq, frozen_journals, frozen_cache,
					frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
					frozen_hand_settled
				)
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
				_rollback_transaction(
					snap, frozen_seq, frozen_journals, frozen_cache,
					frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
					frozen_hand_settled
				)
				return {
					"ok": false, "advanced": false, "waiting_human": false,
					"settled": false, "code": ERROR_EVENT_PUBLISH_FAILED,
				}
			if bool(_bc.get("_settled")):
				if not _emit_settled_if_needed():
					_rollback_transaction(
						snap, frozen_seq, frozen_journals, frozen_cache,
						frozen_rw, frozen_rw_clock, frozen_claim_seen, frozen_hand_deferred,
						frozen_hand_settled
					)
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
## #252 Round 9：先按 candidate aa_seq 预消费 RewardWindow（mutate + 收集待发 effect），
## 再构造含动作后 RW 投影的 AA+SNAP，最后发布 CLOSING 等 effect。
## 逻辑：aa_seq = N，snap_seq = N+1；hash = hash(ROOM_SNAPSHOT payload @ N+1)。
## 任一步失败返回 -1；调用方回滚 BC/RW/seq/journals/flags。不抢占 server_seq 至提交瞬间。
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
	# 阶段 0：RW 预消费（不写 journal、不分配 seq）；收集待发业务 effect
	var pending_effects: Array = []
	if not _reward_preconsume_for_action(action, aa_seq, aa_payload, pending_effects):
		return -1
	# 阶段 1：四席逐席构造非空 snapshot / 64 位 hash / AA clone / SNAP clone
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
	# 阶段 2：提交 journal（唯一抢占 seq 点）
	_server_seq = snap_seq
	for seat2 in range(4):
		var pair: Dictionary = prepared[seat2] as Dictionary
		(_journals[seat2] as Array).append(pair["aa"])
		(_journals[seat2] as Array).append(pair["snap"])
	# 阶段 3：发布预消费收集的 CLOSING 等（在 AA+SNAP 之后；失败由调用方整事务回滚）
	for eff in pending_effects:
		if typeof(eff) != TYPE_DICTIONARY:
			return -1
		var ek: String = str((eff as Dictionary).get("kind", ""))
		var ep: Variant = (eff as Dictionary).get("payload", {})
		if ek.is_empty() or typeof(ep) != TYPE_DICTIONARY:
			return -1
		if not try_publish_business_event(ek, ep as Dictionary):
			return -1
	return aa_seq


func _emit_action_applied(action: Action, discarded_tile: Tile, discard_source: String) -> int:
	# AI / step_ai 路径：与 submit 同原子 RW 预消费 + AA+SNAP + 待发 effect
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
## CLOSING 屏障：CLAIM 未终态/宽限未满时禁止摸打/TURN 推进。
func _auto_advance_ai() -> bool:
	if _bc == null or _bc.state == null:
		return true
	var steps := 0
	while steps < MAX_AI_STEPS:
		steps += 1
		if bool(_bc.get("_settled")):
			return true
		# 打开窗（先刷新，供 CLAIM 可见性与屏障判定）
		for s in range(4):
			_bc.decision_context_for_seat(s)
		_reward_note_claim_visibility()

		# CLOSING：优先处理 CLAIM；禁止在屏障前进入普通摸打
		if _reward_is_closing():
			if _claim_or_rob_window_open():
				if not _auto_advance_claim_only():
					return false
				continue
			# 和牌已成立：不得 mark terminal / FULL_GRANT，交 submit 外层 cancel
			if bool(_bc.get("_settled")):
				return true
			# CLAIM 路径已结束且未和：冻结 context 并尝试 settle（不伪造时钟）
			if not _reward_try_release_barrier():
				return false
			if not _reward_allows_normal_progress():
				return true

		# 真人 DRAW：禁止提前摸牌
		if int(_bc.state.phase) == BattlePhase.Kind.DRAW:
			var cur: int = int(_bc.state.current_seat)
			if _is_human(cur):
				return true
			if not _reward_allows_normal_progress():
				return true
			if not _ensure_drawn():
				return true
		if bool(_bc.get("_settled")):
			return true
		for s2 in range(4):
			_bc.decision_context_for_seat(s2)
		var win = _bc.get("_active_window")
		if win == null or not (win is DecisionWindow):
			if int(_bc.state.phase) == BattlePhase.Kind.SETTLE:
				_bc.set("_settled", true)
				return true
			return true

		var dw: DecisionWindow = win as DecisionWindow
		if dw.kind == DecisionWindow.KIND_TURN:
			if not _reward_allows_normal_progress():
				return true
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
			# AA+SNAP 内已 RW 预消费；禁止再 _reward_on_action_applied（防双计数/双 append）
			var ai_seq: int = _emit_action_applied(act, disc_tile, dsrc)
			if ai_seq < 1:
				return false
			continue

		if dw.kind == DecisionWindow.KIND_CLAIM or dw.kind == DecisionWindow.KIND_ROB_KAN:
			if not _auto_advance_claim_only():
				return false
			continue

		return true
	return true


## 仅推进 CLAIM/ROB 窗（可在 CLOSING 屏障期间运行）。
func _auto_advance_claim_only() -> bool:
	for s in range(4):
		_bc.decision_context_for_seat(s)
	var win = _bc.get("_active_window")
	if win == null or not (win is DecisionWindow):
		return true
	var dw: DecisionWindow = win as DecisionWindow
	if dw.kind != DecisionWindow.KIND_CLAIM and dw.kind != DecisionWindow.KIND_ROB_KAN:
		return true
	_reward_claim_seen_open = true
	var need_human := false
	for s2 in dw.seats():
		var si: int = int(s2)
		if _is_human(si) and not dw.has_responded(si):
			need_human = true
			break
	if need_human:
		return true
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
		# AA+SNAP 内已 RW 预消费
		var claim_seq: int = _emit_action_applied(pass_act, null, "HAND")
		if claim_seq < 1:
			return false
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
## #252：顺序 REWARD_WINDOW_CLOSING → SETTLED|CANCELLED → HAND_SETTLED；
## 延迟宽限未 settle 时不得发 HAND_SETTLED（记 deferred，等 advance_reward_time）。
func _emit_settled_if_needed() -> bool:
	if _bc == null or _bc.state == null:
		return false
	if not bool(_bc.get("_settled")):
		return true
	# 幂等：复用 #241 本局标志；禁止全局 journal 粗查（多局 journal 仍有旧 HAND_SETTLED）
	if _hand_settled_emitted:
		return true
	var payload: Dictionary = _build_hand_settled_payload()
	if payload.is_empty():
		return false
	# E5-04：和牌取消 / 流局 scoring close 必须在 HAND_SETTLED 前完成窗口出口
	if not _reward_on_hand_result(payload):
		return false
	var rw: RewardWindowModule = _reward_module()
	# barrier 未释放：仍 CLOSING → 延后 HAND_SETTLED
	if rw != null and rw.phase == RewardWindowModule.PHASE_CLOSING:
		_reward_hand_settled_deferred = true
		return true
	return _publish_hand_settled_payload(payload)


## 四席同 seq 发布 HAND_SETTLED；本局已发则幂等 true。
func _publish_hand_settled_payload(payload: Dictionary) -> bool:
	if _hand_settled_emitted:
		_reward_hand_settled_deferred = false
		return true
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
	_server_seq = candidate
	for seat2 in range(4):
		(_journals[seat2] as Array).append(prepared[seat2])
	_hand_settled_emitted = true
	_reward_hand_settled_deferred = false
	return true


## 延迟 HAND_SETTLED：仅在奖励窗已离开 CLOSING 后发布一次。
func _emit_deferred_hand_settled_if_ready() -> bool:
	if not _reward_hand_settled_deferred:
		return true
	if _bc == null or not bool(_bc.get("_settled")):
		return true
	var rw: RewardWindowModule = _reward_module()
	if rw != null and rw.phase == RewardWindowModule.PHASE_CLOSING:
		return true
	var payload: Dictionary = _build_hand_settled_payload()
	if payload.is_empty():
		return false
	return _publish_hand_settled_payload(payload)


# ---- E5-04 RewardWindow 权威消费（练习场 = 未来 Worker 同纯逻辑）----

func _reward_module() -> RewardWindowModule:
	if mode_modules == null or not mode_modules.is_trash_talk():
		return null
	return mode_modules.reward_window


func _reward_hard_reset() -> void:
	var rw: RewardWindowModule = _reward_module()
	if rw != null:
		rw.hard_reset()
	_reward_authority_now_ms = REWARD_CLOCK_BASE_MS
	_reward_claim_seen_open = false
	_reward_hand_settled_deferred = false


func _reward_capture_state() -> Dictionary:
	var rw: RewardWindowModule = _reward_module()
	if rw == null:
		return {}
	return rw.capture_state()


func _reward_restore_state(snap: Dictionary) -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null:
		return snap.is_empty()
	if snap.is_empty():
		return false
	return rw.restore_state(snap)


func _reward_now_ms() -> int:
	return _reward_authority_now_ms


## 显式权威时钟 tick：原子事务。settle/open/HAND_SETTLED/恢复推进失败则全回滚。
func advance_reward_time(now_ms: int) -> bool:
	if _rollback_failed or not _started:
		return false
	if not _is_int_ms(now_ms):
		return false
	if now_ms < _reward_authority_now_ms:
		return false
	# 无副作用早返回：时钟未变且屏障不需要工作
	if now_ms == _reward_authority_now_ms:
		return true

	var snap: AuthorityReplaySnapshot = null
	if _bc != null and _bc.state != null:
		snap = AuthorityReplaySnapshot.capture(_bc)
		if snap == null or not snap.can_restore():
			return false
	var frozen_seq: int = _server_seq
	var frozen_journals: Array = []
	for s in range(4):
		frozen_journals.append(_clone_events(_journals[s] as Array))
	var frozen_cache: Dictionary = _command_cache.duplicate(true)
	var frozen_rw: Dictionary = _reward_capture_state()
	var frozen_clock: int = _reward_authority_now_ms
	var frozen_claim: bool = _reward_claim_seen_open
	var frozen_deferred: bool = _reward_hand_settled_deferred
	var frozen_hand_settled: bool = _hand_settled_emitted

	# 仅当本 tick 真正完成 CLOSING→终态/OPEN 转换时才恢复普通推进
	var rw0: RewardWindowModule = _reward_module()
	var closing_before: bool = rw0 != null and rw0.phase == RewardWindowModule.PHASE_CLOSING

	_reward_authority_now_ms = now_ms
	var ok := true
	if not _reward_try_release_barrier():
		ok = false
	elif not _emit_deferred_hand_settled_if_ready():
		ok = false
	else:
		var rw1: RewardWindowModule = _reward_module()
		var left_closing: bool = closing_before and rw1 != null \
			and rw1.phase != RewardWindowModule.PHASE_CLOSING
		# 满 24 等：本 tick 完成 barrier/RW 转换且 hand 未 settled → 恢复推进
		if left_closing and _bc != null and not bool(_bc.get("_settled")):
			if not _resume_normal_progress_after_reward_tick():
				ok = false
	if ok:
		return true
	# 全量回滚
	if snap != null:
		if not snap.restore_into(_bc):
			_rollback_failed = true
			_started = false
			return false
	_server_seq = frozen_seq
	_journals = frozen_journals
	_command_cache = frozen_cache
	_reward_authority_now_ms = frozen_clock
	_reward_claim_seen_open = frozen_claim
	_reward_hand_settled_deferred = frozen_deferred
	_hand_settled_emitted = frozen_hand_settled
	if not frozen_rw.is_empty() and not _reward_restore_state(frozen_rw):
		_rollback_failed = true
		_started = false
		return false
	return false


## tick 内仅在 RW 实际离开 CLOSING 后调用：AI 链 + 真人 DRAW 收尾 + 提示。
## AI 后若领域 settled → HAND/Reward 顺序；若停在真人 DRAW → ensure_drawn+快照。
func _resume_normal_progress_after_reward_tick() -> bool:
	if _bc == null or _bc.state == null:
		return true
	if not _reward_allows_normal_progress():
		return true
	if not _ensure_human_draw_snapshot_if_needed():
		return false
	if bool(_bc.get("_settled")):
		return _emit_settled_if_needed()
	if not _auto_advance_ai():
		return false
	# AI 链可能终局或把 current 交回真人 DRAW
	if bool(_bc.get("_settled")):
		return _emit_settled_if_needed()
	if not _ensure_human_draw_snapshot_if_needed():
		return false
	if bool(_bc.get("_settled")):
		return _emit_settled_if_needed()
	return _emit_prompt_respecting_reward_barrier()


## 当前为真人 DRAW 且允许普通推进时：摸牌 + 原子 ROOM_SNAPSHOT（失败 false）。
func _ensure_human_draw_snapshot_if_needed() -> bool:
	if _bc == null or _bc.state == null or bool(_bc.get("_settled")):
		return true
	if int(_bc.state.phase) != BattlePhase.Kind.DRAW:
		return true
	var cur: int = int(_bc.state.current_seat)
	if not _is_human(cur):
		return true
	if not _reward_allows_normal_progress():
		return true
	if not _ensure_drawn():
		# 摸牌失败可能已 exhaustive settled
		return true
	if bool(_bc.get("_settled")):
		return true
	return publish_snapshot()


## CLAIM/ROB 在 CLOSING 期间仍须发 CLAIM_WINDOW；普通 TURN 受屏障阻止。
func _emit_prompt_respecting_reward_barrier() -> bool:
	if _bc == null:
		return true
	for s in range(4):
		_bc.decision_context_for_seat(s)
	_reward_note_claim_visibility()
	if _claim_or_rob_window_open():
		return _emit_private_prompt()
	if not _reward_allows_normal_progress():
		return true
	return _emit_private_prompt()


## 整场是否结束的权威注入 seam（LocalLoopback 无完整 match 生命周期时显式设置）。
func set_reward_match_ended(ended: bool) -> void:
	_reward_match_ended = ended


func _is_int_ms(v: Variant) -> bool:
	return typeof(v) == TYPE_INT


func _reward_is_closing() -> bool:
	var rw: RewardWindowModule = _reward_module()
	return rw != null and rw.phase == RewardWindowModule.PHASE_CLOSING


func _claim_or_rob_window_open() -> bool:
	if _bc == null:
		return false
	var win = _bc.get("_active_window")
	if win is DecisionWindow:
		var dw: DecisionWindow = win as DecisionWindow
		return dw.kind == DecisionWindow.KIND_CLAIM \
			or dw.kind == DecisionWindow.KIND_ROB_KAN
	return false


func _reward_note_claim_visibility() -> void:
	if _reward_is_closing() and _claim_or_rob_window_open():
		_reward_claim_seen_open = true


## 是否允许下一普通摸牌/出牌/TURN_PROMPT（屏障 fail-closed）。
## CLOSING 期间一律禁止普通推进；CLAIM 提示走 _emit_prompt_respecting_reward_barrier。
func _reward_allows_normal_progress() -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null:
		return true
	# 未 settle 的 CLOSING 不得越过（即使 barrier 已 released 但 try_settle 失败）
	if rw.phase == RewardWindowModule.PHASE_CLOSING:
		return false
	return true


func _maybe_open_reward_window() -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null:
		return true
	if rw.phase == RewardWindowModule.PHASE_OPEN \
			or rw.phase == RewardWindowModule.PHASE_CLOSING:
		return true
	if _config == null or _bc == null or _bc.state == null:
		return false
	var chars: Array = []
	for c in _config.character_ids:
		chars.append(String(c))
	var parts: Array = []
	for p in _participants:
		parts.append(String(p))
	var pub_ini: Dictionary = TrashTalkPublicContextAdapter.public_snapshot_from_battle_state(
		_bc.state
	)
	# 同 hand 内 FULL_GRANT 后 index+1；hand_seq 变化后首窗归 0
	var window_index: int = 0
	var next_hand: int = int(_bc.state.hand_seq)
	if rw.phase == RewardWindowModule.PHASE_SETTLED:
		if next_hand == int(rw.hand_seq):
			window_index = int(rw.window_index) + 1
		else:
			window_index = 0
	var res: Dictionary = rw.open({
		"seed": int(_config.seed),
		"hand_seq": next_hand,
		"window_index": window_index,
		"rule_version": TrashTalkRuleCatalog.rule_version(),
		"room_id": _room_id,
		"character_ids": chars,
		"language": "zh",
		"participants": parts,
		"public_initial": pub_ini,
	})
	if not bool(res.get("ok", false)):
		return false
	if bool(res.get("idempotent", false)):
		return true
	_reward_claim_seen_open = false
	return _publish_business_event_core(
		"REWARD_WINDOW_OPENED", res["payload"] as Dictionary
	)


## 在 AA+SNAP 提交前按 candidate aa_seq 预消费 RewardWindow。
## - 不写 journal、不递增 _server_seq
## - 将合法公开 ACTION_APPLIED 写入评分上下文；弃牌计数/CLOSING 状态立即生效
## - CLOSING 等业务事件放入 pending_effects，由调用方在 AA+SNAP 之后发布
## - 幂等：同 fingerprint 弃牌不双计数；重复 append 由模块/指纹保护
func _reward_preconsume_for_action(
	action: Action,
	aa_seq: int,
	aa_payload: Dictionary,
	pending_effects: Array
) -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null or action == null:
		return true
	if rw.phase != RewardWindowModule.PHASE_OPEN \
			and rw.phase != RewardWindowModule.PHASE_CLOSING:
		return true
	if aa_seq < 1:
		return false
	# 公开 AA：用 payload 自哈希作 provisional view_hash（格式合法）；journal 最终 AA 用 SNAP hash
	var prov_vh: String = ProtocolViewCodec.compute_view_hash(aa_payload)
	if prov_vh.is_empty() or prov_vh.length() != 64:
		prov_vh = _last_committed_snapshot_view_hash(0)
	if prov_vh.is_empty() or prov_vh.length() != 64:
		return false
	var aa_ne: NetworkedEvent = NetworkedEvent.make(
		"ACTION_APPLIED", aa_seq, _room_id, aa_payload, prov_vh
	)
	if aa_ne == null:
		return false
	var verified: NetworkedEvent = NetworkedEvent.from_dict(aa_ne.to_dict())
	if verified == null:
		return false
	var ap: Dictionary = rw.append_public_event(verified.to_dict())
	if not bool(ap.get("ok", false)):
		if String(ap.get("reason", "")) == "AFTER_CONTEXT_BOUNDARY":
			return true
		return false
	if action.kind == "DISCARD" or action.kind == "RIICHI":
		var is_ai: bool = not _is_human(int(action.seat))
		var res: Dictionary = rw.on_discard_applied({
			"server_seq": aa_seq,
			"seat": int(action.seat),
			"kind": str(action.kind),
			"now_ms": _reward_now_ms(),
			"is_ai": is_ai,
		})
		if not bool(res.get("ok", false)):
			return false
		if String(res.get("kind", "")) == "REWARD_WINDOW_CLOSING" \
				and not bool(res.get("idempotent", false)):
			_reward_claim_seen_open = false
			pending_effects.append({
				"kind": "REWARD_WINDOW_CLOSING",
				"payload": (res["payload"] as Dictionary).duplicate(true),
			})
			# 弃牌后同步刷新 CLAIM 窗（状态在模块上；事件稍后发布）
			if _bc != null:
				for s in range(4):
					_bc.decision_context_for_seat(s)
			if _claim_or_rob_window_open():
				_reward_claim_seen_open = true
			else:
				var bp: int = int(_bc.state.phase) if _bc != null and _bc.state != null else -1
				if bp == BattlePhase.Kind.CLAIM:
					return false
				_reward_claim_seen_open = true
				# context boundary 用 candidate snap_seq 对齐本事务内下一公开序号
				var term0: Dictionary = rw.mark_claim_terminal({
					"context_boundary_server_seq": maxi(aa_seq + 1, 1),
				})
				if not bool(term0.get("ok", false)):
					return false
		elif String(res.get("kind", "")) == "REWARD_WINDOW_CLOSING" \
				and bool(res.get("idempotent", false)):
			# 幂等 CLOSING：不重复发事件，仍刷新 CLAIM 可见性
			if _bc != null:
				for s2 in range(4):
					_bc.decision_context_for_seat(s2)
			if _claim_or_rob_window_open():
				_reward_claim_seen_open = true
	return true


## 兼容：journal 已含 aa_seq 时补消费（仅当预消费路径未用）。优先走 preconsume。
func _reward_on_action_applied(action: Action, aa_seq: int) -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null or action == null:
		return true
	if rw.phase != RewardWindowModule.PHASE_OPEN \
			and rw.phase != RewardWindowModule.PHASE_CLOSING:
		return true
	# 若 public_events 已含该 aa_seq 的 ACTION_APPLIED，则仅处理弃牌幂等（不重复 append）
	if _reward_public_has_aa_seq(aa_seq):
		if action.kind == "DISCARD" or action.kind == "RIICHI":
			var is_ai2: bool = not _is_human(int(action.seat))
			var res2: Dictionary = rw.on_discard_applied({
				"server_seq": aa_seq,
				"seat": int(action.seat),
				"kind": str(action.kind),
				"now_ms": _reward_now_ms(),
				"is_ai": is_ai2,
			})
			if not bool(res2.get("ok", false)):
				return false
			# 预消费路径已处理 CLOSING 发布；此处仅幂等 true
		return true
	# 从 journal 取已提交 AA 再 append（旧路径兜底）
	if not _reward_append_journal_event(aa_seq):
		return false
	if action.kind == "DISCARD" or action.kind == "RIICHI":
		var is_ai: bool = not _is_human(int(action.seat))
		var res: Dictionary = rw.on_discard_applied({
			"server_seq": aa_seq,
			"seat": int(action.seat),
			"kind": str(action.kind),
			"now_ms": _reward_now_ms(),
			"is_ai": is_ai,
		})
		if not bool(res.get("ok", false)):
			return false
		if String(res.get("kind", "")) == "REWARD_WINDOW_CLOSING" \
				and not bool(res.get("idempotent", false)):
			_reward_claim_seen_open = false
			if not try_publish_business_event(
				"REWARD_WINDOW_CLOSING", res["payload"] as Dictionary
			):
				return false
			if _bc != null:
				for s in range(4):
					_bc.decision_context_for_seat(s)
			if _claim_or_rob_window_open():
				_reward_claim_seen_open = true
			else:
				var bp: int = int(_bc.state.phase) if _bc != null and _bc.state != null else -1
				if bp == BattlePhase.Kind.CLAIM:
					return false
				_reward_claim_seen_open = true
				var term0: Dictionary = rw.mark_claim_terminal({
					"context_boundary_server_seq": maxi(_server_seq, 1),
				})
				if not bool(term0.get("ok", false)):
					return false
	return true


func _reward_public_has_aa_seq(aa_seq: int) -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null:
		return false
	for ev in rw.get("_public_events") as Array:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = ev
		if str(d.get("kind", "")) == "ACTION_APPLIED" and int(d.get("server_seq", -1)) == aa_seq:
			return true
	return false


func _reward_append_journal_event(server_seq: int) -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null:
		return true
	if _journals.is_empty():
		return true
	var journal: Array = _journals[0] as Array
	for ne_v in journal:
		if not (ne_v is NetworkedEvent):
			continue
		var ne: NetworkedEvent = ne_v as NetworkedEvent
		if int(ne.server_seq) != server_seq:
			continue
		if ne.kind != "ACTION_APPLIED" and ne.kind != "CLAIM_WINDOW":
			continue
		var raw: Dictionary = ne.to_dict()
		var verified: NetworkedEvent = NetworkedEvent.from_dict(raw)
		if verified == null:
			return false
		var ap: Dictionary = rw.append_public_event(verified.to_dict())
		if not bool(ap.get("ok", false)):
			# AFTER_CONTEXT_BOUNDARY 等非致命边界可忽略后续事件
			if String(ap.get("reason", "")) == "AFTER_CONTEXT_BOUNDARY":
				return true
			return false
		return true
	return true


## 仅在真实 CLAIM 终态（曾见开放窗且现已关闭）或 scoring close 路径冻结 context。
## 禁止把「当前无 DecisionWindow」无条件等同 claim terminal（避免 24 弃后 CLAIM 尚未打开就放行）。
func _reward_try_mark_claim_terminal_if_ready() -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null or rw.phase != RewardWindowModule.PHASE_CLOSING:
		return true
	if rw.claim_is_terminal():
		return true
	# 和牌已成立：不得标 claim terminal（会导向 FULL_GRANT）
	if _bc != null and bool(_bc.get("_settled")):
		return true
	if _claim_or_rob_window_open():
		_reward_claim_seen_open = true
		return true
	# 仅当本窗 CLOSING 后确实开过 CLAIM 且现已关闭，才视为 CLAIM 终态
	if not _reward_claim_seen_open:
		return true
	var term: Dictionary = rw.mark_claim_terminal({
		"context_boundary_server_seq": maxi(_server_seq, 1),
	})
	return bool(term.get("ok", false))


func _reward_try_release_barrier() -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null:
		return true
	if rw.phase != RewardWindowModule.PHASE_CLOSING:
		return true
	if not _reward_try_mark_claim_terminal_if_ready():
		return false
	if not rw.claim_is_terminal():
		return true
	# 禁止伪造 deadline：仅 all-terminal 或真实 now>=deadline
	if not rw.barrier_released(_reward_now_ms()):
		return true
	# 屏障已释放：必须 settle 成功（或幂等）；SCORE/ASSIGN 等失败 fail-closed
	var settled: Dictionary = rw.try_settle({"now_ms": _reward_now_ms()})
	if not bool(settled.get("ok", false)):
		return false
	if bool(settled.get("idempotent", false)):
		return true
	if not try_publish_business_event(
		"REWARD_WINDOW_SETTLED", settled["payload"] as Dictionary
	):
		return false
	# 仅同局满 24 FULL_GRANT 开下一窗；hand 已 settled（流局/终场）不得伪造 OPEN
	if String(rw.window_exit) == RewardWindowModule.EXIT_FULL_GRANT \
			and (_bc == null or not bool(_bc.get("_settled"))):
		if not _maybe_open_reward_window():
			return false
	return true


func _reward_on_hand_result(hand_payload: Dictionary) -> bool:
	var rw: RewardWindowModule = _reward_module()
	if rw == null:
		return true
	if rw.phase != RewardWindowModule.PHASE_OPEN \
			and rw.phase != RewardWindowModule.PHASE_CLOSING:
		return true
	var outcome := String(hand_payload.get("outcome", ""))
	if outcome == "RON" or outcome == "TSUMO":
		var can: Dictionary = rw.cancel_by_win({"now_ms": _reward_now_ms()})
		if not bool(can.get("ok", false)):
			return false
		if bool(can.get("idempotent", false)):
			return true
		return try_publish_business_event(
			"REWARD_WINDOW_CANCELLED", can["payload"] as Dictionary
		)
	# 流局：出口仅接受显式权威 match_ended；默认 match 继续 → FULL_GRANT
	# 不猜测 hand_seq 阈值（连庄/半庄未由 LocalLoopback 完整推进）
	var is_match_end := false
	if typeof(_reward_match_ended) == TYPE_BOOL:
		is_match_end = bool(_reward_match_ended)
	elif hand_payload.has("match_ended") and typeof(hand_payload["match_ended"]) == TYPE_BOOL:
		is_match_end = bool(hand_payload["match_ended"])
	var result_seq: int = maxi(_server_seq, 1)
	# scoring close：结果判定事务内 claim_is_terminal=true（无 CLAIM 路径）
	_reward_claim_seen_open = true
	var sc: Dictionary = rw.begin_scoring_close({
		"result_server_seq": result_seq,
		"now_ms": _reward_now_ms(),
		"is_match_end": is_match_end,
	})
	if not bool(sc.get("ok", false)):
		return false
	for eff in sc.get("effects", []):
		if typeof(eff) != TYPE_DICTIONARY:
			continue
		var kind := String(eff.get("kind", ""))
		if kind.is_empty():
			continue
		if not try_publish_business_event(kind, eff["payload"] as Dictionary):
			return false
	# 无 utterance 或全终态时可立即 settle；否则等待 advance_reward_time
	if not rw.barrier_released(_reward_now_ms()):
		return true
	var settled2: Dictionary = rw.try_settle({"now_ms": _reward_now_ms()})
	if not bool(settled2.get("ok", false)):
		return false
	if bool(settled2.get("idempotent", false)):
		return true
	return try_publish_business_event(
		"REWARD_WINDOW_SETTLED", settled2["payload"] as Dictionary
	)
