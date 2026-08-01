class_name EventPayloadCodecUtil extends RefCounted

# ARCH-03 #393：payload codec 共享校验原语（exact keys、安全整数、view hash、
# 私有 hash 键递归拒绝、hand 命名空间实体检查）。语义与拆分前 NetworkedEvent 一致。

const FORBIDDEN_HASH_KEYS := ["snapshot_hash", "state_hash", "full_state_hash"]

const _VIEW_HASH_RE := "^[0-9a-f]{64}$"


static func _has_exact_keys(d: Dictionary, expected: Array) -> bool:
	if d.keys().size() != expected.size():
		return false
	for k in expected:
		if not d.has(k):
			return false
	return true


static func _is_nonempty_string(v: Variant) -> bool:
	if typeof(v) != TYPE_STRING:
		return false
	var s: String = v
	return not s.is_empty() and s == s.strip_edges()


static func _validate_opaque_json_dict(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY:
		return null
	if ProtocolViewCodec.compute_view_hash(raw).is_empty():
		return null
	return _deep_copy_json_safe(raw)


static func _is_view_hash(s: String) -> bool:
	if s.length() != 64:
		return false
	if s != s.to_lower():
		return false
	var re := RegEx.new()
	if re.compile(_VIEW_HASH_RE) != OK:
		return false
	return re.search(s) != null


static func _require_safe_int(v: Variant) -> Variant:
	if typeof(v) != TYPE_INT:
		return null
	var n: int = v
	if n < -ProtocolConstants.MAX_SAFE_INT or n > ProtocolConstants.MAX_SAFE_INT:
		return null
	return n


static func _require_nonneg_safe_int(v: Variant) -> Variant:
	if typeof(v) != TYPE_INT:
		return null
	var n: int = v
	if n < 0 or n > ProtocolConstants.MAX_SAFE_INT:
		return null
	return n


static func _require_positive_safe_int(v: Variant) -> Variant:
	var n: Variant = _require_nonneg_safe_int(v)
	if n == null or int(n) < 1:
		return null
	return n


static func _require_hand_seq(v: Variant) -> Variant:
	var n: Variant = _require_nonneg_safe_int(v)
	if n == null or int(n) > ProtocolConstants.MAX_HAND_SEQ:
		return null
	return n


static func _require_seat(v: Variant) -> Variant:
	if typeof(v) != TYPE_INT:
		return null
	var s: int = v
	if s < 0 or s > 3:
		return null
	return s


## hand_seq 命名空间：instance_id ∈ [hand_seq*136, hand_seq*136+135]


static func _contains_forbidden_hash_keys(v: Variant) -> bool:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			for forbidden in FORBIDDEN_HASH_KEYS:
				if d.has(forbidden):
					return true
			for k in d.keys():
				if _contains_forbidden_hash_keys(d[k]):
					return true
			return false
		TYPE_ARRAY:
			for item in v:
				if _contains_forbidden_hash_keys(item):
					return true
			return false
		_:
			return false


static func _deep_copy_json_safe(v: Variant) -> Variant:
	# 依赖 compute_view_hash 已证明 JSON-safe；deep copy 保序与原类型
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return v
		TYPE_ARRAY:
			var out: Array = []
			for item in v:
				out.append(_deep_copy_json_safe(item))
			return out
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var out_d: Dictionary = {}
			for k in d.keys():
				out_d[k] = _deep_copy_json_safe(d[k])
			return out_d
		_:
			return null


# ---- PLAYER_JOINED / HAND_SETTLED / MATCH_SETTLED ----


## hand_seq 命名空间：instance_id ∈ [hand_seq*136, hand_seq*136+135]
static func _is_instance_id_in_hand_namespace(instance_id: int, hand_seq: int) -> bool:
	var base: int = hand_seq * ProtocolConstants.TILES_PER_HAND
	return instance_id >= base and instance_id <= base + (ProtocolConstants.TILES_PER_HAND - 1)


static func _meld_tiles_in_hand_namespace(meld: Dictionary, hand_seq: int) -> bool:
	var tiles: Array = meld.get("tiles", [])
	for t in tiles:
		if typeof(t) != TYPE_DICTIONARY:
			return false
		if not _is_instance_id_in_hand_namespace(int((t as Dictionary)["instance_id"]), hand_seq):
			return false
	return true


## ROOM_SNAPSHOT / ACTION_APPLIED 共用：副露 from_seat 相对持有席规则


## ROOM_SNAPSHOT / ACTION_APPLIED 共用：副露 from_seat 相对持有席规则
static func _meld_from_seat_rules(meld: Dictionary, holder_seat: int) -> bool:
	var meld_kind: String = str(meld.get("kind", ""))
	var from_seat: int = int(meld.get("from_seat", -999))
	match meld_kind:
		"ANKAN":
			return from_seat == -1
		"CHI":
			if from_seat < 0 or from_seat > 3:
				return false
			if from_seat == holder_seat:
				return false
			# 上家
			return from_seat == (holder_seat + 3) % 4
		"PON", "MINKAN", "ADDED_KAN":
			if from_seat < 0 or from_seat > 3:
				return false
			return from_seat != holder_seat
		_:
			return false


## TURN offers：DISCARD/RIICHI tile、ANKAN 四 tile、ADDED_KAN added 须在 hand


## 收集可见物理实体 id；重复则 false。called/added/last_drawn 不在此重复计入。
static func _collect_visible_tile_id(
	seen: Dictionary,
	instance_id: int,
	hand_seq: int
) -> bool:
	if not _is_instance_id_in_hand_namespace(instance_id, hand_seq):
		return false
	if seen.has(instance_id):
		return false
	seen[instance_id] = true
	return true


# ---- ROOM_SNAPSHOT 模块化 v1 ----
