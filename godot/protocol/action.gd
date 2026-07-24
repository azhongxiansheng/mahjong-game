class_name Action extends RefCounted

# 麻将王 — E2-02 Action v1 实体 command DTO（client → server）
#
# exact envelope 九键：
# protocol_version / command_id / room_id / seat / hand_seq /
# decision_id / kind / payload / client_seq
#
# 业务 kind 仅 DISCARD..DECLARE_ABORTIVE_DRAW；JOIN/READY/RESYNC 拒绝。
# 无旧 tile_id / is_red_dora fallback；fail-closed。

const BUSINESS_KINDS := [
	"DISCARD", "RIICHI", "CHI", "PON", "KAN", "RON", "TSUMO", "PASS",
	"ITEM_USE", "DECLARE_ABORTIVE_DRAW",
]
const KAN_KINDS := ["MINKAN", "ANKAN", "ADDED_KAN"]
const ABORTIVE_DRAW_REASONS := ["KYUUSYU_KYUUHAI"]
const ENVELOPE_KEYS := [
	"protocol_version", "command_id", "room_id", "seat", "hand_seq",
	"decision_id", "kind", "payload", "client_seq",
]

# envelope 字段只读：仅 from_dict 写私有存储；外部 set/赋值不得污染。
var _protocol_version: int = ProtocolConstants.PROTOCOL_VERSION
var protocol_version: int:
	get:
		return _protocol_version
var _command_id: String = ""
var command_id: String:
	get:
		return _command_id
var _room_id: String = ""
var room_id: String:
	get:
		return _room_id
var _seat: int = -1
var seat: int:
	get:
		return _seat
var _hand_seq: int = 0
var hand_seq: int:
	get:
		return _hand_seq
var _decision_id: String = ""
var decision_id: String:
	get:
		return _decision_id
var _kind: String = ""
var kind: String:
	get:
		return _kind
## 私有存储；公开 payload getter 每次 deep copy（无 setter）
var _payload: Dictionary = {}
var payload: Dictionary:
	get:
		return _payload.duplicate(true)
var _client_seq: int = 0
var client_seq: int:
	get:
		return _client_seq


# ---- 构造 helpers（仅产实体 v1 exact DTO） ----

static func discard(
	seat_id: int,
	tile_instance_id: int,
	room: String,
	cmd_id: String,
	decision: String,
	hand_seq_id: int = 0,
	client_seq_id: int = 0
) -> Action:
	return _make(
		"DISCARD", seat_id, {"tile_instance_id": tile_instance_id},
		room, cmd_id, decision, hand_seq_id, client_seq_id
	)


static func riichi(
	seat_id: int,
	tile_instance_id: int,
	room: String,
	cmd_id: String,
	decision: String,
	hand_seq_id: int = 0,
	client_seq_id: int = 0
) -> Action:
	return _make(
		"RIICHI", seat_id, {"tile_instance_id": tile_instance_id},
		room, cmd_id, decision, hand_seq_id, client_seq_id
	)


static func make_pass(
	seat_id: int,
	room: String,
	cmd_id: String,
	decision: String,
	hand_seq_id: int = 0,
	client_seq_id: int = 0
) -> Action:
	return _make("PASS", seat_id, {}, room, cmd_id, decision, hand_seq_id, client_seq_id)


static func chi(
	seat_id: int,
	companion_tile_instance_ids: Array,
	room: String,
	cmd_id: String,
	decision: String,
	hand_seq_id: int = 0,
	client_seq_id: int = 0
) -> Action:
	return _make(
		"CHI", seat_id,
		{"companion_tile_instance_ids": companion_tile_instance_ids.duplicate()},
		room, cmd_id, decision, hand_seq_id, client_seq_id
	)


static func pon(
	seat_id: int,
	companion_tile_instance_ids: Array,
	room: String,
	cmd_id: String,
	decision: String,
	hand_seq_id: int = 0,
	client_seq_id: int = 0
) -> Action:
	return _make(
		"PON", seat_id,
		{"companion_tile_instance_ids": companion_tile_instance_ids.duplicate()},
		room, cmd_id, decision, hand_seq_id, client_seq_id
	)


static func kan(
	seat_id: int,
	payload_dict: Dictionary,
	room: String,
	cmd_id: String,
	decision: String,
	hand_seq_id: int = 0,
	client_seq_id: int = 0
) -> Action:
	return _make(
		"KAN", seat_id, payload_dict.duplicate(true),
		room, cmd_id, decision, hand_seq_id, client_seq_id
	)


static func ron(
	seat_id: int,
	room: String,
	cmd_id: String,
	decision: String,
	hand_seq_id: int = 0,
	client_seq_id: int = 0
) -> Action:
	return _make("RON", seat_id, {}, room, cmd_id, decision, hand_seq_id, client_seq_id)


static func tsumo(
	seat_id: int,
	room: String,
	cmd_id: String,
	decision: String,
	hand_seq_id: int = 0,
	client_seq_id: int = 0
) -> Action:
	return _make("TSUMO", seat_id, {}, room, cmd_id, decision, hand_seq_id, client_seq_id)


static func item_use(
	seat_id: int,
	item_instance_id: String,
	room: String,
	cmd_id: String,
	decision: String,
	hand_seq_id: int = 0,
	client_seq_id: int = 0
) -> Action:
	return _make(
		"ITEM_USE", seat_id, {"item_instance_id": item_instance_id},
		room, cmd_id, decision, hand_seq_id, client_seq_id
	)


static func declare_abortive_draw(
	seat_id: int,
	reason: String,
	room: String,
	cmd_id: String,
	decision: String,
	hand_seq_id: int = 0,
	client_seq_id: int = 0
) -> Action:
	return _make(
		"DECLARE_ABORTIVE_DRAW", seat_id, {"reason": reason},
		room, cmd_id, decision, hand_seq_id, client_seq_id
	)


static func _make(
	kind_str: String,
	seat_id: int,
	payload_dict: Dictionary,
	room: String,
	cmd_id: String,
	decision: String,
	hand_seq_id: int,
	client_seq_id: int
) -> Action:
	# typed helper 已固定 envelope 字段类型；直接执行与 from_dict 相同的值域校验，
	# 避免本地 AI 每个动作先组九键 Dictionary、再完整解析一次。
	if kind_str not in BUSINESS_KINDS:
		return null
	if seat_id < 0 or seat_id > 3:
		return null
	if room.is_empty() or room != room.strip_edges():
		return null
	if not ProtocolUuid.is_canonical_v4(cmd_id):
		return null
	if not ProtocolUuid.is_canonical_v4(decision):
		return null
	if hand_seq_id < 0 or hand_seq_id > ProtocolConstants.MAX_HAND_SEQ:
		return null
	if client_seq_id < 0 or client_seq_id > ProtocolConstants.MAX_SAFE_INT:
		return null
	var validated: Variant = normalize_payload(kind_str, payload_dict)
	if validated == null:
		return null
	if not _payload_entities_in_hand_namespace(
		kind_str, validated as Dictionary, hand_seq_id
	):
		return null
	var action := Action.new()
	action._protocol_version = ProtocolConstants.PROTOCOL_VERSION
	action._command_id = cmd_id
	action._room_id = room
	action._seat = seat_id
	action._hand_seq = hand_seq_id
	action._decision_id = decision
	action._kind = kind_str
	action._payload = (validated as Dictionary).duplicate(true)
	action._client_seq = client_seq_id
	return action


# ---- 序列化 ----

func to_dict() -> Dictionary:
	return {
		"protocol_version": _protocol_version,
		"command_id": _command_id,
		"room_id": _room_id,
		"seat": _seat,
		"hand_seq": _hand_seq,
		"decision_id": _decision_id,
		"kind": _kind,
		"payload": _payload.duplicate(true),
		"client_seq": _client_seq,
	}


static func from_dict(raw: Variant) -> Action:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = raw
	if d.is_empty():
		return null
	if not _has_exact_keys(d, ENVELOPE_KEYS):
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

	if typeof(d["room_id"]) != TYPE_STRING:
		return null
	var room: String = d["room_id"]
	if room.is_empty() or room != room.strip_edges():
		return null

	if typeof(d["seat"]) != TYPE_INT:
		return null
	var seat_id: int = d["seat"]
	if seat_id < 0 or seat_id > 3:
		return null

	if typeof(d["hand_seq"]) != TYPE_INT:
		return null
	var hs: int = d["hand_seq"]
	if hs < 0 or hs > ProtocolConstants.MAX_HAND_SEQ:
		return null

	if typeof(d["decision_id"]) != TYPE_STRING:
		return null
	var dec: String = d["decision_id"]
	if not ProtocolUuid.is_canonical_v4(dec):
		return null

	if typeof(d["kind"]) != TYPE_STRING:
		return null
	var kind_str: String = d["kind"]
	if kind_str not in BUSINESS_KINDS:
		return null

	if typeof(d["payload"]) != TYPE_DICTIONARY:
		return null

	if typeof(d["client_seq"]) != TYPE_INT:
		return null
	var seq: int = d["client_seq"]
	if seq < 0 or seq > ProtocolConstants.MAX_SAFE_INT:
		return null

	var validated: Variant = normalize_payload(kind_str, d["payload"])
	if validated == null:
		return null
	# 实体牌 id 必须落在 envelope.hand_seq 的 136 命名空间；meld_id 不受此限
	if not _payload_entities_in_hand_namespace(kind_str, validated as Dictionary, hs):
		return null

	var a := Action.new()
	a._protocol_version = ProtocolConstants.PROTOCOL_VERSION
	a._command_id = cmd
	a._room_id = room
	a._seat = seat_id
	a._hand_seq = hs
	a._decision_id = dec
	a._kind = kind_str
	a._payload = (validated as Dictionary).duplicate(true)
	a._client_seq = seq
	return a


## 公开可复用 payload normalizer/validator（ActionOffer 同源）。
## 成功 → 规范化后的 deep-copied Dictionary；失败 → null。
## 不构造伪 envelope，不走 from_dict roundtrip。
static func normalize_payload(kind_str: String, raw: Dictionary) -> Variant:
	if kind_str not in BUSINESS_KINDS:
		return null
	return _validate_payload(kind_str, raw)


# ---- payload 精确 schema ----

static func _validate_payload(kind_str: String, p: Dictionary) -> Variant:
	match kind_str:
		"DISCARD", "RIICHI":
			if not _has_exact_keys(p, ["tile_instance_id"]):
				return null
			var iid: Variant = _require_safe_int(p["tile_instance_id"])
			if iid == null:
				return null
			return {"tile_instance_id": iid}
		"CHI", "PON":
			if not _has_exact_keys(p, ["companion_tile_instance_ids"]):
				return null
			var companions: Variant = _normalize_unique_sorted_ids(
				p["companion_tile_instance_ids"], 2
			)
			if companions == null:
				return null
			return {"companion_tile_instance_ids": companions}
		"KAN":
			return _validate_kan_payload(p)
		"RON", "TSUMO", "PASS":
			if not p.is_empty():
				return null
			return {}
		"ITEM_USE":
			if not _has_exact_keys(p, ["item_instance_id"]):
				return null
			if typeof(p["item_instance_id"]) != TYPE_STRING:
				return null
			var item_id: String = p["item_instance_id"]
			if item_id.is_empty() or item_id != item_id.strip_edges():
				return null
			return {"item_instance_id": item_id}
		"DECLARE_ABORTIVE_DRAW":
			if not _has_exact_keys(p, ["reason"]):
				return null
			if typeof(p["reason"]) != TYPE_STRING:
				return null
			var reason: String = p["reason"]
			if reason not in ABORTIVE_DRAW_REASONS:
				return null
			return {"reason": reason}
		_:
			return null


static func _validate_kan_payload(p: Dictionary) -> Variant:
	if not p.has("kan_kind") or typeof(p["kan_kind"]) != TYPE_STRING:
		return null
	var kk: String = p["kan_kind"]
	if kk not in KAN_KINDS:
		return null
	match kk:
		"MINKAN":
			if not _has_exact_keys(p, ["kan_kind", "companion_tile_instance_ids"]):
				return null
			var companions: Variant = _normalize_unique_sorted_ids(
				p["companion_tile_instance_ids"], 3
			)
			if companions == null:
				return null
			return {
				"kan_kind": "MINKAN",
				"companion_tile_instance_ids": companions,
			}
		"ANKAN":
			if not _has_exact_keys(p, ["kan_kind", "tile_instance_ids"]):
				return null
			var ids: Variant = _normalize_unique_sorted_ids(p["tile_instance_ids"], 4)
			if ids == null:
				return null
			return {
				"kan_kind": "ANKAN",
				"tile_instance_ids": ids,
			}
		"ADDED_KAN":
			if not _has_exact_keys(p, ["kan_kind", "meld_id", "added_tile_instance_id"]):
				return null
			var meld_id: Variant = _require_safe_int(p["meld_id"])
			if meld_id == null:
				return null
			var added: Variant = _require_safe_int(p["added_tile_instance_id"])
			if added == null:
				return null
			return {
				"kan_kind": "ADDED_KAN",
				"meld_id": meld_id,
				"added_tile_instance_id": added,
			}
		_:
			return null


static func _normalize_unique_sorted_ids(raw: Variant, expected_len: int) -> Variant:
	if typeof(raw) != TYPE_ARRAY:
		return null
	var arr: Array = raw
	if arr.size() != expected_len:
		return null
	var ids: Array = []
	var seen: Dictionary = {}
	for v in arr:
		var n: Variant = _require_safe_int(v)
		if n == null:
			return null
		var i: int = n
		if seen.has(i):
			return null
		seen[i] = true
		ids.append(i)
	ids.sort()
	return ids


static func _require_safe_int(v: Variant) -> Variant:
	if typeof(v) != TYPE_INT:
		return null
	var n: int = v
	if n < 0 or n > ProtocolConstants.MAX_SAFE_INT:
		return null
	return n


## instance_id ∈ [hand_seq*TILES_PER_HAND, hand_seq*TILES_PER_HAND+135]
static func _is_instance_id_in_hand_namespace(instance_id: int, hand_seq_id: int) -> bool:
	var base: int = hand_seq_id * ProtocolConstants.TILES_PER_HAND
	return (
		instance_id >= base
		and instance_id <= base + (ProtocolConstants.TILES_PER_HAND - 1)
	)


## 仅校验实体牌字段；meld_id 不参与 hand_seq 命名空间。
static func _payload_entities_in_hand_namespace(
	kind_str: String,
	payload_dict: Dictionary,
	hand_seq_id: int
) -> bool:
	match kind_str:
		"DISCARD", "RIICHI":
			return _is_instance_id_in_hand_namespace(
				int(payload_dict["tile_instance_id"]), hand_seq_id
			)
		"CHI", "PON":
			for cid in payload_dict["companion_tile_instance_ids"]:
				if not _is_instance_id_in_hand_namespace(int(cid), hand_seq_id):
					return false
			return true
		"KAN":
			var kk: String = str(payload_dict.get("kan_kind", ""))
			match kk:
				"MINKAN":
					for cid in payload_dict["companion_tile_instance_ids"]:
						if not _is_instance_id_in_hand_namespace(int(cid), hand_seq_id):
							return false
					return true
				"ANKAN":
					for tid in payload_dict["tile_instance_ids"]:
						if not _is_instance_id_in_hand_namespace(int(tid), hand_seq_id):
							return false
					return true
				"ADDED_KAN":
					# meld_id 是副露序号，不校验 136 域
					return _is_instance_id_in_hand_namespace(
						int(payload_dict["added_tile_instance_id"]), hand_seq_id
					)
				_:
					return false
		_:
			return true


static func _has_exact_keys(d: Dictionary, expected: Array) -> bool:
	if d.keys().size() != expected.size():
		return false
	for k in expected:
		if not d.has(k):
			return false
	return true


func describe() -> String:
	return "Action[%s seat=%d hand=%d room=%s cmd=%s decision=%s payload=%s seq=%d]" % [
		_kind, _seat, _hand_seq, _room_id, _command_id, _decision_id, _payload, _client_seq,
	]
