class_name NetworkedEvent extends RefCounted

# 麻将王 — E2-02 ServerEvent 扁平业务事件包络（#232）
#
# exact envelope 六键：
# protocol_version / server_seq / room_id / kind / payload / view_hash
#
# view_hash 必需 64 小写 hex；任何层递归拒绝 state_hash / full_state_hash。
# ACTION_APPLIED 是 resolved 权威结果，禁止命令回显。
# TURN_PROMPT / CLAIM_WINDOW 私有 schema 严格校验；ActionOffer 同源 Action.normalize_payload。
#
# ARCH-03 #393：envelope 与 payload codec 分离。本类只负责六键 envelope 构造、
# 序列化与顶层拒绝；按 kind 的 payload 校验由 EventPayloadCodecRegistry 分发到
# 领域 codec（table flow / snapshot / settlement / reward-item / presence）。
# 注册表构造时冻结；未知 kind、ERROR、COMMAND_RESULT 一律拒绝。

const EVENT_KINDS := [
	"ROOM_SNAPSHOT",
	"PLAYER_JOINED",
	"TURN_PROMPT",
	"ACTION_APPLIED",
	"CLAIM_WINDOW",
	"REWARD_WINDOW_OPENED",
	"REWARD_WINDOW_CLOSING",
	"REWARD_WINDOW_SETTLED",
	"REWARD_WINDOW_CANCELLED",
	"ITEM_GRANTED",
	"ITEM_CONSUMED",
	"ITEM_APPLIED",
	"CHARACTER_ABILITY_ARMED",
	"CHARACTER_ABILITY_DISARMED",
	"SKILL_TRIGGERED",
	"HAND_SETTLED",
	"MATCH_SETTLED",
]

const ENVELOPE_KEYS := [
	"protocol_version", "server_seq", "room_id", "kind", "payload", "view_hash",
]

# 结算 payload 键为对外契约（server/session/tests 引用）；事实源在 SettlementPayloadCodec。
const HAND_SETTLED_KEYS := SettlementPayloadCodec.HAND_SETTLED_KEYS
const MATCH_SETTLED_KEYS := SettlementPayloadCodec.MATCH_SETTLED_KEYS

# payload codec 注册表：静态共享，构造即冻结。
static var _payload_codecs := EventPayloadCodecRegistry.new()

# envelope 字段只读：仅 from_dict 写私有存储；外部 set/赋值不得污染。
var _protocol_version: int = ProtocolConstants.PROTOCOL_VERSION
var protocol_version: int:
	get:
		return _protocol_version
var _server_seq: int = 0
var server_seq: int:
	get:
		return _server_seq
var _room_id: String = ""
var room_id: String:
	get:
		return _room_id
var _kind: String = ""
var kind: String:
	get:
		return _kind
var _payload: Dictionary = {}
var payload: Dictionary:
	get:
		return _payload.duplicate(true)
var _view_hash: String = ""
var view_hash: String:
	get:
		return _view_hash

static func make(
	kind_str: String,
	seq: int,
	room: String,
	payload_dict: Dictionary,
	hash_str: String
) -> NetworkedEvent:
	return from_dict({
		"protocol_version": ProtocolConstants.PROTOCOL_VERSION,
		"server_seq": seq,
		"room_id": room,
		"kind": kind_str,
		"payload": payload_dict.duplicate(true),
		"view_hash": hash_str,
	})


# ---- 序列化 ----


func to_dict() -> Dictionary:
	return {
		"protocol_version": _protocol_version,
		"server_seq": _server_seq,
		"room_id": _room_id,
		"kind": _kind,
		"payload": _payload.duplicate(true),
		"view_hash": _view_hash,
	}


static func from_dict(raw: Variant) -> NetworkedEvent:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = raw
	if d.is_empty():
		return null
	if not EventPayloadCodecUtil._has_exact_keys(d, ENVELOPE_KEYS):
		return null

	if typeof(d["protocol_version"]) != TYPE_INT:
		return null
	if int(d["protocol_version"]) != ProtocolConstants.PROTOCOL_VERSION:
		return null

	if typeof(d["server_seq"]) != TYPE_INT:
		return null
	var seq: int = d["server_seq"]
	if seq < 1 or seq > ProtocolConstants.MAX_SAFE_INT:
		return null

	if typeof(d["room_id"]) != TYPE_STRING:
		return null
	var room: String = d["room_id"]
	if room.is_empty() or room != room.strip_edges():
		return null

	if typeof(d["kind"]) != TYPE_STRING:
		return null
	var kind_str: String = d["kind"]
	if kind_str.is_empty() or kind_str == "ERROR" or kind_str == "COMMAND_RESULT":
		return null
	if kind_str not in EVENT_KINDS:
		return null

	if typeof(d["payload"]) != TYPE_DICTIONARY:
		return null
	var raw_payload: Dictionary = d["payload"]

	if typeof(d["view_hash"]) != TYPE_STRING:
		return null
	var vh: String = d["view_hash"]
	if not EventPayloadCodecUtil._is_view_hash(vh):
		return null

	# 任何层递归拒绝私有 hash 键
	if EventPayloadCodecUtil._contains_forbidden_hash_keys(raw_payload):
		return null

	# server_seq 显式传入，供 boundary 与 typed validator 使用
	var validated: Variant = _payload_codecs.validate(kind_str, raw_payload, seq)
	if validated == null:
		return null
	if EventPayloadCodecUtil._contains_forbidden_hash_keys(validated):
		return null

	# 仅 ROOM_SNAPSHOT：envelope.seq==snapshot，且 view_hash==validated payload hash
	# 其它 event 禁止拿自身 payload 对 hash（view_hash 仅校验格式）
	if kind_str == "ROOM_SNAPSHOT":
		var snap_payload: Dictionary = validated as Dictionary
		if int(snap_payload["snapshot_server_seq"]) != seq:
			return null
		var expected_hash: String = ProtocolViewCodec.compute_view_hash(validated)
		if expected_hash.is_empty() or expected_hash != vh:
			return null

	var ne := NetworkedEvent.new()
	ne._protocol_version = ProtocolConstants.PROTOCOL_VERSION
	ne._server_seq = seq
	ne._room_id = room
	ne._kind = kind_str
	ne._payload = (validated as Dictionary).duplicate(true)
	ne._view_hash = vh
	return ne


# ---- payload 按 kind 校验 ----


func describe() -> String:
	return "NetEv[seq=%d kind=%s room=%s]" % [server_seq, kind, room_id]
