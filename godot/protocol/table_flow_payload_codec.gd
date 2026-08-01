class_name TableFlowPayloadCodec extends RefCounted

# ARCH-03 #393：桌面行动/提示 payload codec —— ACTION_APPLIED / TURN_PROMPT / CLAIM_WINDOW。
# 校验语义与拆分前 NetworkedEvent 完全一致；ActionOffer 同源 Action.normalize_payload。

const DISCARD_SOURCES := ["DRAWN", "HAND"]

const ACTION_APPLIED_KINDS := [
	"DISCARD", "CHI", "PON", "KAN", "RIICHI", "RON", "TSUMO", "PASS", "DECLARE_ABORTIVE_DRAW",
]

const ACTION_APPLIED_PAYLOAD_KEYS := [
	"causation_command_id", "hand_seq", "decision_id",
	"seat", "action_kind", "resolved_payload",
]

const TURN_PAYLOAD_KEYS := [
	"hand_seq", "decision_id", "seat", "hand",
	"last_drawn_tile_instance_id", "allowed_actions",
]

const CLAIM_PAYLOAD_KEYS := [
	"hand_seq", "decision_id", "discarded_by_seat",
	"discarded_tile", "allowed_actions",
]

const OFFER_KEYS := ["kind", "payload_options"]

const TURN_OFFER_KINDS := [
	"DISCARD", "RIICHI", "KAN", "TSUMO", "DECLARE_ABORTIVE_DRAW",
]

const CLAIM_OFFER_KINDS := ["PASS", "CHI", "PON", "KAN", "RON"]

const TURN_KAN_KINDS := ["ANKAN", "ADDED_KAN"]

const CLAIM_KAN_KINDS := ["MINKAN"]


static func validate_action_applied(p: Dictionary) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, ACTION_APPLIED_PAYLOAD_KEYS):
		return null

	if typeof(p["causation_command_id"]) != TYPE_STRING:
		return null
	var causation: String = p["causation_command_id"]
	if not ProtocolUuid.is_canonical_v4(causation):
		return null

	if typeof(p["hand_seq"]) != TYPE_INT:
		return null
	var hs: int = p["hand_seq"]
	if hs < 0 or hs > ProtocolConstants.MAX_HAND_SEQ:
		return null

	if typeof(p["decision_id"]) != TYPE_STRING:
		return null
	var dec: String = p["decision_id"]
	if not ProtocolUuid.is_canonical_v4(dec):
		return null

	if typeof(p["seat"]) != TYPE_INT:
		return null
	var seat_id: int = p["seat"]
	if seat_id < 0 or seat_id > 3:
		return null

	if typeof(p["action_kind"]) != TYPE_STRING:
		return null
	var action_kind: String = p["action_kind"]
	if action_kind not in ACTION_APPLIED_KINDS:
		return null

	if typeof(p["resolved_payload"]) != TYPE_DICTIONARY:
		return null
	var resolved: Variant = _validate_resolved_payload(
		action_kind, p["resolved_payload"], seat_id, hs
	)
	if resolved == null:
		return null

	return {
		"causation_command_id": causation,
		"hand_seq": hs,
		"decision_id": dec,
		"seat": seat_id,
		"action_kind": action_kind,
		"resolved_payload": (resolved as Dictionary).duplicate(true),
	}


static func _validate_resolved_payload(
	action_kind: String,
	rp: Dictionary,
	actor_seat: int,
	hand_seq: int
) -> Variant:
	match action_kind:
		"DISCARD", "RIICHI":
			if not EventPayloadCodecUtil._has_exact_keys(rp, ["tile", "discard_source"]):
				return null
			var tile: Variant = ProtocolViewCodec.tile_view_from_dict(rp["tile"])
			if tile == null:
				return null
			var tile_d: Dictionary = tile
			if not EventPayloadCodecUtil._is_instance_id_in_hand_namespace(int(tile_d["instance_id"]), hand_seq):
				return null
			if typeof(rp["discard_source"]) != TYPE_STRING:
				return null
			var src: String = rp["discard_source"]
			if src not in DISCARD_SOURCES:
				return null
			return {
				"tile": tile_d.duplicate(true),
				"discard_source": src,
			}
		"CHI", "PON", "KAN":
			if not EventPayloadCodecUtil._has_exact_keys(rp, ["meld"]):
				return null
			var meld: Variant = ProtocolViewCodec.meld_view_from_dict(rp["meld"])
			if meld == null:
				return null
			var md: Dictionary = meld
			var meld_kind: String = str(md.get("kind", ""))
			var from_seat: int = int(md.get("from_seat", -999))
			# action_kind 与 canonical meld.kind 对齐
			match action_kind:
				"CHI":
					if meld_kind != "CHI":
						return null
				"PON":
					if meld_kind != "PON":
						return null
				"KAN":
					if meld_kind not in ["MINKAN", "ANKAN", "ADDED_KAN"]:
						return null
			# from_seat vs actor：鸣自他人须 != actor；ANKAN 须 -1
			if meld_kind == "ANKAN":
				if from_seat != -1:
					return null
			elif meld_kind in ["CHI", "PON", "MINKAN", "ADDED_KAN"]:
				if from_seat == actor_seat:
					return null
			# meld.tiles 全量 namespace；called/added 仅为 tiles 内引用
			if not EventPayloadCodecUtil._meld_tiles_in_hand_namespace(md, hand_seq):
				return null
			return {"meld": md.duplicate(true)}
		"RON":
			if not EventPayloadCodecUtil._has_exact_keys(rp, ["winning_tile", "from_seat"]):
				return null
			var wt: Variant = ProtocolViewCodec.tile_view_from_dict(rp["winning_tile"])
			if wt == null:
				return null
			var wt_d: Dictionary = wt
			if not EventPayloadCodecUtil._is_instance_id_in_hand_namespace(int(wt_d["instance_id"]), hand_seq):
				return null
			if typeof(rp["from_seat"]) != TYPE_INT:
				return null
			var from_seat: int = rp["from_seat"]
			if from_seat < 0 or from_seat > 3:
				return null
			if from_seat == actor_seat:
				return null
			return {
				"winning_tile": wt_d.duplicate(true),
				"from_seat": from_seat,
			}
		"TSUMO":
			if not EventPayloadCodecUtil._has_exact_keys(rp, ["winning_tile"]):
				return null
			var tw: Variant = ProtocolViewCodec.tile_view_from_dict(rp["winning_tile"])
			if tw == null:
				return null
			var tw_d: Dictionary = tw
			if not EventPayloadCodecUtil._is_instance_id_in_hand_namespace(int(tw_d["instance_id"]), hand_seq):
				return null
			return {"winning_tile": tw_d.duplicate(true)}
		"PASS":
			if not rp.is_empty():
				return null
			return {}
		"DECLARE_ABORTIVE_DRAW":
			if not EventPayloadCodecUtil._has_exact_keys(rp, ["reason"]):
				return null
			if typeof(rp["reason"]) != TYPE_STRING:
				return null
			if str(rp["reason"]) != "KYUUSYU_KYUUHAI":
				return null
			return {"reason": "KYUUSYU_KYUUHAI"}
		_:
			return null


# ---- TURN_PROMPT / CLAIM_WINDOW ----


static func validate_turn_prompt(p: Dictionary) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, TURN_PAYLOAD_KEYS):
		return null

	if typeof(p["hand_seq"]) != TYPE_INT:
		return null
	var hs: int = p["hand_seq"]
	if hs < 0 or hs > ProtocolConstants.MAX_HAND_SEQ:
		return null

	if typeof(p["decision_id"]) != TYPE_STRING:
		return null
	var dec: String = p["decision_id"]
	if not ProtocolUuid.is_canonical_v4(dec):
		return null

	if typeof(p["seat"]) != TYPE_INT:
		return null
	var seat_id: int = p["seat"]
	if seat_id < 0 or seat_id > 3:
		return null

	if typeof(p["hand"]) != TYPE_ARRAY:
		return null
	var hand_out: Array = []
	var hand_ids: Dictionary = {}
	for item in p["hand"]:
		var tv: Variant = ProtocolViewCodec.tile_view_from_dict(item)
		if tv == null:
			return null
		var td: Dictionary = tv
		var iid: int = td["instance_id"]
		if not EventPayloadCodecUtil._is_instance_id_in_hand_namespace(iid, hs):
			return null
		if hand_ids.has(iid):
			return null
		hand_ids[iid] = true
		hand_out.append(td)

	if typeof(p["last_drawn_tile_instance_id"]) != TYPE_INT:
		return null
	var last_drawn: int = p["last_drawn_tile_instance_id"]
	if last_drawn < -1 or last_drawn > ProtocolConstants.MAX_SAFE_INT:
		return null
	if last_drawn >= 0 and not hand_ids.has(last_drawn):
		return null
	if last_drawn == -1:
		pass
	elif last_drawn < 0:
		return null

	var offers: Variant = _validate_allowed_actions(
		p["allowed_actions"], TURN_OFFER_KINDS, TURN_KAN_KINDS, false
	)
	if offers == null:
		return null
	# DISCARD/RIICHI/ANKAN/ADDED_KAN 实体必须存在于本 prompt hand
	if not _turn_offers_reference_hand(offers as Array, hand_ids):
		return null

	return {
		"hand_seq": hs,
		"decision_id": dec,
		"seat": seat_id,
		"hand": hand_out.duplicate(true),
		"last_drawn_tile_instance_id": last_drawn,
		"allowed_actions": offers,
	}


static func validate_claim_window(p: Dictionary) -> Variant:
	if not EventPayloadCodecUtil._has_exact_keys(p, CLAIM_PAYLOAD_KEYS):
		return null

	if typeof(p["hand_seq"]) != TYPE_INT:
		return null
	var hs: int = p["hand_seq"]
	if hs < 0 or hs > ProtocolConstants.MAX_HAND_SEQ:
		return null

	if typeof(p["decision_id"]) != TYPE_STRING:
		return null
	var dec: String = p["decision_id"]
	if not ProtocolUuid.is_canonical_v4(dec):
		return null

	if typeof(p["discarded_by_seat"]) != TYPE_INT:
		return null
	var discarded_by: int = p["discarded_by_seat"]
	if discarded_by < 0 or discarded_by > 3:
		return null

	var discarded_tile: Variant = ProtocolViewCodec.tile_view_from_dict(p["discarded_tile"])
	if discarded_tile == null:
		return null
	var discarded_d: Dictionary = discarded_tile
	if not EventPayloadCodecUtil._is_instance_id_in_hand_namespace(int(discarded_d["instance_id"]), hs):
		return null

	var offers: Variant = _validate_allowed_actions(
		p["allowed_actions"], CLAIM_OFFER_KINDS, CLAIM_KAN_KINDS, true
	)
	if offers == null:
		return null
	# CHI/PON/MINKAN companions 落在 hand_seq 命名空间；PASS/RON 无实体
	if not _claim_offers_in_hand_namespace(offers as Array, hs):
		return null

	return {
		"hand_seq": hs,
		"decision_id": dec,
		"discarded_by_seat": discarded_by,
		"discarded_tile": discarded_d.duplicate(true),
		"allowed_actions": offers,
	}


## ActionOffer 列表：exact 两键；payload_options 非空；同源 normalize；同 kind 唯一；规范化去重


## ActionOffer 列表：exact 两键；payload_options 非空；同源 normalize；同 kind 唯一；规范化去重
static func _validate_allowed_actions(
	raw: Variant,
	kind_whitelist: Array,
	kan_kinds: Array,
	require_pass: bool
) -> Variant:
	if typeof(raw) != TYPE_ARRAY:
		return null
	var arr: Array = raw
	if arr.is_empty():
		return null

	var out: Array = []
	var seen_kinds: Dictionary = {}
	var has_pass := false

	for item in arr:
		if typeof(item) != TYPE_DICTIONARY:
			return null
		var od: Dictionary = item
		if not EventPayloadCodecUtil._has_exact_keys(od, OFFER_KEYS):
			return null
		if typeof(od["kind"]) != TYPE_STRING:
			return null
		var offer_kind: String = od["kind"]
		if offer_kind not in kind_whitelist:
			return null
		if seen_kinds.has(offer_kind):
			return null
		seen_kinds[offer_kind] = true
		if offer_kind == "PASS":
			has_pass = true

		if typeof(od["payload_options"]) != TYPE_ARRAY:
			return null
		var opts_raw: Array = od["payload_options"]
		if opts_raw.is_empty():
			return null

		var opts_out: Array = []
		var seen_opt_keys: Dictionary = {}
		for opt in opts_raw:
			if typeof(opt) != TYPE_DICTIONARY:
				return null
			var normalized: Variant = Action.normalize_payload(offer_kind, opt)
			if normalized == null:
				return null
			var nd: Dictionary = normalized
			# KAN 子型白名单（窗口级）
			if offer_kind == "KAN":
				var kk: String = str(nd.get("kan_kind", ""))
				if kk not in kan_kinds:
					return null
			# PASS 严格 [{}]：normalize 已保证空 dict；数量在循环外再检
			var key: String = JSON.stringify(nd)
			if seen_opt_keys.has(key):
				return null
			seen_opt_keys[key] = true
			opts_out.append(nd.duplicate(true))

		if offer_kind == "PASS":
			if opts_out.size() != 1:
				return null
			if not (opts_out[0] as Dictionary).is_empty():
				return null

		out.append({
			"kind": offer_kind,
			"payload_options": opts_out,
		})

	if require_pass and not has_pass:
		return null
	return out


# ---- E5 payloads（保留现有语义） ----


## TURN offers：DISCARD/RIICHI tile、ANKAN 四 tile、ADDED_KAN added 须在 hand
static func _turn_offers_reference_hand(offers: Array, hand_ids: Dictionary) -> bool:
	for offer in offers:
		if typeof(offer) != TYPE_DICTIONARY:
			return false
		var od: Dictionary = offer
		var offer_kind: String = str(od.get("kind", ""))
		var opts: Array = od.get("payload_options", [])
		for opt in opts:
			if typeof(opt) != TYPE_DICTIONARY:
				return false
			var op: Dictionary = opt
			match offer_kind:
				"DISCARD", "RIICHI":
					if not hand_ids.has(int(op.get("tile_instance_id", -1))):
						return false
				"KAN":
					var kk: String = str(op.get("kan_kind", ""))
					if kk == "ANKAN":
						var ids: Array = op.get("tile_instance_ids", [])
						for tid in ids:
							if not hand_ids.has(int(tid)):
								return false
					elif kk == "ADDED_KAN":
						if not hand_ids.has(int(op.get("added_tile_instance_id", -1))):
							return false
				_:
					pass
	return true


## CLAIM offers：CHI/PON/MINKAN companions 在 hand_seq 命名空间；PASS/RON 无实体


## CLAIM offers：CHI/PON/MINKAN companions 在 hand_seq 命名空间；PASS/RON 无实体
static func _claim_offers_in_hand_namespace(offers: Array, hand_seq: int) -> bool:
	for offer in offers:
		if typeof(offer) != TYPE_DICTIONARY:
			return false
		var od: Dictionary = offer
		var offer_kind: String = str(od.get("kind", ""))
		var opts: Array = od.get("payload_options", [])
		for opt in opts:
			if typeof(opt) != TYPE_DICTIONARY:
				return false
			var op: Dictionary = opt
			match offer_kind:
				"CHI", "PON":
					var companions: Array = op.get("companion_tile_instance_ids", [])
					for cid in companions:
						if not EventPayloadCodecUtil._is_instance_id_in_hand_namespace(int(cid), hand_seq):
							return false
				"KAN":
					# CLAIM 仅 MINKAN；companions 三 id
					var minkan_ids: Array = op.get("companion_tile_instance_ids", [])
					for mid in minkan_ids:
						if not EventPayloadCodecUtil._is_instance_id_in_hand_namespace(int(mid), hand_seq):
							return false
				_:
					# PASS / RON 无实体字段
					pass
	return true


## 收集可见物理实体 id；重复则 false。called/added/last_drawn 不在此重复计入。
