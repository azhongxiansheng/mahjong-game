class_name NetworkedEvent extends RefCounted

# 麻将王 — E2-02 ServerEvent 扁平业务事件包络（#232）
#
# exact envelope 六键：
# protocol_version / server_seq / room_id / kind / payload / view_hash
#
# view_hash 必需 64 小写 hex；任何层递归拒绝 state_hash / full_state_hash。
# ACTION_APPLIED 是 resolved 权威结果，禁止命令回显。
# TURN_PROMPT / CLAIM_WINDOW 私有 schema 严格校验；ActionOffer 同源 Action.normalize_payload。

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
	"HAND_SETTLED",
	"MATCH_SETTLED",
]

const ENVELOPE_KEYS := [
	"protocol_version", "server_seq", "room_id", "kind", "payload", "view_hash",
]
const FORBIDDEN_HASH_KEYS := ["snapshot_hash", "state_hash", "full_state_hash"]

const SETTLED_OUTCOMES := ["FULL_GRANT", "DISPLAY_ONLY"]
const CANCEL_REASON := "CANCELLED_BY_WIN"
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
# ITEM_USE 仅 Action 命令可表达，不入 TURN_PROMPT offer
const TURN_OFFER_KINDS := [
	"DISCARD", "RIICHI", "KAN", "TSUMO", "DECLARE_ABORTIVE_DRAW",
]
const CLAIM_OFFER_KINDS := ["PASS", "CHI", "PON", "KAN", "RON"]
const TURN_KAN_KINDS := ["ANKAN", "ADDED_KAN"]
const CLAIM_KAN_KINDS := ["MINKAN"]

const ROOM_SNAPSHOT_TOP_KEYS := [
	"snapshot_server_seq", "next_server_seq", "seat_view", "modules",
]
const MODULE_ENTRY_KEYS := ["module_key", "schema_version", "payload"]
const CORE_TABLE_KEYS := [
	"recipient_seat", "hand_seq", "dealer_seat", "current_seat", "phase",
	"round_wind", "hand_number", "honba", "riichi_sticks", "live_wall_count",
	"dora_indicators", "seats",
]
const VIEWER_NEXT_DRAW_KEYS := ["recipient_seat", "hand_seq", "tile"]
const VIEWER_WALL_TOP_KEYS := ["recipient_seat", "hand_seq", "tiles"]
const VIEWER_WALL_TOP_ENTRY_KEYS := ["offset", "tile"]
const VIEWER_SEAT_DRAW_FORECAST_KEYS := ["recipient_seat", "hand_seq", "predictions"]
const VIEWER_SEAT_DRAW_FORECAST_ROW_KEYS := ["target_seat", "tile"]
const SEAT_VIEW_KEYS := [
	"seat", "seat_wind", "score", "concealed_tiles", "concealed_count",
	"last_drawn_tile_instance_id", "river", "melds", "riichi_declared",
	"riichi_double", "riichi_discard_index",
]
# core_table 公开硬上限（非阶段精确牌数）
const LIVE_WALL_COUNT_MAX := 70
const DORA_INDICATORS_MIN := 1
const DORA_INDICATORS_MAX := 5
const CONCEALED_COUNT_MAX := 14
const RIVER_SIZE_MAX := 70
const MELDS_SIZE_MAX := 4
const SNAPSHOT_PHASES := ["DRAW", "DISCARD", "CLAIM", "SETTLE"]
const SEAT_WINDS := [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N]
const ROUND_WINDS := [TileId.E, TileId.S_WIND]
const PLAYER_JOINED_KEYS := ["seat", "participant_kind", "display_name", "connected"]
const PARTICIPANT_KINDS := ["HUMAN", "AI"]
const HAND_SETTLED_KEYS := [
	"hand_seq", "outcome", "winner_seats", "loser_seat", "score_deltas", "scores",
]
const HAND_OUTCOMES := ["RON", "TSUMO", "EXHAUSTIVE_DRAW", "ABORTIVE_DRAW"]
const MATCH_SETTLED_KEYS := ["round_kind", "final_scores", "seat_order"]
const MATCH_ROUND_KINDS := ["EAST", "HANCHAN"]

const _VIEW_HASH_RE := "^[0-9a-f]{64}$"

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


# ---- 唯一构造入口（五参必填；合法 wire 走 from_dict；ERROR / COMMAND_RESULT 一律 null） ----

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
	if not _has_exact_keys(d, ENVELOPE_KEYS):
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
	if not _is_view_hash(vh):
		return null

	# 任何层递归拒绝私有 hash 键
	if _contains_forbidden_hash_keys(raw_payload):
		return null

	# server_seq 显式传入，供 boundary 与 typed validator 使用
	var validated: Variant = _validate_payload(kind_str, raw_payload, seq)
	if validated == null:
		return null
	if _contains_forbidden_hash_keys(validated):
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

static func _validate_payload(kind_str: String, p: Dictionary, envelope_server_seq: int) -> Variant:
	match kind_str:
		"ACTION_APPLIED":
			return _validate_action_applied(p)
		"TURN_PROMPT":
			return _validate_turn_prompt(p)
		"CLAIM_WINDOW":
			return _validate_claim_window(p)
		"REWARD_WINDOW_OPENED":
			return _validate_reward_opened(p)
		"REWARD_WINDOW_CLOSING":
			return _validate_reward_closing(p, envelope_server_seq)
		"REWARD_WINDOW_SETTLED":
			return _validate_reward_settled(p, envelope_server_seq)
		"REWARD_WINDOW_CANCELLED":
			return _validate_reward_cancelled(p, envelope_server_seq)
		"ITEM_GRANTED":
			return _validate_item_granted(p)
		"ITEM_CONSUMED":
			return _validate_item_consumed(p)
		"ITEM_APPLIED":
			return _validate_item_applied(p)
		"CHARACTER_ABILITY_ARMED":
			return _validate_ability_armed(p)
		"CHARACTER_ABILITY_DISARMED":
			return _validate_ability_disarmed(p)
		"ROOM_SNAPSHOT":
			return _validate_room_snapshot(p)
		"PLAYER_JOINED":
			return _validate_player_joined(p)
		"HAND_SETTLED":
			return _validate_hand_settled(p)
		"MATCH_SETTLED":
			return _validate_match_settled(p)
		_:
			return null


static func _validate_action_applied(p: Dictionary) -> Variant:
	if not _has_exact_keys(p, ACTION_APPLIED_PAYLOAD_KEYS):
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
			if not _has_exact_keys(rp, ["tile", "discard_source"]):
				return null
			var tile: Variant = ProtocolViewCodec.tile_view_from_dict(rp["tile"])
			if tile == null:
				return null
			var tile_d: Dictionary = tile
			if not _is_instance_id_in_hand_namespace(int(tile_d["instance_id"]), hand_seq):
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
			if not _has_exact_keys(rp, ["meld"]):
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
			if not _meld_tiles_in_hand_namespace(md, hand_seq):
				return null
			return {"meld": md.duplicate(true)}
		"RON":
			if not _has_exact_keys(rp, ["winning_tile", "from_seat"]):
				return null
			var wt: Variant = ProtocolViewCodec.tile_view_from_dict(rp["winning_tile"])
			if wt == null:
				return null
			var wt_d: Dictionary = wt
			if not _is_instance_id_in_hand_namespace(int(wt_d["instance_id"]), hand_seq):
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
			if not _has_exact_keys(rp, ["winning_tile"]):
				return null
			var tw: Variant = ProtocolViewCodec.tile_view_from_dict(rp["winning_tile"])
			if tw == null:
				return null
			var tw_d: Dictionary = tw
			if not _is_instance_id_in_hand_namespace(int(tw_d["instance_id"]), hand_seq):
				return null
			return {"winning_tile": tw_d.duplicate(true)}
		"PASS":
			if not rp.is_empty():
				return null
			return {}
		"DECLARE_ABORTIVE_DRAW":
			if not _has_exact_keys(rp, ["reason"]):
				return null
			if typeof(rp["reason"]) != TYPE_STRING:
				return null
			if str(rp["reason"]) != "KYUUSYU_KYUUHAI":
				return null
			return {"reason": "KYUUSYU_KYUUHAI"}
		_:
			return null


# ---- TURN_PROMPT / CLAIM_WINDOW ----

static func _validate_turn_prompt(p: Dictionary) -> Variant:
	if not _has_exact_keys(p, TURN_PAYLOAD_KEYS):
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
		if not _is_instance_id_in_hand_namespace(iid, hs):
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


static func _validate_claim_window(p: Dictionary) -> Variant:
	if not _has_exact_keys(p, CLAIM_PAYLOAD_KEYS):
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
	if not _is_instance_id_in_hand_namespace(int(discarded_d["instance_id"]), hs):
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
		if not _has_exact_keys(od, OFFER_KEYS):
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

static func _validate_reward_opened(p: Dictionary) -> Variant:
	var keys := [
		"window_id", "hand_seq", "window_index", "prize_pool",
		"rule_version", "phase", "window_exit",
	]
	if not _has_exact_keys(p, keys):
		return null
	if not _is_nonempty_string(p["window_id"]):
		return null
	var hand_seq: Variant = _require_hand_seq(p["hand_seq"])
	if hand_seq == null:
		return null
	var window_index: Variant = _require_nonneg_safe_int(p["window_index"])
	if window_index == null:
		return null
	var pool: Variant = _validate_prize_pool(p["prize_pool"])
	if pool == null:
		return null
	if not _is_nonempty_string(p["rule_version"]):
		return null
	if typeof(p["phase"]) != TYPE_STRING or str(p["phase"]) != "OPEN":
		return null
	if p["window_exit"] != null:
		return null
	return {
		"window_id": p["window_id"],
		"hand_seq": int(hand_seq),
		"window_index": int(window_index),
		"prize_pool": pool,
		"rule_version": p["rule_version"],
		"phase": "OPEN",
		"window_exit": null,
	}


static func _validate_reward_closing(p: Dictionary, envelope_server_seq: int) -> Variant:
	var keys := [
		"window_id", "hand_seq", "closing_boundary_server_seq",
		"grace_deadline_at", "phase", "window_exit",
	]
	if not _has_exact_keys(p, keys):
		return null
	if not _is_nonempty_string(p["window_id"]):
		return null
	var hand_seq: Variant = _require_hand_seq(p["hand_seq"])
	if hand_seq == null:
		return null
	var boundary: Variant = _require_positive_safe_int(p["closing_boundary_server_seq"])
	if boundary == null:
		return null
	# closing_boundary 必须 ≤ envelope.server_seq
	if int(boundary) > envelope_server_seq:
		return null
	if not _is_nonempty_string(p["grace_deadline_at"]):
		return null
	if typeof(p["phase"]) != TYPE_STRING or str(p["phase"]) != "CLOSING":
		return null
	if p["window_exit"] != null:
		return null
	return {
		"window_id": p["window_id"],
		"hand_seq": int(hand_seq),
		"closing_boundary_server_seq": int(boundary),
		"grace_deadline_at": p["grace_deadline_at"],
		"phase": "CLOSING",
		"window_exit": null,
	}


static func _validate_reward_settled(p: Dictionary, envelope_server_seq: int) -> Variant:
	var keys := [
		"window_id", "outcome", "settle_reason", "rule_version",
		"assignment_version", "prize_pool", "matrix_summary", "assignment",
		"closing_boundary_server_seq", "context_boundary_server_seq",
		"grace_deadline_at", "grant_count", "hand_seq", "transcript_summary",
	]
	if not _has_exact_keys(p, keys):
		return null
	if not _is_nonempty_string(p["window_id"]):
		return null
	if typeof(p["outcome"]) != TYPE_STRING:
		return null
	var outcome: String = p["outcome"]
	if outcome not in SETTLED_OUTCOMES:
		return null
	if not _is_nonempty_string(p["settle_reason"]):
		return null
	if not _is_nonempty_string(p["rule_version"]):
		return null
	if not _is_nonempty_string(p["assignment_version"]):
		return null
	var pool: Variant = _validate_prize_pool(p["prize_pool"])
	if pool == null:
		return null
	var matrix_summary: Variant = _validate_opaque_json_dict(p["matrix_summary"])
	if matrix_summary == null:
		return null
	var assignment: Variant = _validate_opaque_json_dict(p["assignment"])
	if assignment == null:
		return null
	var closing_boundary: Variant = _require_positive_safe_int(p["closing_boundary_server_seq"])
	if closing_boundary == null:
		return null
	var context_boundary: Variant = _require_positive_safe_int(p["context_boundary_server_seq"])
	if context_boundary == null:
		return null
	# context 是 CLAIM 完成或无 CLAIM 同事务结果判定序号，不得早于 closing
	if int(context_boundary) < int(closing_boundary):
		return null
	# closing / context 均须 ≤ envelope.server_seq
	if int(closing_boundary) > envelope_server_seq:
		return null
	if int(context_boundary) > envelope_server_seq:
		return null
	if not _is_nonempty_string(p["grace_deadline_at"]):
		return null
	if typeof(p["grant_count"]) != TYPE_INT:
		return null
	var grant_count: int = p["grant_count"]
	if outcome == "FULL_GRANT" and grant_count != 4:
		return null
	if outcome == "DISPLAY_ONLY" and grant_count != 0:
		return null
	var hand_seq: Variant = _require_hand_seq(p["hand_seq"])
	if hand_seq == null:
		return null
	var transcript_summary: Variant = _validate_opaque_json_dict(p["transcript_summary"])
	if transcript_summary == null:
		return null
	return {
		"window_id": p["window_id"],
		"outcome": outcome,
		"settle_reason": p["settle_reason"],
		"rule_version": p["rule_version"],
		"assignment_version": p["assignment_version"],
		"prize_pool": pool,
		"matrix_summary": matrix_summary,
		"assignment": assignment,
		"closing_boundary_server_seq": int(closing_boundary),
		"context_boundary_server_seq": int(context_boundary),
		"grace_deadline_at": p["grace_deadline_at"],
		"grant_count": grant_count,
		"hand_seq": int(hand_seq),
		"transcript_summary": transcript_summary,
	}


static func _validate_reward_cancelled(p: Dictionary, envelope_server_seq: int) -> Variant:
	var keys := [
		"window_id", "cancel_reason", "closing_boundary_server_seq",
		"grace_aborted", "scored", "grant_count", "hand_seq",
	]
	if not _has_exact_keys(p, keys):
		return null
	if not _is_nonempty_string(p["window_id"]):
		return null
	if typeof(p["cancel_reason"]) != TYPE_STRING:
		return null
	if str(p["cancel_reason"]) != CANCEL_REASON:
		return null
	var boundary: Variant = p["closing_boundary_server_seq"]
	if boundary != null:
		boundary = _require_positive_safe_int(boundary)
		if boundary == null:
			return null
		# 非 null closing_boundary 必须 ≤ envelope.server_seq
		if int(boundary) > envelope_server_seq:
			return null
	if typeof(p["grace_aborted"]) != TYPE_BOOL:
		return null
	if typeof(p["scored"]) != TYPE_BOOL:
		return null
	if p["scored"] != false:
		return null
	if typeof(p["grant_count"]) != TYPE_INT:
		return null
	if int(p["grant_count"]) != 0:
		return null
	var hand_seq: Variant = _require_hand_seq(p["hand_seq"])
	if hand_seq == null:
		return null
	return {
		"window_id": p["window_id"],
		"cancel_reason": CANCEL_REASON,
		"closing_boundary_server_seq": boundary,
		"grace_aborted": p["grace_aborted"],
		"scored": false,
		"grant_count": 0,
		"hand_seq": int(hand_seq),
	}


static func _validate_item_granted(p: Dictionary) -> Variant:
	var keys := [
		"window_id", "rule_version", "assignment_version", "matched_rule_ids",
		"item_id", "item_instance_id", "seat", "hand_seq", "score",
		"affinity_match", "armed_for_window_id",
	]
	if not _has_exact_keys(p, keys):
		return null
	if not _is_nonempty_string(p["window_id"]):
		return null
	if not _is_nonempty_string(p["rule_version"]):
		return null
	if not _is_nonempty_string(p["assignment_version"]):
		return null
	if typeof(p["matched_rule_ids"]) != TYPE_ARRAY:
		return null
	var matched: Array = []
	for item in p["matched_rule_ids"]:
		if not _is_nonempty_string(item):
			return null
		matched.append(item)
	if not _is_nonempty_string(p["item_id"]):
		return null
	if not _is_nonempty_string(p["item_instance_id"]):
		return null
	if typeof(p["seat"]) != TYPE_INT:
		return null
	var seat_id: int = p["seat"]
	if seat_id < 0 or seat_id > 3:
		return null
	var hand_seq: Variant = _require_hand_seq(p["hand_seq"])
	if hand_seq == null:
		return null
	var score: Variant = _require_nonneg_safe_int(p["score"])
	if score == null:
		return null
	if typeof(p["affinity_match"]) != TYPE_BOOL:
		return null
	var armed = p["armed_for_window_id"]
	if armed != null and not _is_nonempty_string(armed):
		return null
	return {
		"window_id": p["window_id"],
		"rule_version": p["rule_version"],
		"assignment_version": p["assignment_version"],
		"matched_rule_ids": matched.duplicate(),
		"item_id": p["item_id"],
		"item_instance_id": p["item_instance_id"],
		"seat": seat_id,
		"hand_seq": int(hand_seq),
		"score": int(score),
		"affinity_match": p["affinity_match"],
		"armed_for_window_id": armed,
	}


static func _validate_item_consumed(p: Dictionary) -> Variant:
	if not _has_exact_keys(p, ["seat", "item_id", "item_instance_id", "command_id"]):
		return null
	if typeof(p["seat"]) != TYPE_INT:
		return null
	var seat_id: int = p["seat"]
	if seat_id < 0 or seat_id > 3:
		return null
	if not _is_nonempty_string(p["item_id"]):
		return null
	if not _is_nonempty_string(p["item_instance_id"]):
		return null
	if typeof(p["command_id"]) != TYPE_STRING:
		return null
	var cmd: String = p["command_id"]
	if not ProtocolUuid.is_canonical_v4(cmd):
		return null
	return {
		"seat": seat_id,
		"item_id": p["item_id"],
		"item_instance_id": p["item_instance_id"],
		"command_id": cmd,
	}


static func _validate_item_applied(p: Dictionary) -> Variant:
	if not _has_exact_keys(p, ["seat", "item_id", "item_instance_id", "effect_id", "command_id"]):
		return null
	if typeof(p["seat"]) != TYPE_INT:
		return null
	var seat_id: int = p["seat"]
	if seat_id < 0 or seat_id > 3:
		return null
	if not _is_nonempty_string(p["item_id"]):
		return null
	if not _is_nonempty_string(p["item_instance_id"]):
		return null
	if not _is_nonempty_string(p["effect_id"]):
		return null
	if typeof(p["command_id"]) != TYPE_STRING:
		return null
	var cmd: String = p["command_id"]
	if not ProtocolUuid.is_canonical_v4(cmd):
		return null
	return {
		"seat": seat_id,
		"item_id": p["item_id"],
		"item_instance_id": p["item_instance_id"],
		"effect_id": p["effect_id"],
		"command_id": cmd,
	}


static func _validate_ability_armed(p: Dictionary) -> Variant:
	if not _has_exact_keys(p, ["seat", "window_id", "character_id", "ability_id", "active_window_id"]):
		return null
	if typeof(p["seat"]) != TYPE_INT:
		return null
	var seat_id: int = p["seat"]
	if seat_id < 0 or seat_id > 3:
		return null
	if not _is_nonempty_string(p["window_id"]):
		return null
	if not _is_nonempty_string(p["character_id"]):
		return null
	if not _is_nonempty_string(p["ability_id"]):
		return null
	if not _is_nonempty_string(p["active_window_id"]):
		return null
	return {
		"seat": seat_id,
		"window_id": p["window_id"],
		"character_id": p["character_id"],
		"ability_id": p["ability_id"],
		"active_window_id": p["active_window_id"],
	}


static func _validate_ability_disarmed(p: Dictionary) -> Variant:
	if not _has_exact_keys(p, ["seat", "window_id", "character_id", "ability_id", "active_window_id"]):
		return null
	if typeof(p["seat"]) != TYPE_INT:
		return null
	var seat_id: int = p["seat"]
	if seat_id < 0 or seat_id > 3:
		return null
	if not _is_nonempty_string(p["window_id"]):
		return null
	if not _is_nonempty_string(p["character_id"]):
		return null
	if not _is_nonempty_string(p["ability_id"]):
		return null
	var active = p["active_window_id"]
	if active != null and not _is_nonempty_string(active):
		return null
	return {
		"seat": seat_id,
		"window_id": p["window_id"],
		"character_id": p["character_id"],
		"ability_id": p["ability_id"],
		"active_window_id": active,
	}


static func _validate_prize_pool(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_ARRAY:
		return null
	var arr: Array = raw
	if arr.size() != 4:
		return null
	var seen: Dictionary = {}
	var out: Array = []
	for item in arr:
		if not _is_nonempty_string(item):
			return null
		var s: String = item
		if seen.has(s):
			return null
		seen[s] = true
		out.append(s)
	return out


# ---- helpers ----

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
						if not _is_instance_id_in_hand_namespace(int(cid), hand_seq):
							return false
				"KAN":
					# CLAIM 仅 MINKAN；companions 三 id
					var minkan_ids: Array = op.get("companion_tile_instance_ids", [])
					for mid in minkan_ids:
						if not _is_instance_id_in_hand_namespace(int(mid), hand_seq):
							return false
				_:
					# PASS / RON 无实体字段
					pass
	return true


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

static func _validate_room_snapshot(p: Dictionary) -> Variant:
	if not _has_exact_keys(p, ROOM_SNAPSHOT_TOP_KEYS):
		return null

	var snap: Variant = _require_nonneg_safe_int(p["snapshot_server_seq"])
	if snap == null:
		return null
	var snap_i: int = snap
	if snap_i < 1:
		return null

	var next: Variant = _require_nonneg_safe_int(p["next_server_seq"])
	if next == null:
		return null
	var next_i: int = next
	if next_i != snap_i + 1:
		return null

	var seat_view: Variant = _require_seat(p["seat_view"])
	if seat_view == null:
		return null
	var seat_view_i: int = seat_view

	if typeof(p["modules"]) != TYPE_ARRAY:
		return null
	var raw_mods: Array = p["modules"]
	if raw_mods.is_empty():
		return null

	var modules_out: Array = []
	var seen_keys: Dictionary = {}
	var prev_key: String = ""
	var has_prev := false
	var core_count := 0
	var core_hand_seq := -1

	for item in raw_mods:
		if typeof(item) != TYPE_DICTIONARY:
			return null
		var md: Dictionary = item
		if not _has_exact_keys(md, MODULE_ENTRY_KEYS):
			return null

		if typeof(md["module_key"]) != TYPE_STRING:
			return null
		var mkey: String = md["module_key"]
		if mkey.is_empty() or mkey != mkey.strip_edges():
			return null
		if seen_keys.has(mkey):
			return null
		seen_keys[mkey] = true
		# 输入必须已按 module_key String 升序；禁止静默排序
		if has_prev and not (mkey > prev_key):
			return null
		has_prev = true
		prev_key = mkey

		if typeof(md["schema_version"]) != TYPE_INT:
			return null
		var sver: int = md["schema_version"]
		if sver < 1 or sver > ProtocolConstants.MAX_SAFE_INT:
			return null

		var pl_raw: Variant = md["payload"]
		var pl_out: Variant = null
		if mkey == "core_table":
			if sver != 1:
				return null
			core_count += 1
			if typeof(pl_raw) != TYPE_DICTIONARY:
				return null
			pl_out = _validate_core_table(pl_raw as Dictionary, seat_view_i)
			if pl_out == null:
				return null
			core_hand_seq = int((pl_out as Dictionary)["hand_seq"])
		elif mkey == "viewer_next_draw" and sver == 1:
			if typeof(pl_raw) != TYPE_DICTIONARY:
				return null
			pl_out = _validate_viewer_next_draw(
				pl_raw as Dictionary, seat_view_i, core_hand_seq)
			if pl_out == null:
				return null
		elif mkey == "viewer_wall_top" and sver == 1:
			if typeof(pl_raw) != TYPE_DICTIONARY:
				return null
			pl_out = _validate_viewer_wall_top(
				pl_raw as Dictionary, seat_view_i, core_hand_seq)
			if pl_out == null:
				return null
		elif mkey == "viewer_seat_draw_forecast" and sver == 1:
			if typeof(pl_raw) != TYPE_DICTIONARY:
				return null
			pl_out = _validate_viewer_seat_draw_forecast(
				pl_raw as Dictionary, seat_view_i, core_hand_seq)
			if pl_out == null:
				return null
		else:
			# unknown module：JSON-safe domain + deep copy；保序
			if ProtocolViewCodec.compute_view_hash(pl_raw).is_empty():
				return null
			pl_out = _deep_copy_json_safe(pl_raw)
			if typeof(pl_raw) != TYPE_NIL and pl_out == null:
				return null

		modules_out.append({
			"module_key": mkey,
			"schema_version": sver,
			"payload": pl_out,
		})

	if core_count != 1:
		return null

	return {
		"snapshot_server_seq": snap_i,
		"next_server_seq": next_i,
		"seat_view": seat_view_i,
		"modules": modules_out,
	}


static func _validate_core_table(p: Dictionary, seat_view: int) -> Variant:
	if not _has_exact_keys(p, CORE_TABLE_KEYS):
		return null

	var recipient: Variant = _require_seat(p["recipient_seat"])
	if recipient == null:
		return null
	var recipient_i: int = recipient
	if recipient_i != seat_view:
		return null

	if typeof(p["hand_seq"]) != TYPE_INT:
		return null
	var hs: int = p["hand_seq"]
	if hs < 0 or hs > ProtocolConstants.MAX_HAND_SEQ:
		return null

	var dealer: Variant = _require_seat(p["dealer_seat"])
	if dealer == null:
		return null
	var current: Variant = _require_seat(p["current_seat"])
	if current == null:
		return null

	if typeof(p["phase"]) != TYPE_STRING:
		return null
	var phase: String = p["phase"]
	if phase not in SNAPSHOT_PHASES:
		return null

	if typeof(p["round_wind"]) != TYPE_INT:
		return null
	var rw: int = p["round_wind"]
	if rw not in ROUND_WINDS:
		return null

	if typeof(p["hand_number"]) != TYPE_INT:
		return null
	var hn: int = p["hand_number"]
	if hn < 1 or hn > 4:
		return null

	var honba: Variant = _require_nonneg_safe_int(p["honba"])
	if honba == null:
		return null
	var sticks: Variant = _require_nonneg_safe_int(p["riichi_sticks"])
	if sticks == null:
		return null
	var live: Variant = _require_nonneg_safe_int(p["live_wall_count"])
	if live == null:
		return null
	if int(live) > LIVE_WALL_COUNT_MAX:
		return null

	if typeof(p["dora_indicators"]) != TYPE_ARRAY:
		return null
	var dora_size: int = (p["dora_indicators"] as Array).size()
	if dora_size < DORA_INDICATORS_MIN or dora_size > DORA_INDICATORS_MAX:
		return null
	var dora_out: Array = []
	for item in p["dora_indicators"]:
		var tv: Variant = ProtocolViewCodec.tile_view_from_dict(item)
		if tv == null:
			return null
		dora_out.append(tv)

	if typeof(p["seats"]) != TYPE_ARRAY:
		return null
	var seats_raw: Array = p["seats"]
	if seats_raw.size() != 4:
		return null
	var seats_out: Array = []
	var wind_seen: Dictionary = {}
	var global_meld_ids: Dictionary = {}
	for i in range(4):
		if typeof(seats_raw[i]) != TYPE_DICTIONARY:
			return null
		var sv: Variant = _validate_seat_view(
			seats_raw[i] as Dictionary, i, recipient_i, hs
		)
		if sv == null:
			return null
		var svd: Dictionary = sv
		var wind: int = svd["seat_wind"]
		if wind_seen.has(wind):
			return null
		wind_seen[wind] = true
		# meld_id 四席全局唯一（仅同席唯一不够）
		for mv0 in svd["melds"]:
			var mid0: int = int((mv0 as Dictionary)["meld_id"])
			if global_meld_ids.has(mid0):
				return null
			global_meld_ids[mid0] = true
		seats_out.append(svd)

	# 可见物理实体：dora + recipient 手牌 + 四席河 + 副露 tiles；全局唯一 + namespace
	# last_drawn / called / added 仅为引用，不重复计入
	var visible_ids: Dictionary = {}
	for dora_tv in dora_out:
		var did: int = int((dora_tv as Dictionary)["instance_id"])
		if not _collect_visible_tile_id(visible_ids, did, hs):
			return null
	for svd2 in seats_out:
		var seat_d: Dictionary = svd2
		for ct in seat_d["concealed_tiles"]:
			var cid: int = int((ct as Dictionary)["instance_id"])
			if not _collect_visible_tile_id(visible_ids, cid, hs):
				return null
		for rv in seat_d["river"]:
			var rid: int = int((rv as Dictionary)["instance_id"])
			if not _collect_visible_tile_id(visible_ids, rid, hs):
				return null
		for mv in seat_d["melds"]:
			var meld_d: Dictionary = mv
			for mt in meld_d["tiles"]:
				var mid: int = int((mt as Dictionary)["instance_id"])
				if not _collect_visible_tile_id(visible_ids, mid, hs):
					return null

	return {
		"recipient_seat": recipient_i,
		"hand_seq": hs,
		"dealer_seat": int(dealer),
		"current_seat": int(current),
		"phase": phase,
		"round_wind": rw,
		"hand_number": hn,
		"honba": int(honba),
		"riichi_sticks": int(sticks),
		"live_wall_count": int(live),
		"dora_indicators": dora_out,
		"seats": seats_out,
	}


static func _validate_viewer_next_draw(
	p: Dictionary, seat_view: int, core_hand_seq: int
) -> Variant:
	if not _has_exact_keys(p, VIEWER_NEXT_DRAW_KEYS):
		return null
	var recipient: Variant = _require_seat(p["recipient_seat"])
	if recipient == null or int(recipient) != seat_view:
		return null
	if typeof(p["hand_seq"]) != TYPE_INT:
		return null
	var hand_seq := int(p["hand_seq"])
	if hand_seq < 0 or hand_seq != core_hand_seq:
		return null
	var tile: Variant = ProtocolViewCodec.tile_view_from_dict(p["tile"])
	if tile == null:
		return null
	if not _is_instance_id_in_hand_namespace(int((tile as Dictionary)["instance_id"]), hand_seq):
		return null
	return {
		"recipient_seat": int(recipient),
		"hand_seq": hand_seq,
		"tile": tile,
	}


static func _validate_viewer_wall_top(
	p: Dictionary, seat_view: int, core_hand_seq: int
) -> Variant:
	if not _has_exact_keys(p, VIEWER_WALL_TOP_KEYS):
		return null
	var recipient: Variant = _require_seat(p["recipient_seat"])
	if recipient == null or int(recipient) != seat_view \
			or typeof(p["hand_seq"]) != TYPE_INT:
		return null
	var hand_seq := int(p["hand_seq"])
	if hand_seq < 0 or hand_seq != core_hand_seq or typeof(p["tiles"]) != TYPE_ARRAY:
		return null
	var raw_tiles := p["tiles"] as Array
	if raw_tiles.is_empty() or raw_tiles.size() > 3:
		return null
	var tiles_out: Array = []
	var seen: Dictionary = {}
	for index in range(raw_tiles.size()):
		if typeof(raw_tiles[index]) != TYPE_DICTIONARY:
			return null
		var entry := raw_tiles[index] as Dictionary
		if not _has_exact_keys(entry, VIEWER_WALL_TOP_ENTRY_KEYS) \
				or typeof(entry["offset"]) != TYPE_INT or int(entry["offset"]) != index:
			return null
		var tile: Variant = ProtocolViewCodec.tile_view_from_dict(entry["tile"])
		if tile == null:
			return null
		var iid := int((tile as Dictionary)["instance_id"])
		if seen.has(iid) or not _is_instance_id_in_hand_namespace(iid, hand_seq):
			return null
		seen[iid] = true
		tiles_out.append({"offset": index, "tile": tile})
	return {
		"recipient_seat": int(recipient),
		"hand_seq": hand_seq,
		"tiles": tiles_out,
	}


static func _validate_viewer_seat_draw_forecast(
	p: Dictionary, seat_view: int, core_hand_seq: int
) -> Variant:
	if not _has_exact_keys(p, VIEWER_SEAT_DRAW_FORECAST_KEYS):
		return null
	var recipient: Variant = _require_seat(p["recipient_seat"])
	if recipient == null or int(recipient) != seat_view:
		return null
	if typeof(p["hand_seq"]) != TYPE_INT:
		return null
	var hand_seq := int(p["hand_seq"])
	if hand_seq < 0 or hand_seq != core_hand_seq or typeof(p["predictions"]) != TYPE_ARRAY:
		return null
	var rows := p["predictions"] as Array
	if rows.is_empty() or rows.size() > 4:
		return null
	var targets: Dictionary = {}
	var instances: Dictionary = {}
	var out: Array = []
	for value in rows:
		if typeof(value) != TYPE_DICTIONARY:
			return null
		var row := value as Dictionary
		if not _has_exact_keys(row, VIEWER_SEAT_DRAW_FORECAST_ROW_KEYS):
			return null
		var target: Variant = _require_seat(row["target_seat"])
		if target == null or targets.has(int(target)):
			return null
		var tile: Variant = ProtocolViewCodec.tile_view_from_dict(row["tile"])
		if tile == null:
			return null
		var iid := int((tile as Dictionary)["instance_id"])
		if instances.has(iid) or not _is_instance_id_in_hand_namespace(iid, hand_seq):
			return null
		targets[int(target)] = true
		instances[iid] = true
		out.append({"target_seat": int(target), "tile": tile})
	return {
		"recipient_seat": int(recipient),
		"hand_seq": hand_seq,
		"predictions": out,
	}


static func _validate_seat_view(
	p: Dictionary,
	expect_seat: int,
	recipient: int,
	hand_seq: int
) -> Variant:
	if not _has_exact_keys(p, SEAT_VIEW_KEYS):
		return null

	var seat: Variant = _require_seat(p["seat"])
	if seat == null:
		return null
	var seat_i: int = seat
	if seat_i != expect_seat:
		return null

	if typeof(p["seat_wind"]) != TYPE_INT:
		return null
	var wind: int = p["seat_wind"]
	if wind not in SEAT_WINDS:
		return null

	var score: Variant = _require_safe_int(p["score"])
	if score == null:
		return null

	if typeof(p["concealed_tiles"]) != TYPE_ARRAY:
		return null
	var ct_out: Array = []
	var ct_ids: Dictionary = {}
	for item in p["concealed_tiles"]:
		var tv: Variant = ProtocolViewCodec.tile_view_from_dict(item)
		if tv == null:
			return null
		var td: Dictionary = tv
		var iid: int = td["instance_id"]
		if not _is_instance_id_in_hand_namespace(iid, hand_seq):
			return null
		if ct_ids.has(iid):
			return null
		ct_ids[iid] = true
		ct_out.append(td)

	var ccount: Variant = _require_nonneg_safe_int(p["concealed_count"])
	if ccount == null:
		return null
	var ccount_i: int = ccount
	if ccount_i > CONCEALED_COUNT_MAX:
		return null

	if typeof(p["last_drawn_tile_instance_id"]) != TYPE_INT:
		return null
	var last_drawn: int = p["last_drawn_tile_instance_id"]
	if last_drawn < -1 or last_drawn > ProtocolConstants.MAX_SAFE_INT:
		return null

	if seat_i == recipient:
		if ct_out.size() != ccount_i:
			return null
		# last_drawn 是 concealed 内引用，不重复计数
		if last_drawn >= 0 and not ct_ids.has(last_drawn):
			return null
	else:
		# 信息能力允许服务端向 recipient 投影对手手牌的可见子集；权限由
		# RecipientViewProjector 决定。wire 层只接受不超过真实手牌张数的子集。
		if ct_out.size() > ccount_i:
			return null
		if last_drawn != -1:
			return null

	if typeof(p["river"]) != TYPE_ARRAY:
		return null
	if (p["river"] as Array).size() > RIVER_SIZE_MAX:
		return null
	var river_out: Array = []
	for item in p["river"]:
		var rtv: Variant = ProtocolViewCodec.tile_view_from_dict(item)
		if rtv == null:
			return null
		var rtd: Dictionary = rtv
		if not _is_instance_id_in_hand_namespace(int(rtd["instance_id"]), hand_seq):
			return null
		river_out.append(rtd)

	if typeof(p["melds"]) != TYPE_ARRAY:
		return null
	if (p["melds"] as Array).size() > MELDS_SIZE_MAX:
		return null
	var melds_out: Array = []
	var meld_ids_seen: Dictionary = {}
	for item in p["melds"]:
		var mv: Variant = ProtocolViewCodec.meld_view_from_dict(item)
		if mv == null:
			return null
		var md: Dictionary = mv
		# 同席 meld_id 唯一（全局唯一在 core_table 再检）
		var meld_id: int = int(md["meld_id"])
		if meld_ids_seen.has(meld_id):
			return null
		meld_ids_seen[meld_id] = true
		# from_seat 相对持有席：ANKAN=-1；CHI/PON/MINKAN/ADDED_KAN 不得等于 holder
		# CHI 必须来自上家 (holder+3)%4
		if not _meld_from_seat_rules(md, seat_i):
			return null
		# tiles 全量 namespace；called/added 仅为 tiles 内引用
		if not _meld_tiles_in_hand_namespace(md, hand_seq):
			return null
		melds_out.append(md)

	if typeof(p["riichi_declared"]) != TYPE_BOOL:
		return null
	var declared: bool = p["riichi_declared"]
	if typeof(p["riichi_double"]) != TYPE_BOOL:
		return null
	var double_r: bool = p["riichi_double"]
	if double_r and not declared:
		return null

	if typeof(p["riichi_discard_index"]) != TYPE_INT:
		return null
	var ridx: int = p["riichi_discard_index"]
	if not declared:
		if ridx != -1:
			return null
	else:
		# 宣言牌被鸣走时允许 -1；>=0 须落在河内
		if ridx == -1:
			pass
		elif ridx < 0 or ridx >= river_out.size():
			return null

	return {
		"seat": seat_i,
		"seat_wind": wind,
		"score": int(score),
		"concealed_tiles": ct_out,
		"concealed_count": ccount_i,
		"last_drawn_tile_instance_id": last_drawn,
		"river": river_out,
		"melds": melds_out,
		"riichi_declared": declared,
		"riichi_double": double_r,
		"riichi_discard_index": ridx,
	}


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

static func _validate_player_joined(p: Dictionary) -> Variant:
	if not _has_exact_keys(p, PLAYER_JOINED_KEYS):
		return null
	var seat: Variant = _require_seat(p["seat"])
	if seat == null:
		return null
	if typeof(p["participant_kind"]) != TYPE_STRING:
		return null
	var participant_kind: String = p["participant_kind"]
	if participant_kind not in PARTICIPANT_KINDS:
		return null
	if typeof(p["display_name"]) != TYPE_STRING:
		return null
	var name: String = p["display_name"]
	if name.strip_edges().is_empty():
		return null
	if name != name.strip_edges():
		return null
	if typeof(p["connected"]) != TYPE_BOOL:
		return null
	return {
		"seat": int(seat),
		"participant_kind": participant_kind,
		"display_name": name,
		"connected": bool(p["connected"]),
	}


static func _validate_hand_settled(p: Dictionary) -> Variant:
	if not _has_exact_keys(p, HAND_SETTLED_KEYS):
		return null

	if typeof(p["hand_seq"]) != TYPE_INT:
		return null
	var hs: int = p["hand_seq"]
	if hs < 0 or hs > ProtocolConstants.MAX_HAND_SEQ:
		return null

	if typeof(p["outcome"]) != TYPE_STRING:
		return null
	var outcome: String = p["outcome"]
	if outcome not in HAND_OUTCOMES:
		return null

	if typeof(p["winner_seats"]) != TYPE_ARRAY:
		return null
	var winners_raw: Array = p["winner_seats"]
	var winners: Array = []
	var prev := -1
	var seen_w: Dictionary = {}
	for w in winners_raw:
		if typeof(w) != TYPE_INT:
			return null
		var wi: int = w
		if wi < 0 or wi > 3:
			return null
		if seen_w.has(wi):
			return null
		seen_w[wi] = true
		# 输入必须已升序
		if prev >= 0 and wi <= prev:
			return null
		prev = wi
		winners.append(wi)

	if typeof(p["loser_seat"]) != TYPE_INT:
		return null
	var loser: int = p["loser_seat"]
	if loser < -1 or loser > 3:
		return null

	match outcome:
		"RON":
			# 协议：RON 恰好单 winner（不支持多响）
			if winners.size() != 1:
				return null
			if loser < 0 or loser > 3:
				return null
			if seen_w.has(loser):
				return null
		"TSUMO":
			if winners.size() != 1:
				return null
			if loser != -1:
				return null
		"EXHAUSTIVE_DRAW", "ABORTIVE_DRAW":
			if not winners.is_empty():
				return null
			if loser != -1:
				return null
		_:
			return null

	# A 契约：score_deltas = 本局最终分 - 本局起始分。
	# 局前桌上立直棒进入赢家分数时局内 delta 和可合法非零，禁止静态 sum==0。
	var deltas: Variant = _validate_four_safe_ints(p["score_deltas"])
	if deltas == null:
		return null

	var scores: Variant = _validate_four_safe_ints(p["scores"])
	if scores == null:
		return null

	return {
		"hand_seq": hs,
		"outcome": outcome,
		"winner_seats": winners,
		"loser_seat": loser,
		"score_deltas": deltas,
		"scores": scores,
	}


static func _validate_match_settled(p: Dictionary) -> Variant:
	if not _has_exact_keys(p, MATCH_SETTLED_KEYS):
		return null
	if typeof(p["round_kind"]) != TYPE_STRING:
		return null
	var rk: String = p["round_kind"]
	if rk not in MATCH_ROUND_KINDS:
		return null
	var finals: Variant = _validate_four_safe_ints(p["final_scores"])
	if finals == null:
		return null
	if typeof(p["seat_order"]) != TYPE_ARRAY:
		return null
	var order_raw: Array = p["seat_order"]
	if order_raw.size() != 4:
		return null
	var order: Array = []
	var seen: Dictionary = {}
	for s in order_raw:
		if typeof(s) != TYPE_INT:
			return null
		var si: int = s
		if si < 0 or si > 3:
			return null
		if seen.has(si):
			return null
		seen[si] = true
		order.append(si)
	if seen.size() != 4:
		return null
	# seat_order 必须恰好按 final_scores 降序；同分 seat 数字升序。拒绝不合顺序，不静默重排。
	var finals_arr: Array = finals as Array
	for i in range(order.size() - 1):
		var a: int = int(order[i])
		var b: int = int(order[i + 1])
		var sa: int = int(finals_arr[a])
		var sb: int = int(finals_arr[b])
		if sa < sb:
			return null
		if sa == sb and a > b:
			return null
	return {
		"round_kind": rk,
		"final_scores": finals,
		"seat_order": order,
	}


static func _validate_four_safe_ints(raw: Variant) -> Variant:
	if typeof(raw) != TYPE_ARRAY:
		return null
	var arr: Array = raw
	if arr.size() != 4:
		return null
	var out: Array = []
	for v in arr:
		var n: Variant = _require_safe_int(v)
		if n == null:
			return null
		out.append(int(n))
	return out


func describe() -> String:
	return "NetEv[seq=%d kind=%s room=%s]" % [server_seq, kind, room_id]
