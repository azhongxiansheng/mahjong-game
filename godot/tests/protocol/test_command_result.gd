extends GutTest

# E2-02（#232）Red：CommandResult 新 class 契约。
# 与 ACTION_APPLIED 不互相替代：命令受理回执 vs 权威已解析结果事件。
# 生产路径：res://protocol/command_result.gd（class_name CommandResult）

const CR_PATH := "res://protocol/command_result.gd"
const CommandResultScript := preload("res://protocol/command_result.gd")

const CMD := "550e8400-e29b-41d4-a716-446655440000"
const MAX_SAFE_INT := 9007199254740991
# CommandResult 独立五键；非 NetworkedEvent，也不在 EVENT_KINDS 内
const RESULT_KEYS := [
	"protocol_version", "command_id", "status", "server_seq", "error_code",
]
# 语义契约（Protocol 只校验字段，不能凭 DTO 推导关系）：
# - REJECTED.server_seq = 当前已见业务序号（不分配新序号）
# - ACCEPTED.server_seq = 最后一条业务事件序号


func _exact_keys(d: Dictionary, expected: Array) -> bool:
	if d.keys().size() != expected.size():
		return false
	for k in expected:
		if not d.has(k):
			return false
	return true


func _accepted(server_seq: int = 1) -> Dictionary:
	return {
		"protocol_version": 1,
		"command_id": CMD,
		"status": "ACCEPTED",
		"server_seq": server_seq,
		"error_code": "",
	}


func _rejected(server_seq: int = 0, error_code: String = "COMMAND_REJECTED") -> Dictionary:
	return {
		"protocol_version": 1,
		"command_id": CMD,
		"status": "REJECTED",
		"server_seq": server_seq,
		"error_code": error_code,
	}


func test_command_result_production_path_locked() -> void:
	assert_eq(CR_PATH, "res://protocol/command_result.gd")
	assert_true(ResourceLoader.exists(CR_PATH), "缺失生产契约: %s" % CR_PATH)


func test_accepted_exact_keys_and_empty_error_code() -> void:
	var cr: Variant = CommandResultScript.from_dict(_accepted(7))
	assert_not_null(cr, "ACCEPTED 应解析")
	if cr == null:
		return
	var out: Dictionary = cr.to_dict()
	assert_true(_exact_keys(out, RESULT_KEYS), "CommandResult exact 五键")
	assert_eq(out.keys().size(), 5, "独立五键，无额外 envelope 字段")
	assert_eq(typeof(out["protocol_version"]), TYPE_INT)
	assert_eq(int(out["protocol_version"]), 1)
	assert_eq(typeof(out["command_id"]), TYPE_STRING)
	assert_eq(str(out["command_id"]), CMD)
	assert_eq(typeof(out["status"]), TYPE_STRING)
	assert_eq(str(out["status"]), "ACCEPTED")
	assert_eq(typeof(out["server_seq"]), TYPE_INT)
	assert_eq(int(out["server_seq"]), 7)
	# 语义：ACCEPTED.server_seq 表示最后业务事件序号，必须 >= 1
	assert_true(int(out["server_seq"]) >= 1 and int(out["server_seq"]) <= MAX_SAFE_INT)
	assert_eq(typeof(out["error_code"]), TYPE_STRING)
	assert_eq(str(out["error_code"]), "", "ACCEPTED error_code 必须空串")


func test_rejected_requires_nonempty_error_code() -> void:
	var cr: Variant = CommandResultScript.from_dict(_rejected(0, "ILLEGAL_ACTION"))
	assert_not_null(cr, "REJECTED 应解析")
	if cr == null:
		return
	var out: Dictionary = cr.to_dict()
	assert_true(_exact_keys(out, RESULT_KEYS))
	assert_eq(str(out["status"]), "REJECTED")
	assert_eq(str(out["error_code"]), "ILLEGAL_ACTION")
	assert_true(str(out["error_code"]).length() > 0)
	# 语义：REJECTED.server_seq 是当前已见值，不分配新序号（Protocol 只校验字段）
	assert_eq(int(out["server_seq"]), 0)
	assert_true(int(out["server_seq"]) >= 0 and int(out["server_seq"]) <= MAX_SAFE_INT)

	assert_null(CommandResultScript.from_dict({
		"protocol_version": 1,
		"command_id": CMD,
		"status": "REJECTED",
		"server_seq": 0,
		"error_code": "",
	}), "REJECTED error_code 不得空")


func test_accepted_rejects_nonempty_error_code() -> void:
	assert_null(CommandResultScript.from_dict({
		"protocol_version": 1,
		"command_id": CMD,
		"status": "ACCEPTED",
		"server_seq": 1,
		"error_code": "SHOULD_BE_EMPTY",
	}), "ACCEPTED 不得带非空 error_code")


func test_status_enum_only_accepted_or_rejected() -> void:
	assert_null(CommandResultScript.from_dict({
		"protocol_version": 1,
		"command_id": CMD,
		"status": "PENDING",
		"server_seq": 0,
		"error_code": "",
	}), "未知 status 拒绝")
	assert_null(CommandResultScript.from_dict({
		"protocol_version": 1,
		"command_id": CMD,
		"status": "accepted",
		"server_seq": 0,
		"error_code": "",
	}), "status 大小写敏感")
	assert_null(CommandResultScript.from_dict({
		"protocol_version": 1,
		"command_id": CMD,
		"status": 1,
		"server_seq": 0,
		"error_code": "",
	}), "status 非 String 拒绝")


func test_rejects_missing_extra_wrong_types_and_uuid() -> void:
	var full := _accepted()
	for key in RESULT_KEYS:
		var bad := full.duplicate(true)
		bad.erase(key)
		assert_null(CommandResultScript.from_dict(bad), "缺 %s 拒绝" % key)

	var extra := full.duplicate(true)
	extra["payload"] = {}
	assert_null(CommandResultScript.from_dict(extra), "多余键拒绝")

	var bad_pv := full.duplicate(true)
	bad_pv["protocol_version"] = "1"
	assert_null(CommandResultScript.from_dict(bad_pv), "protocol_version 不得 str 强转")

	var bad_seq := full.duplicate(true)
	bad_seq["server_seq"] = -1
	assert_null(CommandResultScript.from_dict(bad_seq), "server_seq 负数拒绝")

	assert_null(CommandResultScript.from_dict(_accepted(0)), "ACCEPTED.server_seq=0 拒绝")
	assert_not_null(
		CommandResultScript.from_dict(_rejected(0)),
		"REJECTED.server_seq=0 合法（已见值可为 0）"
	)
	assert_not_null(
		CommandResultScript.from_dict(_accepted(MAX_SAFE_INT)),
		"ACCEPTED.server_seq=MAX_SAFE 合法"
	)
	assert_null(CommandResultScript.from_dict({
		"protocol_version": 1,
		"command_id": CMD,
		"status": "ACCEPTED",
		"server_seq": MAX_SAFE_INT + 1,
		"error_code": "",
	}), "server_seq=MAX_SAFE+1 拒绝")

	var bad_seq_f := full.duplicate(true)
	bad_seq_f["server_seq"] = 1.5
	assert_null(CommandResultScript.from_dict(bad_seq_f), "server_seq float 拒绝")

	var bad_seq_str := full.duplicate(true)
	bad_seq_str["server_seq"] = "1"
	assert_null(CommandResultScript.from_dict(bad_seq_str), "server_seq 不得 str 强转")

	var bad_cmd := full.duplicate(true)
	bad_cmd["command_id"] = "not-a-uuid"
	assert_null(CommandResultScript.from_dict(bad_cmd), "command_id 非 UUID 拒绝")
	for bad_id in [
		"550e8400e29b41d4a716446655440000",
		"550e8400-e29b-41d4-a716",
		"gggggggg-e29b-41d4-a716-446655440000",
		"550e8400-e29b-11d4-a716-446655440000", # version≠4
		"550e8400-e29b-41d4-7716-446655440000", # variant 7xxx
		"550e8400-e29b-41d4-c716-446655440000", # variant cxxx
	]:
		var mid := full.duplicate(true)
		mid["command_id"] = bad_id
		assert_null(CommandResultScript.from_dict(mid), "malformed UUID 拒绝: %s" % bad_id)

	# canonical lowercase only：大写 / 混大小写 command_id 拒绝，防幂等绕过
	var upper_cmd := "550E8400-E29B-41D4-A716-446655440000"
	var upper_wire := _accepted(2)
	upper_wire["command_id"] = upper_cmd
	assert_null(CommandResultScript.from_dict(upper_wire), "大写 command_id 必须拒绝")

	var mixed_wire := _accepted(2)
	mixed_wire["command_id"] = "550e8400-E29b-41d4-a716-446655440000"
	assert_null(CommandResultScript.from_dict(mixed_wire), "混大小写 command_id 必须拒绝")

	# 正例：lowercase v4+variant 合法且 to_dict 保持 lowercase
	var lower_ok: Variant = CommandResultScript.from_dict(_accepted(2))
	assert_not_null(lower_ok, "lowercase command_id 合法")
	if lower_ok != null:
		assert_eq(str(lower_ok.to_dict()["command_id"]), CMD)
		assert_eq(str(lower_ok.to_dict()["command_id"]), CMD.to_lower())

	var bad_err_type := _rejected()
	bad_err_type["error_code"] = 404
	assert_null(CommandResultScript.from_dict(bad_err_type), "error_code 必须 String")

	assert_null(CommandResultScript.from_dict({}), "空 dict 拒绝")


func test_roundtrip_and_deep_copy() -> void:
	var src := _rejected(3, "OUT_OF_TURN")
	var cr: Variant = CommandResultScript.from_dict(src)
	assert_not_null(cr)
	if cr == null:
		return
	src["error_code"] = "MUTATED"
	src["server_seq"] = 99
	var out: Dictionary = cr.to_dict()
	assert_eq(str(out["error_code"]), "OUT_OF_TURN")
	assert_eq(int(out["server_seq"]), 3)

	out["error_code"] = "X"
	var out2: Dictionary = cr.to_dict()
	assert_eq(str(out2["error_code"]), "OUT_OF_TURN", "to_dict deep copy")

	var again: Variant = CommandResultScript.from_dict(out2)
	assert_not_null(again)
	if again != null:
		var r2: Dictionary = again.to_dict()
		assert_true(_exact_keys(r2, RESULT_KEYS))
		assert_eq(str(r2["status"]), "REJECTED")
		assert_eq(str(r2["error_code"]), "OUT_OF_TURN")


func test_command_result_is_not_action_applied_substitute() -> void:
	# CommandResult 不是事件：不得被 NetworkedEvent 当 ACTION_APPLIED 消费
	var cr_wire := _accepted(5)
	assert_null(
		NetworkedEvent.from_dict(cr_wire),
		"CommandResult wire 不得作为 NetworkedEvent"
	)

	# ACTION_APPLIED 也不得被当成 CommandResult
	var event_shaped := {
		"protocol_version": 1,
		"server_seq": 5,
		"room_id": "room_x",
		"kind": "ACTION_APPLIED",
		"payload": {},
		"view_hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
	}
	assert_null(
		CommandResultScript.from_dict(event_shaped),
		"ACTION_APPLIED envelope 不得 from_dict 为 CommandResult"
	)

	# 两者 exact keys 集合不同
	assert_false(_exact_keys(cr_wire, [
		"protocol_version", "server_seq", "room_id", "kind", "payload", "view_hash",
	]))

	# NetworkedEvent.EVENT_KINDS 不含 ERROR / COMMAND_RESULT
	assert_true(NetworkedEvent.EVENT_KINDS is Array or typeof(NetworkedEvent.EVENT_KINDS) == TYPE_ARRAY)
	assert_false(
		"ERROR" in NetworkedEvent.EVENT_KINDS,
		"EVENT_KINDS 不得含 ERROR"
	)
	assert_false(
		"COMMAND_RESULT" in NetworkedEvent.EVENT_KINDS,
		"EVENT_KINDS 不得含 COMMAND_RESULT（CommandResult 独立五键）"
	)


# ---- P2：envelope 只读 + from_dict(Variant) ----

func _from_dict_first_arg_type(script_path: String) -> int:
	var script: GDScript = load(script_path) as GDScript
	if script == null:
		return -1
	for m in script.get_script_method_list():
		if str(m.get("name", "")) != "from_dict":
			continue
		var args: Array = m.get("args", [])
		if args.is_empty():
			return -1
		var a0: Variant = args[0]
		if typeof(a0) != TYPE_DICTIONARY:
			return -1
		return int((a0 as Dictionary).get("type", -1))
	return -1


func test_command_result_envelope_fields_reject_mutation() -> void:
	# 只读：反射冻结 @字段_getter 存在且 @字段_setter 不存在（Godot 4.6 命名）
	# 禁止 Object.set / 直接赋值攻击（生产缺 setter 时会 runtime error）
	var cr: CommandResult = CommandResultScript.from_dict(_rejected(3, "OUT_OF_TURN"))
	assert_not_null(cr, "合法 REJECTED 应解析")
	if cr == null:
		return
	var before: Dictionary = cr.to_dict().duplicate(true)

	var script: GDScript = load(CR_PATH) as GDScript
	assert_not_null(script, "CommandResult 脚本必须可加载")
	var method_names: Dictionary = {}
	for m in script.get_script_method_list():
		method_names[str(m.get("name", ""))] = true

	var fields: Array = [
		"protocol_version", "command_id", "status", "server_seq", "error_code",
	]
	for field in fields:
		var gname: String = "@%s_getter" % field
		var sname: String = "@%s_setter" % field
		assert_true(method_names.has(gname), "必须存在只读 getter %s" % gname)
		assert_false(method_names.has(sname), "不得存在 setter %s" % sname)

	var after: Dictionary = cr.to_dict()
	assert_eq(int(after["protocol_version"]), int(before["protocol_version"]))
	assert_eq(str(after["command_id"]), str(before["command_id"]))
	assert_eq(str(after["status"]), str(before["status"]))
	assert_eq(int(after["server_seq"]), int(before["server_seq"]))
	assert_eq(str(after["error_code"]), str(before["error_code"]))
	assert_true(_exact_keys(after, RESULT_KEYS))


func test_command_result_from_dict_arg_is_variant() -> void:
	var arg_type: int = _from_dict_first_arg_type(CR_PATH)
	assert_eq(
		arg_type, TYPE_NIL,
		"CommandResultScript.from_dict 公开参数必须是 Variant（反射 type=TYPE_NIL）；当前=%d" % arg_type
	)


func test_command_result_from_dict_rejects_non_dictionary_matrix() -> void:
	var arg_type: int = _from_dict_first_arg_type(CR_PATH)
	assert_eq(
		arg_type, TYPE_NIL,
		"签名未切到 Variant 前不动态调用非 Dictionary（Red：先修签名）"
	)
	if arg_type != TYPE_NIL:
		return
	var script: GDScript = load(CR_PATH) as GDScript
	assert_not_null(script)
	var samples: Array = [null, false, true, 0, 1.0, [], "not_dict", RefCounted.new()]
	for sample in samples:
		var ret: Variant = script.call("from_dict", sample)
		assert_null(ret, "非 Dictionary 必须返回 null 且不抛: typeof=%d" % typeof(sample))
