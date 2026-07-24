class_name HeadlessRoomSession
extends RefCounted

# #240：单房间权威会话。惰性建房后持有 LocalLoopbackServer；
# 全部 HUMAN READY 才 start。客户端不得注入 seed/牌墙/结果。
# #241：座位连接代际、30s lease、AI 接管/归还。
# 网络端到端未验证。

const RULE_VERSION := "riichi-v1"
const ERR_UNAUTHORIZED := "UNAUTHORIZED"
const ERR_COMMAND_REJECTED := "COMMAND_REJECTED"
const ERR_FORGERY_REJECTED := "FORGERY_REJECTED"
const ERR_NOT_READY := "COMMAND_REJECTED"
const ERR_PROTOCOL := "PROTOCOL_VERSION_UNSUPPORTED"
## #241：掉线后保留座位的宽限（毫秒）
const RECONNECT_LEASE_MS := 30000

var room_id: String = ""
var round_kind: String = ""
var game_mode: String = ""
var participants: Array = []  # wire HUMAN/AI ×4
var authority_seed: int = 0
var character_ids: Array = []
var config: GameSessionConfig = null
var server: LocalLoopbackServer = null

# seat -> seat state dict
var _seats: Dictionary = {}
var _started: bool = false
var _seed_override: int = -1  # 测试注入；生产用 Crypto


func _init() -> void:
	pass


## 首个合法 JOIN 时调用。claims 来自已验签 room_token。
func bootstrap_from_claims(claims: Dictionary) -> bool:
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
	if _seed_override >= 0:
		authority_seed = _seed_override
	else:
		authority_seed = _generate_seed()
	character_ids = _pick_characters(authority_seed)
	if character_ids.size() != 4:
		return false
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
	server = LocalLoopbackServer.new(config, 0)
	if server == null or server._bc == null:
		server = null
		return false
	_seats.clear()
	for i in range(4):
		_seats[i] = _empty_seat_state(String(participants[i]))
	_started = false
	return true


func set_seed_override_for_test(p_seed: int) -> void:
	_seed_override = p_seed


func is_bootstrapped() -> bool:
	return server != null


func is_started() -> bool:
	return _started


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
func submit_action_for_seat(bound_seat: int, action: Action) -> CommandResult:
	if action == null:
		return _reject_cmd("", ERR_COMMAND_REJECTED)
	if not _started or server == null:
		return _reject_cmd(action.command_id, "NOT_STARTED")
	if int(action.seat) != bound_seat:
		return _reject_cmd(action.command_id, ERR_UNAUTHORIZED)
	if action.room_id != room_id:
		return _reject_cmd(action.command_id, "WRONG_ROOM")
	if is_seat_ai_controlled(bound_seat):
		return _reject_cmd(action.command_id, ERR_UNAUTHORIZED)
	var st: Dictionary = _seats.get(bound_seat, {})
	if not bool(st.get("joined", false)):
		return _reject_cmd(action.command_id, ERR_UNAUTHORIZED)
	# Worker 绑定了活动连接时必须仍 connected；无绑定（会话单测直调）放行
	if int(st.get("active_conn_id", -1)) >= 0 and not bool(st.get("connected", false)):
		return _reject_cmd(action.command_id, ERR_UNAUTHORIZED)
	return server.submit_action(action)


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


func _pick_characters(p_seed: int) -> Array:
	var pool: Array = []
	for c in CharacterPool.all():
		pool.append(c.id)
	pool.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	var state: int = p_seed & 0xffffffff
	for i in range(pool.size() - 1, 0, -1):
		state = GameSessionConfig._lcrng_next(state)
		var j: int = state % (i + 1)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var out: Array = []
	for i in range(mini(4, pool.size())):
		out.append(pool[i])
	return out


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
