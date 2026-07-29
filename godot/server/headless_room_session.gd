class_name HeadlessRoomSession
extends RefCounted

# #240：单房间权威会话。惰性建房后持有 LocalLoopbackServer；
# 全部 HUMAN READY 才 start。客户端不得注入 seed/牌墙/结果。
# #241：座位连接代际、30s lease、AI 接管/归还。
# #376：整场 match owner（GameDriver + 跨局 LocalLoopback + READY 超时）。
# 网络端到端未验证。

const RULE_VERSION := "riichi-v1"
const ERR_UNAUTHORIZED := "UNAUTHORIZED"
const ERR_COMMAND_REJECTED := "COMMAND_REJECTED"
const ERR_FORGERY_REJECTED := "FORGERY_REJECTED"
const ERR_NOT_READY := "COMMAND_REJECTED"
const ERR_PROTOCOL := "PROTOCOL_VERSION_UNSUPPORTED"
const ERR_ROOM_FAILED := "ROOM_FAILED"
## #241：掉线后保留座位的宽限（毫秒）
const RECONNECT_LEASE_MS := 30000
## #376：assigned 后真人 JOIN+READY 宽限（毫秒）；起点=首次合法 bootstrap 单调时钟
const HUMAN_READY_TIMEOUT_MS := 30000
const HANDS_PER_ROUND := 4
const EAST_TOTAL_HANDS := 4
const HANCHAN_TOTAL_HANDS := 8

var room_id: String = ""
var round_kind: String = ""
var game_mode: String = ""
var participants: Array = []  # wire HUMAN/AI ×4
var authority_seed: int = 0
var character_ids: Array = []
var config: GameSessionConfig = null
var server: LocalLoopbackServer = null
## #376：整场权威驱动（hand_index/dealer/honba/…）；客户端不可提交覆盖
var match_driver: GameDriver = null
## #376：与整场共享的模式模块（TT 跨局保留；STANDARD 四零）
var mode_modules: ModeModuleBundle = null

# seat -> seat state dict
var _seats: Dictionary = {}
var _started: bool = false
var _seed_override: int = -1  # 测试注入；生产用 Crypto
## #376：bootstrap 单调时钟（ms）；READY 超时起点
var _bootstrap_at_ms: int = -1
## #376 R5：Worker 单调 ms → RewardWindow 权威时钟映射起点（bootstrap 冻结）
var _auth_clock_worker_origin_ms: int = -1
var _auth_clock_reward_origin_ms: int = -1
var _room_failed: bool = false
var _fail_code: String = ""
var _fail_message: String = ""


func _init() -> void:
	pass


## 首个合法 JOIN 时调用。claims 来自已验签 room_token。
## now_ms：Worker 单调时钟；<0 时用 Time.get_ticks_msec（仅非 Worker 路径）。
func bootstrap_from_claims(claims: Dictionary, now_ms: int = -1) -> bool:
	if server != null:
		return false
	if claims.is_empty():
		return false
	room_id = str(claims.get("room_id", ""))
	round_kind = str(claims.get("round_kind", ""))
	game_mode = str(claims.get("game_mode", ""))
	var parts_raw: Variant = claims.get("participants", [])
	if typeof(parts_raw) != TYPE_ARRAY:
		return false
	participants = []
	for p in parts_raw:
		participants.append(StringName(str(p)))
	if room_id.is_empty() or participants.size() != 4:
		return false
	# #374：四席角色必须来自已验签 claims；禁止本地再抽。
	var chars_raw: Variant = claims.get("character_ids", null)
	if typeof(chars_raw) != TYPE_ARRAY:
		return false
	character_ids = []
	for c in chars_raw:
		var cid := StringName(str(c))
		if String(cid).is_empty() or CharacterPool.find(cid) == null:
			return false
		character_ids.append(cid)
	if character_ids.size() != 4:
		return false
	if _seed_override >= 0:
		authority_seed = _seed_override
	else:
		authority_seed = _generate_seed()
	var wire_parts: Array = []
	for p in participants:
		wire_parts.append(p)
	config = GameSessionConfig.create_validated(
		GameSessionConfig.ROOM_PUBLIC_CASUAL,
		StringName(round_kind),
		StringName(game_mode),
		wire_parts,
		character_ids,
		authority_seed,
		room_id,
		RULE_VERSION
	)
	if config == null:
		return false
	var total_hands: int = EAST_TOTAL_HANDS
	if config.round_kind == GameSessionConfig.ROUND_HANCHAN:
		total_hands = HANCHAN_TOTAL_HANDS
	elif config.round_kind != GameSessionConfig.ROUND_EAST:
		return false
	mode_modules = ModeModuleBundle.from_config(config)
	if mode_modules == null:
		return false
	if mode_modules.is_trash_talk() and mode_modules.item_inventory != null:
		mode_modules.item_inventory.set_match_namespace(str(config.session_id))
	match_driver = GameDriver.new(authority_seed, total_hands, HANDS_PER_ROUND)
	match_driver.mode_modules = mode_modules
	var mods_ref: ModeModuleBundle = mode_modules
	match_driver.bc_factory = func(
		hand_seed: int,
		dealer: int,
		use_heuristic: bool,
		round_wind: int,
		hand_seq: int
	) -> BattleController:
		var bc := BattleController.new(
			hand_seed, dealer, use_heuristic, round_wind, hand_seq
		)
		if bc != null:
			bc.bind_mode_modules(mods_ref)
		return bc
	var first_bc: BattleController = match_driver.start_hand() as BattleController
	if first_bc == null or first_bc.state == null:
		match_driver = null
		mode_modules = null
		return false
	server = LocalLoopbackServer.new(
		config, match_driver.dealer_seat, first_bc, mode_modules
	)
	if server == null or server._bc == null:
		server = null
		match_driver = null
		mode_modules = null
		return false
	server.match_owner = self
	server.match_end_after_hand = Callable(self, "will_match_end_after_hand")
	server.on_hand_settled_committed = Callable(self, "on_hand_settled_committed")
	# GameDriver.battle 与 server BC 对齐（首局）
	match_driver.battle = first_bc
	_seats.clear()
	for i in range(4):
		_seats[i] = _empty_seat_state(String(participants[i]))
	_started = false
	_room_failed = false
	_fail_code = ""
	_fail_message = ""
	_auth_clock_worker_origin_ms = -1
	_auth_clock_reward_origin_ms = -1
	if now_ms >= 0:
		_bootstrap_at_ms = int(now_ms)
	else:
		_bootstrap_at_ms = Time.get_ticks_msec()
	# #376 R5：冻结 Worker 单调时钟 → Reward 权威时钟映射（非墙钟、非 ticks 直灌）
	_bind_authority_clock_origin(_bootstrap_at_ms)
	return true


func set_seed_override_for_test(p_seed: int) -> void:
	_seed_override = p_seed


## #376：测试可覆盖 bootstrap 时钟起点。
func set_bootstrap_at_ms_for_test(ms: int) -> void:
	_bootstrap_at_ms = ms


## #376 R5：bootstrap 冻结 Worker ms ↔ Reward authority ms 映射。
func _bind_authority_clock_origin(worker_ms: int) -> void:
	if _auth_clock_worker_origin_ms >= 0:
		return
	_auth_clock_worker_origin_ms = maxi(0, int(worker_ms))
	_auth_clock_reward_origin_ms = LocalLoopbackServer.REWARD_CLOCK_BASE_MS


## #376 R5：Worker 单调 ms → RewardWindow 权威时钟（仅非负 delta）。
func map_worker_ms_to_reward_authority(worker_ms: int) -> int:
	if _auth_clock_worker_origin_ms < 0:
		_bind_authority_clock_origin(worker_ms)
	var delta: int = int(worker_ms) - _auth_clock_worker_origin_ms
	if delta < 0:
		delta = 0
	return _auth_clock_reward_origin_ms + delta


## #376 R5：Worker poll 推进本房间 Reward 权威时钟。
## 倒退/相同 → 零副作用 true；advance 失败 → false（调用方 ROOM_FAILED）。
func tick_reward_authority(worker_ms: int) -> bool:
	if server == null or _room_failed:
		return true
	if not _started or is_match_completed():
		return true
	var target: int = map_worker_ms_to_reward_authority(worker_ms)
	var cur: int = server.reward_authority_now_ms()
	if target <= cur:
		return true
	return server.advance_reward_time(target)


## #376 R5：权威 tick/其它失败 → 稳定 ROOM_FAILED（幂等）。
func mark_room_failed(code: String = ERR_ROOM_FAILED, message: String = "authority failed") -> void:
	if _room_failed:
		return
	_room_failed = true
	_fail_code = code if not str(code).is_empty() else ERR_ROOM_FAILED
	_fail_message = message if not str(message).is_empty() else "authority failed"


func is_bootstrapped() -> bool:
	return server != null and match_driver != null


func is_started() -> bool:
	return _started


func is_room_failed() -> bool:
	return _room_failed


func fail_code() -> String:
	return _fail_code


func fail_message() -> String:
	return _fail_message


## #376：只读 match 权威状态（客户端不可覆盖）。
func export_match_state() -> Dictionary:
	if match_driver == null:
		return {}
	return match_driver.export_match_state()


## #376 P1-1/P1-3：事务 capture（含 GameDriver battle 引用）。
func capture_match_authority_state() -> Dictionary:
	if match_driver == null:
		return {}
	return match_driver.capture_authority_state()


## #376：事务 restore；失败 false。
func restore_match_authority_state(snap: Dictionary) -> bool:
	if match_driver == null:
		return snap.is_empty()
	return match_driver.restore_authority_state(snap)


## #376：HAND_SETTLED payload → 是否整场终场（生产 RewardWindow / MATCH 判定）。
func will_match_end_after_hand(settlement: Dictionary) -> bool:
	if match_driver == null:
		return false
	return match_driver.will_finish_after_settlement(settlement)


## #376：HAND_SETTLED 已原子发布并 commit 后调用；推进账本并返回下一局 BC 或 finished。
## #376 R4：任何非空 error 必须 finished=false，禁止伪装终场。
func on_hand_settled_committed(settlement: Dictionary) -> Dictionary:
	if match_driver == null:
		return {"finished": false, "bc": null, "error": "NO_DRIVER"}
	var adv: Dictionary = match_driver.advance_from_committed_settlement(settlement)
	if not str(adv.get("error", "")).is_empty():
		return {"finished": false, "bc": null, "error": str(adv.get("error", ""))}
	if bool(adv.get("finished", false)) or match_driver.finished:
		return {"finished": true, "bc": null, "renchan": bool(adv.get("renchan", false))}
	var next_bc: BattleController = match_driver.start_hand() as BattleController
	if next_bc == null:
		return {"finished": false, "bc": null, "error": "START_HAND_FAILED"}
	# 跨局保留 AI 接管：由 LocalLoopback.start_next_hand 重绑 _ai_control_seats
	return {
		"finished": false,
		"bc": next_bc,
		"renchan": bool(adv.get("renchan", false)),
		"dealer": match_driver.dealer_seat,
	}


## #376：poll/tick 路径：未开局且真人未在时限内全部 JOIN+READY → 权威失败。
## 返回 true 表示本 tick 新失败。
func tick_ready_timeout(now_ms: int) -> bool:
	if _room_failed or _started or server == null:
		return false
	if _bootstrap_at_ms < 0:
		return false
	if int(now_ms) - _bootstrap_at_ms < HUMAN_READY_TIMEOUT_MS:
		return false
	# 仍有 HUMAN 未 JOIN+READY
	if all_humans_ready() and _all_humans_joined():
		return false
	_room_failed = true
	_fail_code = ERR_ROOM_FAILED
	_fail_message = "humans not ready within timeout"
	return true


func _all_humans_joined() -> bool:
	for i in range(4):
		if not is_human_seat(i):
			continue
		var st: Dictionary = _seats[i]
		if not bool(st.get("joined", false)):
			return false
	return true


func participant_kind(seat: int) -> String:
	if seat < 0 or seat > 3 or not _seats.has(seat):
		return ""
	return str((_seats[seat] as Dictionary).get("kind", ""))


func is_human_seat(seat: int) -> bool:
	return participant_kind(seat) == "HUMAN"


## 只读预检：是否允许 JOIN/重连（不改 seat 状态）。
func can_join(seat: int, session_id: String) -> Dictionary:
	if server == null:
		return _fail(ERR_COMMAND_REJECTED, "room not bootstrapped")
	if _room_failed:
		return _fail(ERR_ROOM_FAILED, _fail_message if not _fail_message.is_empty() else "room failed")
	if seat < 0 or seat > 3:
		return _fail(ERR_UNAUTHORIZED, "invalid seat")
	if not is_human_seat(seat):
		return _fail(ERR_UNAUTHORIZED, "AI seat cannot join")
	if session_id.is_empty():
		return _fail(ERR_UNAUTHORIZED, "missing session")
	var st: Dictionary = _seats[seat]
	var is_reconnect := false
	if bool(st.get("joined", false)):
		if str(st.get("session_id", "")) != session_id:
			return _fail(ERR_UNAUTHORIZED, "seat occupied")
		is_reconnect = true
	var out := _ok()
	out["reconnect"] = is_reconnect
	return out


## JOIN / 同 session 重连绑定。返回 {ok,code,message,replaced_conn_id,reconnect}。
## replaced_conn_id >=0 表示需 Worker 原子作废旧连接（不启动 lease）。
## 注意：重连交付失败路径不得先调用本方法（见 Worker prepare→commit 顺序）。
func join(seat: int, session_id: String, conn_id: int = -1, generation: int = 0) -> Dictionary:
	if _room_failed:
		return _fail(ERR_ROOM_FAILED, _fail_message if not _fail_message.is_empty() else "room failed")
	var pre: Dictionary = can_join(seat, session_id)
	if not bool(pre.get("ok", false)):
		return pre
	var st: Dictionary = (_seats[seat] as Dictionary).duplicate(true)
	var replaced: int = -1
	var is_reconnect: bool = bool(pre.get("reconnect", false))
	if is_reconnect:
		var prev_cid: int = int(st.get("active_conn_id", -1))
		if prev_cid >= 0 and prev_cid != conn_id:
			replaced = prev_cid
	st["joined"] = true
	st["session_id"] = session_id
	if not is_reconnect:
		st["ready"] = false
	st["active_conn_id"] = conn_id
	st["conn_generation"] = generation
	st["connected"] = conn_id >= 0
	# 提交后：清 lease，归还真人控制
	st["lease_deadline_ms"] = -1
	st["ai_control"] = false
	if server != null:
		server.set_seat_ai_control(seat, false)
	_seats[seat] = st
	var out := _ok()
	out["replaced_conn_id"] = replaced
	out["reconnect"] = is_reconnect
	return out


## 捕获座位控制态（重连交付失败回滚用）。
func capture_seat_control_state(seat: int) -> Dictionary:
	if not _seats.has(seat):
		return {}
	var st: Dictionary = _seats[seat]
	return {
		"session_id": str(st.get("session_id", "")),
		"ready": bool(st.get("ready", false)),
		"joined": bool(st.get("joined", false)),
		"connected": bool(st.get("connected", false)),
		"active_conn_id": int(st.get("active_conn_id", -1)),
		"conn_generation": int(st.get("conn_generation", 0)),
		"lease_deadline_ms": int(st.get("lease_deadline_ms", -1)),
		"ai_control": bool(st.get("ai_control", false)),
		"server_ai": server != null and server.is_seat_ai_controlled(seat),
	}


## 回滚座位控制态（含 server AI 标志）。
func restore_seat_control_state(seat: int, frozen: Dictionary) -> void:
	if frozen.is_empty() or not _seats.has(seat):
		return
	var st: Dictionary = (_seats[seat] as Dictionary).duplicate(true)
	st["session_id"] = str(frozen.get("session_id", st.get("session_id", "")))
	st["ready"] = bool(frozen.get("ready", st.get("ready", false)))
	st["joined"] = bool(frozen.get("joined", st.get("joined", false)))
	st["connected"] = bool(frozen.get("connected", st.get("connected", false)))
	st["active_conn_id"] = int(frozen.get("active_conn_id", st.get("active_conn_id", -1)))
	st["conn_generation"] = int(frozen.get("conn_generation", st.get("conn_generation", 0)))
	st["lease_deadline_ms"] = int(frozen.get("lease_deadline_ms", st.get("lease_deadline_ms", -1)))
	st["ai_control"] = bool(frozen.get("ai_control", false))
	_seats[seat] = st
	if server != null:
		server.set_seat_ai_control(seat, bool(frozen.get("server_ai", false)))


## Worker：连接关闭。仅当关闭的是当前有效连接时启动 30s lease。
func on_connection_closed(
	seat: int,
	session_id: String,
	conn_id: int,
	generation: int,
	now_ms: int
) -> Dictionary:
	if seat < 0 or seat > 3 or not _seats.has(seat):
		return _fail(ERR_COMMAND_REJECTED, "bad seat")
	var st: Dictionary = (_seats[seat] as Dictionary).duplicate(true)
	if str(st.get("session_id", "")) != session_id:
		return _ok()  # 无关
	if int(st.get("active_conn_id", -1)) != conn_id:
		return _ok()  # 已被替换，不启动 lease
	if int(st.get("conn_generation", -1)) != generation:
		return _ok()
	st["connected"] = false
	st["active_conn_id"] = -1
	# 仅已开局且仍为真人控制时启动 lease
	if _started and not bool(st.get("ai_control", false)):
		st["lease_deadline_ms"] = int(now_ms) + RECONNECT_LEASE_MS
	else:
		st["lease_deadline_ms"] = -1
	_seats[seat] = st
	return _ok()


## 单调时钟 tick：now >= deadline → 标记 AI 接管（不在此推进 Action）。
## 返回本 tick 新接管的 seat 列表。AI 单步由 step_ai_once / Worker poll 驱动。
func tick_leases(now_ms: int) -> Array:
	var taken: Array = []
	if server == null or not _started:
		return taken
	for i in range(4):
		if not is_human_seat(i):
			continue
		var st: Dictionary = (_seats[i] as Dictionary).duplicate(true)
		var dl: int = int(st.get("lease_deadline_ms", -1))
		if dl < 0:
			continue
		if int(now_ms) < dl:
			continue
		# 精确：now >= deadline → AI 接管
		st["lease_deadline_ms"] = -1
		st["ai_control"] = true
		_seats[i] = st
		server.set_seat_ai_control(i, true)
		taken.append(i)
	return taken


## 是否存在 AI 接管中的配置 HUMAN 席。
func has_ai_controlled_seat() -> bool:
	for i in range(4):
		if is_seat_ai_controlled(i):
			return true
	return false


## AI 单步推进（至多一个权威 Action + 原子发布）。
func step_ai_once() -> Dictionary:
	if server == null or not _started:
		return {
			"ok": false, "advanced": false, "waiting_human": false,
			"settled": false, "code": ERR_COMMAND_REJECTED,
		}
	if not has_ai_controlled_seat():
		return {
			"ok": true, "advanced": false, "waiting_human": false,
			"settled": false, "code": "",
		}
	return server.step_ai_once()


## 重连交付准备（不绑定连接）：临时归还控制并发布当前快照+决策窗。
## 失败时调用方必须 restore_seat_control_state；成功后由 join 提交绑定。
func prepare_reconnect_delivery(seat: int) -> Dictionary:
	if server == null or not _started:
		return _fail(ERR_COMMAND_REJECTED, "not started")
	if seat < 0 or seat > 3:
		return _fail(ERR_UNAUTHORIZED, "bad seat")
	# 交付投影按真人控制生成（不在此永久提交 seat 字典；Worker 失败可回滚）
	server.set_seat_ai_control(seat, false)
	var r: Dictionary = server.publish_resync_snapshot_and_prompt()
	if not bool(r.get("ok", false)):
		return _fail(ERR_COMMAND_REJECTED, str(r.get("code", "reconnect delivery failed")))
	return _ok()


func is_connection_active(seat: int, conn_id: int, generation: int) -> bool:
	if seat < 0 or seat > 3 or not _seats.has(seat):
		return false
	var st: Dictionary = _seats[seat]
	if not bool(st.get("connected", false)):
		return false
	if int(st.get("active_conn_id", -1)) != conn_id:
		return false
	if int(st.get("conn_generation", -1)) != generation:
		return false
	return true


func seat_state_for_test(seat: int) -> Dictionary:
	if not _seats.has(seat):
		return {}
	return (_seats[seat] as Dictionary).duplicate(true)


func is_seat_ai_controlled(seat: int) -> bool:
	if not _seats.has(seat):
		return false
	return bool((_seats[seat] as Dictionary).get("ai_control", false))


func lease_deadline_ms(seat: int) -> int:
	if not _seats.has(seat):
		return -1
	return int((_seats[seat] as Dictionary).get("lease_deadline_ms", -1))


func ready(seat: int, session_id: String) -> Dictionary:
	if server == null:
		return _fail(ERR_COMMAND_REJECTED, "room not bootstrapped")
	if _room_failed:
		return _fail(ERR_ROOM_FAILED, _fail_message if not _fail_message.is_empty() else "room failed")
	if seat < 0 or seat > 3 or not is_human_seat(seat):
		return _fail(ERR_UNAUTHORIZED, "invalid seat")
	var st: Dictionary = _seats[seat]
	if not bool(st.get("joined", false)):
		return _fail(ERR_UNAUTHORIZED, "not joined")
	if str(st.get("session_id", "")) != session_id:
		return _fail(ERR_UNAUTHORIZED, "session mismatch")
	st["ready"] = true
	_seats[seat] = st
	var start_err := try_start_if_ready()
	if not start_err.is_empty():
		return _fail(ERR_COMMAND_REJECTED, start_err)
	return _ok()


## 全部 HUMAN 已 JOIN+READY 时启动权威；否则返回 ""。
func try_start_if_ready() -> String:
	if _started:
		return ""
	if _room_failed:
		return "room failed"
	if server == null:
		return "no server"
	for i in range(4):
		if not is_human_seat(i):
			continue
		var st: Dictionary = _seats[i]
		if not bool(st.get("joined", false)) or not bool(st.get("ready", false)):
			return ""
	if not server.start():
		return "start failed"
	_started = true
	return ""


func all_humans_ready() -> bool:
	for i in range(4):
		if not is_human_seat(i):
			continue
		var st: Dictionary = _seats[i]
		if not bool(st.get("ready", false)):
			return false
	return true


func human_seat_count() -> int:
	var n := 0
	for i in range(4):
		if is_human_seat(i):
			n += 1
	return n


## 仅已绑定且当前有效连接的 seat 可提交；强制 action.seat 与绑定一致。
## AI 接管中拒绝真人 Action（须先重连归还）。
## #242：指纹 session_id 使用 JOIN 绑定的客户端 session_id；会话拒绝在可规范化后缓存。
func submit_action_for_seat(bound_seat: int, action: Action) -> CommandResult:
	if action == null:
		return _reject_cmd("", ERR_COMMAND_REJECTED)
	var st: Dictionary = _seats.get(bound_seat, {})
	var bound_session: String = str(st.get("session_id", ""))
	if server == null:
		return _reject_cmd(action.command_id, "NOT_STARTED")
	# 会话层拒绝：Action 已解析时可形成指纹 → 首次结果缓存
	if not _started:
		return server.reject_action_cached(action, bound_session, "NOT_STARTED")
	if int(action.seat) != bound_seat:
		return server.reject_action_cached(action, bound_session, ERR_UNAUTHORIZED)
	if action.room_id != room_id:
		return server.reject_action_cached(action, bound_session, "WRONG_ROOM")
	if is_seat_ai_controlled(bound_seat):
		return server.reject_action_cached(action, bound_session, ERR_UNAUTHORIZED)
	if not bool(st.get("joined", false)):
		return server.reject_action_cached(action, bound_session, ERR_UNAUTHORIZED)
	# Worker 绑定了活动连接时必须仍 connected；无绑定（会话单测直调）放行
	if int(st.get("active_conn_id", -1)) >= 0 and not bool(st.get("connected", false)):
		return server.reject_action_cached(action, bound_session, ERR_UNAUTHORIZED)
	return server.submit_action(action, bound_session)


## #256/#376：权威整场结束（MATCH_SETTLED）。O(1) 读 LocalLoopbackServer 完成标志，不调用 event_journal。
func is_match_completed() -> bool:
	if server == null:
		return false
	return server.has_match_settled()


## #376：失败终态（READY 超时等）；与 match completed 互斥，均不算活跃房间。
func is_terminal() -> bool:
	return is_match_completed() or _room_failed


func events_since(seat: int, after_seq: int) -> Array:
	if server == null:
		return []
	return server.events_since(seat, after_seq)


func event_journal(seat: int) -> Array:
	if server == null:
		return []
	return server.event_journal(seat)


func current_server_seq() -> int:
	if server == null:
		return 0
	return server.current_server_seq()


func _empty_seat_state(kind: String) -> Dictionary:
	return {
		"session_id": "",
		"ready": false,
		"joined": false,
		"kind": kind,
		"connected": false,
		"active_conn_id": -1,
		"conn_generation": 0,
		"lease_deadline_ms": -1,
		"ai_control": false,
	}


func _generate_seed() -> int:
	var c := Crypto.new()
	var b: PackedByteArray = c.generate_random_bytes(8)
	var v: int = 0
	for i in range(mini(8, b.size())):
		v = (v << 8) | int(b[i])
	# 保证正 int64 语义范围
	return v & 0x7fffffffffffffff




func _ok() -> Dictionary:
	return {"ok": true, "code": "", "message": ""}


func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


func _reject_cmd(cmd: String, code: String) -> CommandResult:
	var use_cmd := cmd
	if use_cmd.is_empty() or not ProtocolUuid.is_canonical_v4(use_cmd):
		use_cmd = "00000000-0000-4000-8000-000000000000"
	return CommandResult.from_dict({
		"protocol_version": 1,
		"command_id": use_cmd,
		"status": "REJECTED",
		"server_seq": current_server_seq(),
		"error_code": code,
	})
