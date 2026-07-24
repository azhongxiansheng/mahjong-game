class_name CommandResult extends RefCounted

# E2-02（#232）CommandResult：命令受理回执（非 EventKind，不进 replay）。
# exact 五键：protocol_version / command_id / status / server_seq / error_code

const RESULT_KEYS := [
	"protocol_version", "command_id", "status", "server_seq", "error_code",
]

# 五键只读：仅 from_dict 写私有存储；外部 set/赋值不得污染。
var _protocol_version: int = ProtocolConstants.PROTOCOL_VERSION
var protocol_version: int:
	get:
		return _protocol_version
var _command_id: String = ""
var command_id: String:
	get:
		return _command_id
var _status: String = ""
var status: String:
	get:
		return _status
var _server_seq: int = 0
var server_seq: int:
	get:
		return _server_seq
var _error_code: String = ""
var error_code: String:
	get:
		return _error_code


func to_dict() -> Dictionary:
	return {
		"protocol_version": _protocol_version,
		"command_id": _command_id,
		"status": _status,
		"server_seq": _server_seq,
		"error_code": _error_code,
	}


static func from_dict(raw: Variant) -> CommandResult:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = raw
	if d.is_empty():
		return null
	if not _has_exact_keys(d, RESULT_KEYS):
		return null

	if typeof(d["protocol_version"]) != TYPE_INT:
		return null
	if int(d["protocol_version"]) != ProtocolConstants.PROTOCOL_VERSION:
		return null

	if typeof(d["command_id"]) != TYPE_STRING:
		return null
	var cmd: String = d["command_id"]
	if not ProtocolUuid.is_canonical_v4(cmd):
		return null

	if typeof(d["status"]) != TYPE_STRING:
		return null
	var st: String = d["status"]
	if st != "ACCEPTED" and st != "REJECTED":
		return null

	if typeof(d["server_seq"]) != TYPE_INT:
		return null
	var seq: int = d["server_seq"]
	if seq < 0 or seq > ProtocolConstants.MAX_SAFE_INT:
		return null
	# ACCEPTED：server_seq 为最后业务事件序号，必须 >= 1；REJECTED 可为已见 0
	if st == "ACCEPTED" and seq < 1:
		return null

	if typeof(d["error_code"]) != TYPE_STRING:
		return null
	var err: String = d["error_code"]
	if st == "ACCEPTED":
		if err != "":
			return null
	else:
		if err.is_empty():
			return null

	var cr := CommandResult.new()
	cr._protocol_version = ProtocolConstants.PROTOCOL_VERSION
	cr._command_id = cmd
	cr._status = st
	cr._server_seq = seq
	cr._error_code = err
	return cr


static func _has_exact_keys(d: Dictionary, expected: Array) -> bool:
	if d.keys().size() != expected.size():
		return false
	for k in expected:
		if not d.has(k):
			return false
	return true
