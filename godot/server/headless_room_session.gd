class_name HeadlessRoomSession
extends RefCounted

# #240：单房间权威会话。惰性建房后持有 LocalLoopbackServer；
# 全部 HUMAN READY 才 start。客户端不得注入 seed/牌墙/结果。
# 网络端到端未验证。

const RULE_VERSION := "riichi-v1"
const ERR_UNAUTHORIZED := "UNAUTHORIZED"
const ERR_COMMAND_REJECTED := "COMMAND_REJECTED"
const ERR_FORGERY_REJECTED := "FORGERY_REJECTED"
const ERR_NOT_READY := "COMMAND_REJECTED"
const ERR_PROTOCOL := "PROTOCOL_VERSION_UNSUPPORTED"

var room_id: String = ""
var round_kind: String = ""
var game_mode: String = ""
var participants: Array = []  # wire HUMAN/AI ×4
var authority_seed: int = 0
var character_ids: Array = []
var config: GameSessionConfig = null
var server: LocalLoopbackServer = null

# seat -> { "session_id": String, "ready": bool, "joined": bool }
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
		_seats[i] = {
			"session_id": "",
			"ready": false,
			"joined": false,
			"kind": String(participants[i]),
		}
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


## JOIN 绑定。返回 { "ok": bool, "code": String, "message": String }
func join(seat: int, session_id: String) -> Dictionary:
	if server == null:
		return _fail(ERR_COMMAND_REJECTED, "room not bootstrapped")
	if seat < 0 or seat > 3:
		return _fail(ERR_UNAUTHORIZED, "invalid seat")
	if not is_human_seat(seat):
		return _fail(ERR_UNAUTHORIZED, "AI seat cannot join")
	if session_id.is_empty():
		return _fail(ERR_UNAUTHORIZED, "missing session")
	var st: Dictionary = _seats[seat]
	if bool(st.get("joined", false)):
		# 同 session 幂等；不同 session 拒绝（#241 才做重连 lease）
		if str(st.get("session_id", "")) == session_id:
			return _ok()
		return _fail(ERR_UNAUTHORIZED, "seat occupied")
	st["joined"] = true
	st["session_id"] = session_id
	st["ready"] = false
	_seats[seat] = st
	return _ok()


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


## 仅已绑定 seat 可提交；强制 action.seat 与绑定一致。
func submit_action_for_seat(bound_seat: int, action: Action) -> CommandResult:
	if action == null:
		return _reject_cmd("", ERR_COMMAND_REJECTED)
	if not _started or server == null:
		return _reject_cmd(action.command_id, "NOT_STARTED")
	if int(action.seat) != bound_seat:
		return _reject_cmd(action.command_id, ERR_UNAUTHORIZED)
	if action.room_id != room_id:
		return _reject_cmd(action.command_id, "WRONG_ROOM")
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
