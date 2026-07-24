class_name DecisionContext
extends RefCounted
## 单座位决策 offer：严格 kind/payload、只读标量、深拷贝 allowed_actions。

const KIND_TURN := "TURN"
const KIND_CLAIM := "CLAIM"
const KIND_ROB_KAN := "ROB_KAN"

const _TURN_KINDS := {
	"DISCARD": true, "RIICHI": true, "KAN": true, "TSUMO": true,
	"DECLARE_ABORTIVE_DRAW": true,
}
const _CLAIM_KINDS := {
	"CHI": true, "PON": true, "KAN": true, "RON": true, "PASS": true,
}
const _ROB_KINDS := {
	"RON": true, "PASS": true,
}

var _window_kind: String = ""
var window_kind: String:
	get:
		return _window_kind

var _hand_seq: int = 0
var hand_seq: int:
	get:
		return _hand_seq

var _decision_id: String = ""
var decision_id: String:
	get:
		return _decision_id

var _seat: int = -1
var seat: int:
	get:
		return _seat

var _claimed_tile_instance_id: int = -1
var claimed_tile_instance_id: int:
	get:
		return _claimed_tile_instance_id

var _discarder_seat: int = -1
var discarder_seat: int:
	get:
		return _discarder_seat

## 私有：Array of exact `{kind, payload_options}`
var _allowed_actions: Array = []

var allowed_actions: Array:
	get:
		return _deep_copy_allowed_actions(_allowed_actions)

var allowed_kinds: Array:
	get:
		return _derive_allowed_kinds()


static func make(
	p_window_kind: String,
	p_hand_seq: int,
	p_decision_id: String,
	p_seat: int,
	p_allowed_actions: Variant,
	p_claimed_tile_instance_id: int = -1,
	p_discarder_seat: int = -1
) -> DecisionContext:
	if p_window_kind != KIND_TURN and p_window_kind != KIND_CLAIM and p_window_kind != KIND_ROB_KAN:
		return null
	if typeof(p_hand_seq) != TYPE_INT:
		return null
	if p_hand_seq < 0 or p_hand_seq > ProtocolConstants.MAX_HAND_SEQ:
		return null
	if not ProtocolUuid.is_canonical_v4(p_decision_id):
		return null
	if typeof(p_seat) != TYPE_INT or p_seat < 0 or p_seat > 3:
		return null
	if typeof(p_allowed_actions) != TYPE_ARRAY:
		return null
	if not _validate_claimed_discarder(
		p_window_kind, p_seat, p_claimed_tile_instance_id, p_discarder_seat, p_hand_seq
	):
		return null
	var validated: Variant = _validate_allowed_actions(
		p_window_kind, p_allowed_actions, p_hand_seq
	)
	if validated == null:
		return null

	var ctx := DecisionContext.new()
	ctx._window_kind = p_window_kind
	ctx._hand_seq = p_hand_seq
	ctx._decision_id = p_decision_id
	ctx._seat = p_seat
	ctx._claimed_tile_instance_id = p_claimed_tile_instance_id
	ctx._discarder_seat = p_discarder_seat
	ctx._allowed_actions = validated as Array
	return ctx


func to_dict() -> Dictionary:
	return {
		"window_kind": _window_kind,
		"hand_seq": _hand_seq,
		"decision_id": _decision_id,
		"seat": _seat,
		"claimed_tile_instance_id": _claimed_tile_instance_id,
		"discarder_seat": _discarder_seat,
		"allowed_actions": allowed_actions,
		"allowed_kinds": allowed_kinds,
	}


func has_kind(action_kind: String) -> bool:
	for offer in _allowed_actions:
		if offer is Dictionary and str(offer.get("kind", "")) == action_kind:
			return true
	return false


func allows(action_kind: String, payload: Dictionary) -> bool:
	if not has_kind(action_kind):
		return false
	var normalized: Variant = Action.normalize_payload(action_kind, payload)
	if normalized == null:
		return false
	for offer in _allowed_actions:
		if not (offer is Dictionary):
			continue
		if str(offer.get("kind", "")) != action_kind:
			continue
		var options: Array = offer.get("payload_options", [])
		if not (options is Array):
			continue
		for opt in options:
			if not (opt is Dictionary):
				continue
			# _allowed_actions 已在 make() 中完成 exact 校验和 normalize；
			# 每次决策只归一化来参，避免对同一窗口的全部 offer 重复做第二遍解析。
			if _deep_equal(normalized, opt):
				return true
	return false


## 仅供 DecisionWindow 复制已经过 make() 校验的内部快照；不重新解析 offer。
## 仍深拷贝 nested payload，保持 add/context_for_seat 的引用隔离契约。
func _clone_validated() -> DecisionContext:
	var ctx := DecisionContext.new()
	ctx._window_kind = _window_kind
	ctx._hand_seq = _hand_seq
	ctx._decision_id = _decision_id
	ctx._seat = _seat
	ctx._claimed_tile_instance_id = _claimed_tile_instance_id
	ctx._discarder_seat = _discarder_seat
	ctx._allowed_actions = _deep_copy_allowed_actions(_allowed_actions)
	return ctx


static func _validate_claimed_discarder(
	p_window_kind: String, p_seat: int, claimed: int, discarder: int, p_hand_seq: int
) -> bool:
	if p_window_kind == KIND_TURN:
		return claimed == -1 and discarder == -1
	# CLAIM / ROB_KAN：claimed 必须属于本局 hand_seq 命名空间
	if discarder < 0 or discarder > 3:
		return false
	if p_seat == discarder:
		return false
	if not Tile.is_instance_id_in_hand_seq(claimed, p_hand_seq):
		return false
	return true


static func _validate_allowed_actions(
	p_window_kind: String, raw: Array, p_hand_seq: int
) -> Variant:
	if raw.is_empty():
		return null
	var result: Array = []
	var seen_kinds: Dictionary = {}
	var has_pass := false
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			return null
		var d: Dictionary = item
		if d.keys().size() != 2:
			return null
		if not d.has("kind") or not d.has("payload_options"):
			return null
		if typeof(d["kind"]) != TYPE_STRING:
			return null
		var action_kind: String = d["kind"]
		if not _kind_allowed_in_window(p_window_kind, action_kind):
			return null
		if seen_kinds.has(action_kind):
			return null
		seen_kinds[action_kind] = true
		if action_kind == "PASS":
			has_pass = true
		if typeof(d["payload_options"]) != TYPE_ARRAY:
			return null
		var opts: Array = d["payload_options"]
		if opts.is_empty():
			return null
		var norm_opts: Array = []
		var seen_opt_keys: Dictionary = {}
		for opt in opts:
			if typeof(opt) != TYPE_DICTIONARY:
				return null
			var opt_dict: Dictionary = opt
			if not _validate_offer_payload_for_window(p_window_kind, action_kind, opt_dict):
				return null
			var norm: Variant = Action.normalize_payload(action_kind, opt_dict)
			if norm == null:
				return null
			if not _payload_iids_in_hand_seq(norm as Dictionary, p_hand_seq):
				return null
			var key: String = JSON.stringify(norm)
			if seen_opt_keys.has(key):
				return null
			seen_opt_keys[key] = true
			norm_opts.append((norm as Dictionary).duplicate(true))
		result.append({
			"kind": action_kind,
			"payload_options": norm_opts,
		})
	if p_window_kind == KIND_CLAIM or p_window_kind == KIND_ROB_KAN:
		if not has_pass:
			return null
	return result


static func _kind_allowed_in_window(p_window_kind: String, action_kind: String) -> bool:
	match p_window_kind:
		KIND_TURN:
			return _TURN_KINDS.has(action_kind)
		KIND_CLAIM:
			return _CLAIM_KINDS.has(action_kind)
		KIND_ROB_KAN:
			return _ROB_KINDS.has(action_kind)
		_:
			return false


static func _validate_offer_payload_for_window(
	p_window_kind: String, action_kind: String, payload: Dictionary
) -> bool:
	# 额外禁止旧键 / 泄漏 claimed/discarder 进 payload
	if payload.has("tile") or payload.has("claimed") or payload.has("discarder"):
		return false
	if action_kind == "KAN":
		var kk: Variant = payload.get("kan_kind", null)
		if typeof(kk) != TYPE_STRING:
			return false
		var kan_kind: String = kk
		if p_window_kind == KIND_TURN:
			if kan_kind != "ANKAN" and kan_kind != "ADDED_KAN":
				return false
			if kan_kind == "ADDED_KAN":
				if typeof(payload.get("meld_id", null)) != TYPE_INT:
					return false
		elif p_window_kind == KIND_CLAIM:
			if kan_kind != "MINKAN":
				return false
		elif p_window_kind == KIND_ROB_KAN:
			return false
	return true


static func _payload_iids_in_hand_seq(payload: Dictionary, p_hand_seq: int) -> bool:
	if payload.has("tile_instance_id"):
		if not Tile.is_instance_id_in_hand_seq(payload["tile_instance_id"], p_hand_seq):
			return false
	if payload.has("added_tile_instance_id"):
		if not Tile.is_instance_id_in_hand_seq(payload["added_tile_instance_id"], p_hand_seq):
			return false
	for arr_key in ["companion_tile_instance_ids", "tile_instance_ids"]:
		if not payload.has(arr_key):
			continue
		var arr: Variant = payload[arr_key]
		if typeof(arr) != TYPE_ARRAY:
			return false
		for iid in arr:
			if not Tile.is_instance_id_in_hand_seq(iid, p_hand_seq):
				return false
	return true


static func _deep_copy_allowed_actions(source: Array) -> Array:
	var result: Array = []
	for item in source:
		if not (item is Dictionary):
			continue
		var kind: String = str(item.get("kind", ""))
		var options_src: Array = item.get("payload_options", [])
		var options_copy: Array = []
		if options_src is Array:
			for opt in options_src:
				if opt is Dictionary:
					options_copy.append((opt as Dictionary).duplicate(true))
		result.append({
			"kind": kind,
			"payload_options": options_copy,
		})
	return result


func _derive_allowed_kinds() -> Array:
	var kinds: Array = []
	for offer in _allowed_actions:
		if not (offer is Dictionary):
			continue
		var kind: String = str(offer.get("kind", ""))
		if not kinds.has(kind):
			kinds.append(kind)
	return kinds.duplicate()


static func _deep_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for k in da.keys():
			if not db.has(k):
				return false
			if not _deep_equal(da[k], db[k]):
				return false
		return true
	if a is Array:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return false
		for i in range(aa.size()):
			if not _deep_equal(aa[i], ab[i]):
				return false
		return true
	return a == b
