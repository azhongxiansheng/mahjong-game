extends GutTest

# E2-02（#232）Red：NetworkedEvent 扁平包络 + 强制 view_hash。
# exact envelope：protocol_version / server_seq / room_id / kind / payload / view_hash
# 任何层不得出现 state_hash / full_state_hash。
# ACTION_APPLIED 是已解析权威结果（resolved_payload 实体），禁止命令回显。

const ROOM := "room_x"
const NE_SCRIPT := "res://protocol/networked_event.gd"
const UUID_OK := "550e8400-e29b-41d4-a716-446655440000"
const DECISION := "550e8400-e29b-41d4-a716-4466554400aa"
const VIEW_HASH := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
const MAX_HAND_SEQ := 66229406284859
const MAX_SAFE_INT := 9007199254740991
const TILES_PER_HAND := 136

const ENVELOPE_KEYS := [
	"protocol_version", "server_seq", "room_id", "kind", "payload", "view_hash",
]
const FORBIDDEN_HASH_KEYS := ["state_hash", "full_state_hash"]

# PASS 合法（只投影提交者；Protocol 只验证合法，不表达广播）
const ACTION_APPLIED_KINDS := [
	"DISCARD", "CHI", "PON", "KAN", "RIICHI", "RON", "TSUMO", "PASS", "DECLARE_ABORTIVE_DRAW",
]
const REJECTED_ACTION_KINDS := [
	"ITEM_USE", "JOIN", "READY", "RESYNC_REQUEST", "DRAW", "PASS_CLAIM", "UNKNOWN",
]


## 跨局 instance_id：hand_seq*136 + serial(0..135)
func _ns(hand_seq: int, serial: int) -> int:
	return hand_seq * TILES_PER_HAND + serial


## Wall canonical：serial=iid%136 → tile=ALL[serial/4]、owner=serial%4、W5/T5/S5 copy0 赤
func _canonical_tile_view_for_iid(iid: int) -> Dictionary:
	var serial: int = iid % TILES_PER_HAND
	@warning_ignore("integer_division")
	var tile_index: int = serial / 4
	var tile_id: int = TileId.ALL[tile_index]
	var owner_seat: int = serial % 4
	var is_red: bool = (
		owner_seat == 0
		and (tile_id == TileId.W5 or tile_id == TileId.T5 or tile_id == TileId.S5)
	)
	return {
		"instance_id": iid,
		"tile_id": tile_id,
		"is_red_dora": is_red,
		"owner_seat": owner_seat,
	}


## iid = ALL.find(tile_id)*4 + copy_index + hand_seq*136
func _canonical_tile_view(
	tile_id: int,
	copy_index: int,
	hand_seq: int = 0
) -> Dictionary:
	var idx: int = TileId.ALL.find(tile_id)
	var iid: int = idx * 4 + copy_index + hand_seq * TILES_PER_HAND
	return _canonical_tile_view_for_iid(iid)


## 合法 TileView：仅由 iid 推导 identity（忽略其它参数，兼容旧调用点）。
## 故意非法负例请直接构造 raw dict，勿走本 helper。
func _tile_view(
	instance_id: int = 10,
	_tile_id: int = TileId.W5,
	_is_red: bool = false,
	_owner_seat: int = 0
) -> Dictionary:
	return _canonical_tile_view_for_iid(instance_id)


## called_serial 仅用于选合法 tile type（serial/4 → ALL）；不伪造 tid/red/owner。
## tiles 非空时原样使用（调用方负责 canonical + called/added 引用）。
func _meld_view(
	kind: String = "PON",
	meld_id: int = 0,
	from_seat: int = 2,
	called: int = 30,
	added: int = -1,
	tiles: Array = [],
	hand_seq: int = 0
) -> Dictionary:
	if not tiles.is_empty():
		return {
			"meld_id": meld_id,
			"kind": kind,
			"from_seat": from_seat,
			"called_tile_instance_id": called,
			"added_tile_instance_id": added,
			"tiles": tiles.duplicate(true),
		}
	return _meld_view_ns(hand_seq, kind, meld_id, from_seat, called % TILES_PER_HAND, added % TILES_PER_HAND if added >= 0 else 40)


func _resolved_for(action_kind: String, seat: int = 0, hand_seq: int = 0) -> Dictionary:
	# 鸣牌 from_seat 默认取 != actor seat（ANKAN 仍为 -1）；实体 id 落在 hand_seq 命名空间
	var other: int = (seat + 1) % 4
	match action_kind:
		"DISCARD", "RIICHI":
			return {
				"tile": _canonical_tile_view(TileId.W5, seat % 4, hand_seq),
				"discard_source": "DRAWN",
			}
		"CHI":
			return {"meld": _meld_view_ns(hand_seq, "CHI", 0, other)}
		"PON":
			return {"meld": _meld_view_ns(hand_seq, "PON", 0, other)}
		"KAN":
			return {"meld": _meld_view_ns(hand_seq, "MINKAN", 0, other)}
		"RON":
			return {
				"winning_tile": _canonical_tile_view(TileId.S5, other % 4, hand_seq),
				"from_seat": other,
			}
		"TSUMO":
			return {
				"winning_tile": _canonical_tile_view(TileId.S5, seat % 4, hand_seq),
			}
		"PASS":
			return {}
		"DECLARE_ABORTIVE_DRAW":
			return {"reason": "KYUUSYU_KYUUHAI"}
		_:
			return {}


## 默认 meld tiles 落在 hand_seq 命名空间；CHI 同花连续；PON/KAN 同牌不同 copies
func _meld_view_ns(
	hand_seq: int,
	kind: String = "PON",
	meld_id: int = 0,
	from_seat: int = 2,
	called_serial: int = 30,
	_added_serial: int = 40
) -> Dictionary:
	var tiles: Array = []
	var called: int = -1
	var added: int = -1
	var fs: int = from_seat
	@warning_ignore("integer_division")
	var type_index: int = (called_serial % TILES_PER_HAND) / 4
	if type_index < 0 or type_index >= TileId.ALL.size():
		type_index = 0
	var type_tid: int = TileId.ALL[type_index]

	if kind == "ANKAN":
		fs = -1
		called = -1
		added = -1
		for o in range(4):
			tiles.append(_canonical_tile_view(type_tid, o, hand_seq))
	elif kind == "CHI":
		# 同花连续升序；called 为序列第三张且 owner=from_seat
		var called_tid: int = TileId.W4
		var a_tid: int = TileId.W2
		var b_tid: int = TileId.W3
		if (
			not TileId.is_honor(type_tid)
			and TileId.number(type_tid) >= 3
			and TileId.number(type_tid) <= 9
		):
			called_tid = type_tid
			a_tid = type_tid - 2
			b_tid = type_tid - 1
		var hold_copy: int = 0 if fs != 0 else 1
		var t_a: Dictionary = _canonical_tile_view(a_tid, hold_copy, hand_seq)
		var t_b: Dictionary = _canonical_tile_view(b_tid, hold_copy, hand_seq)
		var t_called: Dictionary = _canonical_tile_view(called_tid, fs, hand_seq)
		called = int(t_called["instance_id"])
		tiles = [t_a, t_b, t_called]
	elif kind == "MINKAN":
		var t_called_mk: Dictionary = _canonical_tile_view(type_tid, fs, hand_seq)
		called = int(t_called_mk["instance_id"])
		for o in range(4):
			if o == fs:
				continue
			tiles.append(_canonical_tile_view(type_tid, o, hand_seq))
		tiles.append(t_called_mk)
	elif kind == "ADDED_KAN":
		var added_copy: int = 3 if fs != 3 else 1
		var t_called_ak: Dictionary = _canonical_tile_view(type_tid, fs, hand_seq)
		var t_added: Dictionary = _canonical_tile_view(type_tid, added_copy, hand_seq)
		called = int(t_called_ak["instance_id"])
		added = int(t_added["instance_id"])
		for o in range(4):
			if o == fs or o == added_copy:
				continue
			tiles.append(_canonical_tile_view(type_tid, o, hand_seq))
		tiles.append(t_called_ak)
		tiles.append(t_added)
	else:
		# PON：同 tile 三 copies；called=from 成员
		var t_called_pn: Dictionary = _canonical_tile_view(type_tid, fs, hand_seq)
		called = int(t_called_pn["instance_id"])
		var picked := 0
		for o in range(4):
			if o == fs:
				continue
			tiles.append(_canonical_tile_view(type_tid, o, hand_seq))
			picked += 1
			if picked == 2:
				break
		tiles.append(t_called_pn)

	return {
		"meld_id": meld_id,
		"kind": kind,
		"from_seat": fs,
		"called_tile_instance_id": called,
		"added_tile_instance_id": added,
		"tiles": tiles,
	}


func _action_applied_payload(
	action_kind: String,
	resolved: Variant = null,
	seat: int = 0,
	hand_seq: int = 0
) -> Dictionary:
	# null → 默认 resolved；显式 {} / Dictionary 原样保留（含 PASS 空 dict）
	var rp: Dictionary
	if resolved == null:
		rp = _resolved_for(action_kind, seat, hand_seq)
	else:
		assert(typeof(resolved) == TYPE_DICTIONARY, "resolved 必须 Dictionary 或 null")
		rp = (resolved as Dictionary).duplicate(true)
	return {
		"causation_command_id": UUID_OK,
		"hand_seq": hand_seq,
		"decision_id": DECISION,
		"seat": seat,
		"action_kind": action_kind,
		"resolved_payload": rp.duplicate(true),
	}


func _flat_event(
	kind: String,
	server_seq: int = 1,
	payload: Dictionary = {},
	view_hash: String = VIEW_HASH
) -> Dictionary:
	return {
		"protocol_version": 1,
		"server_seq": server_seq,
		"room_id": ROOM,
		"kind": kind,
		"payload": payload.duplicate(true),
		"view_hash": view_hash,
	}


## 完整四键 ROOM_SNAPSHOT payload 的 view_hash（模块化唯一口径）。
## 仅 snapshot 要求 envelope.view_hash == 自身完整 payload hash；其它 event 的
## view_hash 是 action 后 recipient snapshot hash，不能与自身 payload 比较。
## 非法 hash domain 算不出时用 VIEW_HASH 保 envelope 格式，由 payload validator 拒绝。
func _snapshot_view_hash(payload: Dictionary) -> String:
	return ProtocolViewCodec.compute_view_hash(payload)


func _room_snapshot_event(
	server_seq: int,
	payload: Dictionary,
	view_hash: String = ""
) -> Dictionary:
	var p: Dictionary = payload.duplicate(true)
	var vh: String = view_hash
	if vh.is_empty():
		vh = _snapshot_view_hash(p)
		if vh.is_empty():
			vh = VIEW_HASH
	return _flat_event("ROOM_SNAPSHOT", server_seq, p, vh)


## MeldView 全数组保序：输入/领域顺序即输出顺序（不再按 instance_id 排序）。
## 仅 deep-copy 作为 fixture；校验由 NetworkedEvent / codec 自身负责。
func _order_preserving_meld_view(raw: Dictionary) -> Dictionary:
	return raw.duplicate(true)


## TURN_PROMPT 私有 schema 最小合法 payload（#232 strict；详见 test_decision_window_protocol）
func _turn_prompt_payload(seat: int = 1, hand_seq: int = 0) -> Dictionary:
	var iid: int = _ns(hand_seq, 10)
	return {
		"hand_seq": hand_seq,
		"decision_id": DECISION,
		"seat": seat,
		"hand": [_tile_view(iid, TileId.W5, false, seat)],
		"last_drawn_tile_instance_id": -1,
		"allowed_actions": [{
			"kind": "DISCARD",
			"payload_options": [{"tile_instance_id": iid}],
		}],
	}


## CLAIM_WINDOW 私有 schema 最小合法 payload（每 recipient 仅自己的 offers，至少 PASS）
func _claim_window_payload(discarded_by_seat: int = 0, hand_seq: int = 0) -> Dictionary:
	return {
		"hand_seq": hand_seq,
		"decision_id": DECISION,
		"discarded_by_seat": discarded_by_seat,
		"discarded_tile": _tile_view(_ns(hand_seq, 50), TileId.W5, false, discarded_by_seat),
		"allowed_actions": [{
			"kind": "PASS",
			"payload_options": [{}],
		}],
	}


# ---- recipient DTO fixtures（模块化 ROOM_SNAPSHOT / PLAYER_JOINED / HAND_SETTLED / MATCH_SETTLED）----

# ROOM_SNAPSHOT.payload exact 4 键（禁止 flat 12 键顶层）
const ROOM_SNAPSHOT_TOP_KEYS := [
	"snapshot_server_seq", "next_server_seq", "seat_view", "modules",
]
const MODULE_ENTRY_KEYS := ["module_key", "schema_version", "payload"]
# core_table.payload exact 12 键
const CORE_TABLE_KEYS := [
	"recipient_seat", "hand_seq", "dealer_seat", "current_seat", "phase",
	"round_wind", "hand_number", "honba", "riichi_sticks", "live_wall_count",
	"dora_indicators", "seats",
]
# SeatView exact 11 键（含 riichi_double）
const SEAT_VIEW_KEYS := [
	"seat", "seat_wind", "score", "concealed_tiles", "concealed_count",
	"last_drawn_tile_instance_id", "river", "melds", "riichi_declared",
	"riichi_double", "riichi_discard_index",
]
const PLAYER_JOINED_KEYS := ["seat", "participant_kind", "display_name", "connected"]
const HAND_SETTLED_KEYS := [
	"hand_seq", "outcome", "winner_seats", "loser_seat", "score_deltas", "scores",
	"dealer_seat", "renchan", "honba", "riichi_sticks", "adjustments",
]
const MATCH_SETTLED_KEYS := ["round_kind", "final_scores", "seat_order"]
const SNAPSHOT_PHASES := ["DRAW", "DISCARD", "CLAIM", "SETTLE"]
const SEAT_WINDS := [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N]


func _seat_view(
	seat: int,
	seat_wind: int,
	score: int = 25000,
	concealed_count: int = 0,
	concealed_tiles: Array = [],
	last_drawn: int = -1,
	melds: Array = [],
	river: Array = [],
	riichi_declared: bool = false,
	riichi_double: bool = false,
	riichi_discard_index: int = -1
) -> Dictionary:
	return {
		"seat": seat,
		"seat_wind": seat_wind,
		"score": score,
		"concealed_tiles": concealed_tiles.duplicate(true),
		"concealed_count": concealed_count,
		"last_drawn_tile_instance_id": last_drawn,
		"river": river.duplicate(true),
		"melds": melds.duplicate(true),
		"riichi_declared": riichi_declared,
		"riichi_double": riichi_double,
		"riichi_discard_index": riichi_discard_index,
	}


func _default_seats(recipient_seat: int = 0, hand_seq: int = 0) -> Array:
	# 四席 seat 顺序 0..3；风位 E/S/W/N 不重复；仅 recipient 公开手牌；实体落在 hand_seq 命名空间
	var seats: Array = []
	for i in range(4):
		if i == recipient_seat:
			var tiles: Array = [
				_tile_view(_ns(hand_seq, 10), TileId.W1, false, i),
				_tile_view(_ns(hand_seq, 11), TileId.W2, false, i),
			]
			seats.append(_seat_view(
				i, SEAT_WINDS[i], 25000, 2, tiles, -1, [], [], false, false, -1
			))
		else:
			seats.append(_seat_view(
				i, SEAT_WINDS[i], 25000, 13, [], -1, [], [], false, false, -1
			))
	return seats


## core_table.payload exact 12 键 fixture（非 ROOM_SNAPSHOT 顶层）。
func _core_table_payload(
	recipient_seat: int = 0,
	hand_seq: int = 0,
	phase: String = "DRAW",
	seats: Array = [],
	dora: Array = []
) -> Dictionary:
	var seat_list: Array = seats
	if seat_list.is_empty():
		seat_list = _default_seats(recipient_seat, hand_seq)
	var dora_list: Array = dora
	if dora_list.is_empty():
		dora_list = [_tile_view(_ns(hand_seq, 1), TileId.W5, false, -1)]
	return {
		"recipient_seat": recipient_seat,
		"hand_seq": hand_seq,
		"dealer_seat": 0,
		"current_seat": 0,
		"phase": phase,
		"round_wind": TileId.E,
		"hand_number": 1,
		"honba": 0,
		"riichi_sticks": 0,
		"live_wall_count": 70,
		"dora_indicators": dora_list.duplicate(true),
		"seats": seat_list.duplicate(true),
	}


func _module_entry(module_key: String, schema_version: int, payload: Variant) -> Dictionary:
	var p: Variant = payload
	if typeof(payload) == TYPE_DICTIONARY:
		p = (payload as Dictionary).duplicate(true)
	elif typeof(payload) == TYPE_ARRAY:
		p = (payload as Array).duplicate(true)
	return {
		"module_key": module_key,
		"schema_version": schema_version,
		"payload": p,
	}


func _core_module(core: Dictionary = {}) -> Dictionary:
	var body: Dictionary = core
	if body.is_empty():
		body = _core_table_payload(0)
	return _module_entry("core_table", 1, body)


## 模块化 ROOM_SNAPSHOT.payload exact 4 键。
## modules 须已按 module_key 升序；默认仅 core_table。
func _room_snapshot_payload(
	snapshot_server_seq: int = 1,
	seat_view: int = 0,
	modules: Array = []
) -> Dictionary:
	var mods: Array = modules
	if mods.is_empty():
		mods = [_core_module(_core_table_payload(seat_view))]
	return {
		"snapshot_server_seq": snapshot_server_seq,
		"next_server_seq": snapshot_server_seq + 1,
		"seat_view": seat_view,
		"modules": mods.duplicate(true),
	}


func _core_from_snapshot(payload: Dictionary) -> Dictionary:
	var modules: Array = payload.get("modules", []) as Array
	for m in modules:
		if typeof(m) != TYPE_DICTIONARY:
			continue
		if str((m as Dictionary).get("module_key", "")) == "core_table":
			return ((m as Dictionary).get("payload", {}) as Dictionary).duplicate(true)
	return {}


func _player_joined_payload(
	seat: int = 0,
	kind: String = "HUMAN",
	display_name: String = "Player",
	connected: bool = true
) -> Dictionary:
	return {
		"seat": seat,
		"participant_kind": kind,
		"display_name": display_name,
		"connected": connected,
	}


func _hand_settled_payload(
	outcome: String = "TSUMO",
	winner_seats: Array = [0],
	loser_seat: int = -1,
	score_deltas: Array = [3000, -1000, -1000, -1000],
	scores: Array = [28000, 24000, 24000, 24000],
	hand_seq: int = 0,
	dealer_seat: int = 0,
	renchan: bool = false,
	honba: int = 0,
	riichi_sticks: int = 0,
	adjustments: Array = []
) -> Dictionary:
	return {
		"hand_seq": hand_seq,
		"outcome": outcome,
		"winner_seats": winner_seats.duplicate(),
		"loser_seat": loser_seat,
		"score_deltas": score_deltas.duplicate(),
		"scores": scores.duplicate(),
		"dealer_seat": dealer_seat,
		"renchan": renchan,
		"honba": honba,
		"riichi_sticks": riichi_sticks,
		"adjustments": adjustments.duplicate(true),
	}


func _match_settled_payload(
	round_kind: String = "EAST",
	final_scores: Array = [30000, 25000, 25000, 20000],
	seat_order: Array = [0, 1, 2, 3]
) -> Dictionary:
	return {
		"round_kind": round_kind,
		"final_scores": final_scores.duplicate(),
		"seat_order": seat_order.duplicate(),
	}


func _exact_keys(d: Dictionary, expected: Array) -> bool:
	if d.keys().size() != expected.size():
		return false
	for k in expected:
		if not d.has(k):
			return false
	return true


func _assert_flat_envelope(d: Dictionary, kind: String, seq: int) -> void:
	assert_true(_exact_keys(d, ENVELOPE_KEYS), "envelope exact 六键")
	assert_eq(int(d.get("protocol_version", -1)), 1)
	assert_eq(typeof(d.get("server_seq")), TYPE_INT)
	assert_eq(int(d.get("server_seq", -1)), seq)
	# 业务事件 server_seq exact int 1..MAX_SAFE（0 与 MAX_SAFE+1 拒绝）
	assert_true(int(d["server_seq"]) >= 1 and int(d["server_seq"]) <= MAX_SAFE_INT,
		"业务事件 server_seq 1..MAX_SAFE")
	assert_eq(typeof(d.get("room_id")), TYPE_STRING)
	assert_eq(str(d.get("room_id", "")), ROOM)
	assert_eq(typeof(d.get("kind")), TYPE_STRING)
	assert_eq(str(d.get("kind")), kind)
	assert_eq(typeof(d.get("payload")), TYPE_DICTIONARY)
	assert_eq(typeof(d.get("view_hash")), TYPE_STRING)
	assert_eq(str(d.get("view_hash")).length(), 64)
	assert_eq(str(d.get("view_hash")), str(d.get("view_hash")).to_lower())
	assert_false(d.has("server_ts_ms"))
	assert_false(d.has("causing_action_id"))
	assert_false(d.has("event"))
	for forbidden in FORBIDDEN_HASH_KEYS:
		assert_false(d.has(forbidden), "公开 DTO 不得出现 %s" % forbidden)


func _script_has_static(method_name: String) -> bool:
	var script: GDScript = load(NE_SCRIPT) as GDScript
	if script == null:
		return false
	for m in script.get_script_method_list():
		if str(m.get("name", "")) == method_name:
			return true
	return false


func _is_lowercase_hex64(s: String) -> bool:
	if s.length() != 64:
		return false
	if s != s.to_lower():
		return false
	var re := RegEx.new()
	re.compile("^[0-9a-f]{64}$")
	return re.search(s) != null


# ---- 扁平构造与 round-trip ----

func test_flat_server_event_roundtrip_requires_view_hash() -> void:
	var wire := _flat_event("ACTION_APPLIED", 42, _action_applied_payload("DISCARD"))
	var ne: NetworkedEvent = NetworkedEvent.from_dict(wire)
	assert_not_null(ne, "扁平 ServerEvent + view_hash 应解析")
	if ne == null:
		return
	assert_eq(ne.server_seq, 42)
	var out: Dictionary = ne.to_dict()
	_assert_flat_envelope(out, "ACTION_APPLIED", 42)
	assert_eq(str(out.get("view_hash")), VIEW_HASH)
	assert_true(_is_lowercase_hex64(str(out.get("view_hash"))))

	var ne2: NetworkedEvent = NetworkedEvent.from_dict(out)
	assert_not_null(ne2)
	if ne2 != null:
		_assert_flat_envelope(ne2.to_dict(), "ACTION_APPLIED", 42)


func test_view_hash_required_and_must_be_sha256_hex() -> void:
	var base := _flat_event("TURN_PROMPT", 5, _turn_prompt_payload(1))
	assert_not_null(NetworkedEvent.from_dict(base), "合法 view_hash 应通过")

	var missing := base.duplicate(true)
	missing.erase("view_hash")
	assert_null(NetworkedEvent.from_dict(missing), "缺 view_hash 拒绝")

	var bad_len := base.duplicate(true)
	bad_len["view_hash"] = "abc"
	assert_null(NetworkedEvent.from_dict(bad_len), "非 64 位拒绝")

	var upper := base.duplicate(true)
	upper["view_hash"] = VIEW_HASH.to_upper()
	assert_null(NetworkedEvent.from_dict(upper), "大写 hex 拒绝")

	var non_hex := base.duplicate(true)
	non_hex["view_hash"] = "g" + VIEW_HASH.substr(1)
	assert_null(NetworkedEvent.from_dict(non_hex), "非十六进制拒绝")

	var bad_type := base.duplicate(true)
	bad_type["view_hash"] = 123
	assert_null(NetworkedEvent.from_dict(bad_type), "view_hash 非 String 拒绝")


func test_state_hash_and_full_state_hash_forbidden_everywhere() -> void:
	# 使用完整 HAND_SETTLED recipient DTO（非 arbitrary dict）
	var base := _flat_event("HAND_SETTLED", 9, _hand_settled_payload())
	for forbidden in FORBIDDEN_HASH_KEYS:
		var bad := base.duplicate(true)
		bad[forbidden] = VIEW_HASH
		assert_null(
			NetworkedEvent.from_dict(bad),
			"envelope 含 %s 必须拒绝" % forbidden
		)

	var with_payload_hash := base.duplicate(true)
	var p: Dictionary = (with_payload_hash["payload"] as Dictionary).duplicate(true)
	p["state_hash"] = VIEW_HASH
	with_payload_hash["payload"] = p
	# payload exact 的 kind 会因多余键失败；不得把旧 hash 当契约
	assert_null(
		NetworkedEvent.from_dict(with_payload_hash),
		"payload 内 state_hash 不得作为合法契约字段"
	)

	var ne: NetworkedEvent = NetworkedEvent.from_dict(base)
	assert_not_null(ne)
	if ne != null:
		var out: Dictionary = ne.to_dict()
		for forbidden in FORBIDDEN_HASH_KEYS:
			assert_false(out.has(forbidden), "to_dict 不得发射 %s" % forbidden)


func test_all_business_events_require_server_seq_ge_1() -> void:
	for kind in [
		"ACTION_APPLIED",
		"TURN_PROMPT",
		"CLAIM_WINDOW",
		"HAND_SETTLED",
		"MATCH_SETTLED",
		"REWARD_WINDOW_OPENED",
	]:
		var payload: Dictionary = {}
		if kind == "ACTION_APPLIED":
			payload = _action_applied_payload("DISCARD")
		elif kind == "TURN_PROMPT":
			payload = _turn_prompt_payload(1)
		elif kind == "CLAIM_WINDOW":
			payload = _claim_window_payload(0)
		elif kind == "HAND_SETTLED":
			payload = _hand_settled_payload()
		elif kind == "MATCH_SETTLED":
			payload = _match_settled_payload()
		elif kind.begins_with("REWARD"):
			payload = {
				"window_id": "w1",
				"hand_seq": 1,
				"window_index": 0,
				"prize_pool": ["a", "b", "c", "d"],
				"rule_version": "rv",
				"phase": "OPEN",
				"window_exit": null,
			}
		var zero := _flat_event(kind, 0, payload)
		assert_null(NetworkedEvent.from_dict(zero), "%s server_seq=0 拒绝" % kind)
		var over := _flat_event(kind, MAX_SAFE_INT + 1, payload)
		assert_null(NetworkedEvent.from_dict(over), "%s server_seq=MAX_SAFE+1 拒绝" % kind)

	# 上限合法：server_seq=MAX_SAFE
	var max_ok := _flat_event("TURN_PROMPT", MAX_SAFE_INT, _turn_prompt_payload(1))
	assert_not_null(NetworkedEvent.from_dict(max_ok), "server_seq=MAX_SAFE 合法")


func test_error_and_command_result_not_in_event_kinds() -> void:
	assert_false("ERROR" in NetworkedEvent.EVENT_KINDS, "EVENT_KINDS 不含 ERROR")
	assert_false(
		"COMMAND_RESULT" in NetworkedEvent.EVENT_KINDS,
		"EVENT_KINDS 不含 COMMAND_RESULT"
	)
	var as_event := _flat_event("ERROR", 1, {"code": "COMMAND_REJECTED", "message": "x"})
	assert_null(NetworkedEvent.from_dict(as_event), "ERROR 不得 from_dict 为业务事件")
	var as_cr := _flat_event("COMMAND_RESULT", 1, {
		"command_id": UUID_OK, "status": "ACCEPTED", "error_code": "",
	})
	assert_null(NetworkedEvent.from_dict(as_cr), "COMMAND_RESULT 不得作为业务事件 kind")

	var script: GDScript = load(NE_SCRIPT) as GDScript
	assert_not_null(script)
	assert_true(_script_has_static("make"), "保留 make 工厂")
	assert_false(_script_has_static("business"), "不得暴露 business")
	assert_false(_script_has_static("make_business"), "不得暴露 make_business")
	var built: Variant = script.call("make", "ERROR", 1, ROOM, {}, VIEW_HASH)
	assert_null(built, "make 不得构造 ERROR 业务事件")


func test_rejects_legacy_nested_battle_event_envelope() -> void:
	var legacy := {
		"server_seq": 100,
		"causing_action_id": 5,
		"server_ts_ms": 9999,
		"event": {
			"type": "WIN_DECLARED",
			"actor_seat": 0,
			"extra": {"han": 3, "fu": 30},
		},
	}
	assert_null(NetworkedEvent.from_dict(legacy), "旧嵌套 BattleEvent 信封拒绝")


func test_rejects_missing_extra_envelope_and_silent_coercion() -> void:
	assert_null(NetworkedEvent.from_dict({}))
	var full := _flat_event("ACTION_APPLIED", 3, _action_applied_payload("DISCARD"))
	for key in ENVELOPE_KEYS:
		var bad := full.duplicate(true)
		bad.erase(key)
		assert_null(NetworkedEvent.from_dict(bad), "缺 %s" % key)

	var extra := full.duplicate(true)
	extra["client_seq"] = 1
	assert_null(NetworkedEvent.from_dict(extra), "envelope 多余键拒绝")

	var bad_seq := full.duplicate(true)
	bad_seq["server_seq"] = "3"
	assert_null(NetworkedEvent.from_dict(bad_seq), "server_seq 不得 str 强转")

	var bad_kind := full.duplicate(true)
	bad_kind["kind"] = 1
	assert_null(NetworkedEvent.from_dict(bad_kind), "kind 不得 int")

	var bad_room := full.duplicate(true)
	bad_room["room_id"] = ""
	assert_null(NetworkedEvent.from_dict(bad_room), "room_id 非空")
	for bad_room_id in ["   ", " room_x", "room_x "]:
		var noncanonical_room := full.duplicate(true)
		noncanonical_room["room_id"] = bad_room_id
		assert_null(
			NetworkedEvent.from_dict(noncanonical_room),
			"room_id 必须非空且已去除首尾空白: %s" % JSON.stringify(bad_room_id)
		)

	var bad_pv := full.duplicate(true)
	bad_pv["protocol_version"] = "1"
	assert_null(NetworkedEvent.from_dict(bad_pv), "protocol_version 不得 str")

	var bad_payload := full.duplicate(true)
	bad_payload["payload"] = []
	assert_null(NetworkedEvent.from_dict(bad_payload), "payload 必须 Dictionary")


func test_rejects_unknown_kind() -> void:
	assert_null(NetworkedEvent.from_dict(_flat_event("NOT_AN_EVENT_KIND", 1, {})))
	assert_null(NetworkedEvent.from_dict(_flat_event("", 1, {})))


func test_payload_copy_on_read() -> void:
	var src_payload := _action_applied_payload("DISCARD", null, 1)
	# 捕获构造源 canonical iid，禁止硬编码（W5/seat 等会随 helper 变化）
	var expected_iid: int = int(
		((src_payload["resolved_payload"] as Dictionary)["tile"] as Dictionary)["instance_id"]
	)
	var wire := _flat_event("ACTION_APPLIED", 8, src_payload)
	var ne: NetworkedEvent = NetworkedEvent.from_dict(wire)
	assert_not_null(ne)
	if ne == null:
		return
	src_payload["seat"] = 99
	var nested: Dictionary = src_payload["resolved_payload"] as Dictionary
	if nested.has("tile"):
		(nested["tile"] as Dictionary)["instance_id"] = 0
	var out1: Dictionary = ne.to_dict()
	var p1: Dictionary = out1["payload"] as Dictionary
	assert_eq(int(p1.get("seat", -1)), 1, "from_dict 后改输入不得污染")
	var rp: Dictionary = p1.get("resolved_payload", {}) as Dictionary
	if rp.has("tile"):
		assert_eq(int((rp["tile"] as Dictionary).get("instance_id", -1)), expected_iid)

	p1["seat"] = 2
	var out2: Dictionary = ne.to_dict()
	assert_eq(int((out2["payload"] as Dictionary).get("seat", -1)), 1, "to_dict deep copy")


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


func test_networked_event_envelope_fields_reject_mutation() -> void:
	# 只读：反射冻结 @字段_getter 存在且 @字段_setter 不存在（Godot 4.6 命名）
	# 禁止 Object.set / 直接赋值攻击（生产缺 setter 时会 runtime error）
	var ne: NetworkedEvent = NetworkedEvent.from_dict(
		_flat_event("ACTION_APPLIED", 8, _action_applied_payload("DISCARD", null, 1))
	)
	assert_not_null(ne, "合法 ACTION_APPLIED 应解析")
	if ne == null:
		return
	var before: Dictionary = ne.to_dict().duplicate(true)

	var script: GDScript = load(NE_SCRIPT) as GDScript
	assert_not_null(script, "NetworkedEvent 脚本必须可加载")
	var method_names: Dictionary = {}
	for m in script.get_script_method_list():
		method_names[str(m.get("name", ""))] = true

	var fields: Array = [
		"protocol_version", "server_seq", "room_id", "kind", "view_hash", "payload",
	]
	for field in fields:
		var gname: String = "@%s_getter" % field
		var sname: String = "@%s_setter" % field
		assert_true(method_names.has(gname), "必须存在只读 getter %s" % gname)
		assert_false(method_names.has(sname), "不得存在 setter %s" % sname)

	var after: Dictionary = ne.to_dict()
	assert_eq(int(after["protocol_version"]), int(before["protocol_version"]))
	assert_eq(int(after["server_seq"]), int(before["server_seq"]))
	assert_eq(str(after["room_id"]), str(before["room_id"]))
	assert_eq(str(after["kind"]), str(before["kind"]))
	assert_eq(str(after["view_hash"]), str(before["view_hash"]))
	assert_eq(int((after["payload"] as Dictionary).get("seat", -1)), 1,
		"to_dict payload 保持原值")
	assert_eq(str((after["payload"] as Dictionary).get("action_kind", "")), "DISCARD")

	var exposed: Dictionary = ne.payload
	exposed["seat"] = 99
	assert_eq(int(ne.payload.get("seat", -1)), 1, "payload getter deep-copy 未变")


func test_networked_event_from_dict_arg_is_variant() -> void:
	var arg_type: int = _from_dict_first_arg_type(NE_SCRIPT)
	assert_eq(
		arg_type, TYPE_NIL,
		"NetworkedEvent.from_dict 公开参数必须是 Variant（反射 type=TYPE_NIL）；当前=%d" % arg_type
	)


func test_networked_event_from_dict_rejects_non_dictionary_matrix() -> void:
	var arg_type: int = _from_dict_first_arg_type(NE_SCRIPT)
	assert_eq(
		arg_type, TYPE_NIL,
		"签名未切到 Variant 前不动态调用非 Dictionary（Red：先修签名）"
	)
	if arg_type != TYPE_NIL:
		return
	var script: GDScript = load(NE_SCRIPT) as GDScript
	assert_not_null(script)
	var samples: Array = [null, false, true, 0, 1.0, [], "not_dict", RefCounted.new()]
	for sample in samples:
		var ret: Variant = script.call("from_dict", sample)
		assert_null(ret, "非 Dictionary 必须返回 null 且不抛: typeof=%d" % typeof(sample))


func test_describe_uses_flat_kind_not_nested_event() -> void:
	var ne: NetworkedEvent = NetworkedEvent.from_dict(
		_flat_event("TURN_PROMPT", 7, _turn_prompt_payload(1))
	)
	assert_not_null(ne)
	if ne == null:
		return
	assert_eq(
		ne.describe(),
		"NetEv[seq=7 kind=TURN_PROMPT room=room_x]",
		"describe 必须精确使用扁平 envelope 的 seq/kind/room"
	)


# ---- ACTION_APPLIED 权威 resolved 契约 ----

func test_action_applied_payload_exact_resolved_entity_schema() -> void:
	for action_kind in ACTION_APPLIED_KINDS:
		var wire := _flat_event(
			"ACTION_APPLIED", 4, _action_applied_payload(action_kind, null, 2, 7)
		)
		var ne: NetworkedEvent = NetworkedEvent.from_dict(wire)
		assert_not_null(ne, "允许牌局动作 %s 应解析" % action_kind)
		if ne == null:
			continue
		var payload: Dictionary = ne.to_dict()["payload"] as Dictionary
		assert_true(_exact_keys(payload, [
			"causation_command_id", "hand_seq", "decision_id",
			"seat", "action_kind", "resolved_payload",
		]), "%s payload exact 六键" % action_kind)
		assert_eq(str(payload.get("action_kind")), action_kind)
		assert_eq(str(payload.get("causation_command_id")), UUID_OK)
		assert_eq(str(payload.get("decision_id")), DECISION)
		assert_eq(int(payload.get("seat", -1)), 2)
		assert_eq(int(payload.get("hand_seq", -1)), 7)
		assert_eq(typeof(payload.get("resolved_payload")), TYPE_DICTIONARY)

	# KAN 三型均走 resolved_payload.meld
	for mk in ["MINKAN", "ANKAN", "ADDED_KAN"]:
		var kan_wire := _flat_event("ACTION_APPLIED", 5, _action_applied_payload(
			"KAN", {"meld": _meld_view(mk)}
		))
		assert_not_null(NetworkedEvent.from_dict(kan_wire), "KAN.%s resolved meld 应解析" % mk)

	# PASS={} 合法（只投影提交者语义由上层表达，Protocol 仅校验合法）
	var pass_wire := _flat_event("ACTION_APPLIED", 6, _action_applied_payload("PASS", {}, 1, 2))
	var pass_ev: NetworkedEvent = NetworkedEvent.from_dict(pass_wire)
	assert_not_null(pass_ev, "PASS ACTION_APPLIED 合法（显式 {} 保留）")
	if pass_ev != null:
		var pass_rp: Dictionary = (pass_ev.to_dict()["payload"] as Dictionary)["resolved_payload"]
		assert_eq(pass_rp.keys().size(), 0, "PASS resolved 必须空 dict")


func test_action_applied_rejects_item_use_session_and_command_echo() -> void:
	for action_kind in REJECTED_ACTION_KINDS:
		var p := _action_applied_payload("DISCARD")
		p["action_kind"] = action_kind
		p["resolved_payload"] = {}
		assert_null(
			NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 3, p)),
			"ACTION_APPLIED 拒绝 action_kind=%s" % action_kind
		)

	# 禁止复用 Action 命令 payload 作为回显
	var echo := {
		"causation_command_id": UUID_OK,
		"hand_seq": 1,
		"decision_id": DECISION,
		"seat": 0,
		"action_kind": "DISCARD",
		"resolved_payload": {"tile_instance_id": 42},
	}
	assert_null(
		NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 1, echo)),
		"不得把 Action 命令 payload 当 resolved_payload"
	)

	var old_normalized := {
		"command_id": UUID_OK,
		"seat": 0,
		"action_kind": "DISCARD",
		"normalized_payload": {"tile_id": TileId.W5, "is_red_dora": false},
	}
	assert_null(
		NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 1, old_normalized)),
		"旧 normalized_payload 回显契约拒绝"
	)

	# 旧 winner_seat 字段拒绝
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 1, _action_applied_payload("RON", {
			"winner_seat": 2,
			"winning_tile": _tile_view(9, TileId.S5, false, 1),
			"from_seat": 1,
		}, 2)
	)), "RON 不得含 winner_seat")


func test_action_applied_resolved_payload_exact_by_kind() -> void:
	# DISCARD / RIICHI：{tile: TileView, discard_source: DRAWN|HAND}
	for ak in ["DISCARD", "RIICHI"]:
		for src in ["DRAWN", "HAND"]:
			assert_not_null(NetworkedEvent.from_dict(_flat_event(
				"ACTION_APPLIED", 6, _action_applied_payload(ak, {
					"tile": _tile_view(1, TileId.W5, true, 0),
					"discard_source": src,
				})
			)), "%s discard_source=%s 合法" % [ak, src])
		assert_null(NetworkedEvent.from_dict(_flat_event(
			"ACTION_APPLIED", 6, _action_applied_payload(ak, {
				"tile": _tile_view(1, TileId.W5, true, 0),
			})
		)), "%s 缺 discard_source 拒绝" % ak)
		assert_null(NetworkedEvent.from_dict(_flat_event(
			"ACTION_APPLIED", 6, _action_applied_payload(ak, {
				"tile": _tile_view(1, TileId.W5, true, 0),
				"discard_source": "TSUMOGIRI",
			})
		)), "%s 非法 discard_source 拒绝" % ak)
		assert_null(NetworkedEvent.from_dict(_flat_event(
			"ACTION_APPLIED", 6, _action_applied_payload(ak, {
				"tile_instance_id": 1,
				"discard_source": "HAND",
			})
		)), "%s resolved 必须 tile:TileView" % ak)
		assert_null(NetworkedEvent.from_dict(_flat_event(
			"ACTION_APPLIED", 6, _action_applied_payload(ak, {
				"tile": _tile_view(), "discard_source": "HAND", "extra": 1,
			})
		)), "%s resolved 多键拒绝" % ak)
		assert_null(NetworkedEvent.from_dict(_flat_event(
			"ACTION_APPLIED", 6, _action_applied_payload(ak, {})
		)), "%s resolved 缺 tile" % ak)

	# CHI/PON/KAN：{meld: MeldView}
	for ak in ["CHI", "PON", "KAN"]:
		var mk := "CHI" if ak == "CHI" else ("PON" if ak == "PON" else "MINKAN")
		assert_not_null(NetworkedEvent.from_dict(_flat_event(
			"ACTION_APPLIED", 6, _action_applied_payload(ak, {"meld": _meld_view(mk)})
		)), "%s meld resolved 合法" % ak)
		assert_null(NetworkedEvent.from_dict(_flat_event(
			"ACTION_APPLIED", 6, _action_applied_payload(ak, {
				"companion_tile_instance_ids": [1, 2],
			})
		)), "%s 不得用命令 companion 回显" % ak)

	# RON：{winning_tile, from_seat}；from_seat 0..3 且 != seat
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("RON", {
			"winning_tile": _tile_view(9, TileId.S5, false, 1),
			"from_seat": 1,
		}, 2)
	)), "RON resolved 合法")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("RON", {
			"winning_tile": _tile_view(9, TileId.S5, false, 2),
			"from_seat": 2,
		}, 2)
	)), "RON from_seat 不得等于 actor seat")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("RON", {
			"winning_tile": _tile_view(9, TileId.S5, false, 1),
			"from_seat": 4,
		}, 2)
	)), "RON from_seat 必须 0..3")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("RON", {
			"winning_tile": _tile_view(9, TileId.S5, false, 1),
		}, 2)
	)), "RON 缺 from_seat")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("RON", {
			"discarder_seat": 1, "tile_id": TileId.S5,
		})
	)), "RON 旧命令 schema 拒绝")

	# TSUMO：{winning_tile} only
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("TSUMO", {
			"winning_tile": _tile_view(9, TileId.S5, false, 2),
		}, 2)
	)), "TSUMO resolved 合法")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("TSUMO", {
			"winning_tile": _tile_view(9, TileId.S5, false, 2),
			"from_seat": 1,
		}, 2)
	)), "TSUMO 不得含 from_seat")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("TSUMO", {
			"winner_seat": 2,
		})
	)), "TSUMO 缺 winning_tile / 旧 winner_seat 拒绝")

	# PASS：{}
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("PASS", {}, 0)
	)), "PASS resolved={} 合法")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("PASS", {"x": 1}, 0)
	)), "PASS resolved 多键拒绝")

	# DECLARE_ABORTIVE_DRAW
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("DECLARE_ABORTIVE_DRAW", {
			"reason": "KYUUSYU_KYUUHAI",
		})
	)))
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("DECLARE_ABORTIVE_DRAW", {
			"reason": "SUUKAIKAN",
		})
	)), "非法流局 reason")


func test_action_applied_rejects_payload_extras_and_bad_ids() -> void:
	var base := _action_applied_payload("DISCARD")
	assert_not_null(NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 1, base)))

	var with_extra := base.duplicate(true)
	with_extra["extra_field"] = 1
	assert_null(NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 1, with_extra)))

	var with_client := base.duplicate(true)
	with_client["client_seq"] = 7
	assert_null(NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 1, with_client)))

	for bad_cmd in ["", "not-a-uuid", 123, "550e8400e29b41d4a716446655440000"]:
		var p := base.duplicate(true)
		p["causation_command_id"] = bad_cmd
		assert_null(NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 2, p)))

	# lowercase 正例对照（canonical）
	assert_not_null(NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 2, base)))
	var lower_ev: NetworkedEvent = NetworkedEvent.from_dict(
		_flat_event("ACTION_APPLIED", 2, base)
	)
	if lower_ev != null:
		var lp: Dictionary = lower_ev.to_dict()["payload"] as Dictionary
		assert_eq(str(lp["causation_command_id"]), UUID_OK)
		assert_eq(str(lp["decision_id"]), DECISION)
		assert_eq(str(lp["causation_command_id"]), str(lp["causation_command_id"]).to_lower())
		assert_eq(str(lp["decision_id"]), str(lp["decision_id"]).to_lower())

	var bad_hand := base.duplicate(true)
	bad_hand["hand_seq"] = -1
	assert_null(NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 2, bad_hand)))

	var bad_hand_f := base.duplicate(true)
	bad_hand_f["hand_seq"] = 1.5
	assert_null(NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 2, bad_hand_f)))

	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 2, _action_applied_payload("DISCARD", null, 0, MAX_HAND_SEQ)
	)), "hand_seq=MAX_HAND_SEQ 合法")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 2, _action_applied_payload("DISCARD", null, 0, MAX_HAND_SEQ + 1)
	)), "hand_seq=MAX_HAND_SEQ+1 拒绝")


# ---- ACTION_APPLIED meld.kind 与 action_kind 对齐 ----

func test_action_applied_meld_kind_must_match_action_kind() -> void:
	# CHI 只接受 meld.kind=CHI
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("CHI", {
			"meld": _meld_view("CHI", 0, 1),
		}, 0)
	)), "CHI + meld.kind=CHI 合法")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("CHI", {
			"meld": _meld_view("PON", 0, 1),
		}, 0)
	)), "CHI + meld.kind=PON 拒绝")

	# PON 只接受 meld.kind=PON
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("PON", {
			"meld": _meld_view("PON", 0, 1),
		}, 0)
	)), "PON + meld.kind=PON 合法")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("PON", {
			"meld": _meld_view("CHI", 0, 1),
		}, 0)
	)), "PON + meld.kind=CHI 拒绝")

	# KAN 只接受 MINKAN / ANKAN / ADDED_KAN
	for mk in ["MINKAN", "ANKAN", "ADDED_KAN"]:
		assert_not_null(NetworkedEvent.from_dict(_flat_event(
			"ACTION_APPLIED", 6, _action_applied_payload("KAN", {
				"meld": _meld_view(mk, 0, 1 if mk != "ANKAN" else -1),
			}, 0)
		)), "KAN + meld.kind=%s 合法" % mk)
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("KAN", {
			"meld": _meld_view("PON", 0, 1),
		}, 0)
	)), "KAN + meld.kind=PON 拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 6, _action_applied_payload("KAN", {
			"meld": _meld_view("CHI", 0, 1),
		}, 0)
	)), "KAN + meld.kind=CHI 拒绝")


# ---- ACTION_APPLIED actor seat vs meld.from_seat ----

func test_action_applied_meld_from_seat_not_equal_actor() -> void:
	# owner_seat 与本约束无关；from_seat 由 helper 参数单独控制
	var actor: int = 1
	var other: int = 2

	# 正例：CHI / PON / MINKAN / ADDED_KAN 的 from_seat != ACTION_APPLIED.seat
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 7, _action_applied_payload("CHI", {
			"meld": _meld_view("CHI", 0, other),
		}, actor)
	)), "CHI from_seat!=actor 合法")
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 7, _action_applied_payload("PON", {
			"meld": _meld_view("PON", 0, other),
		}, actor)
	)), "PON from_seat!=actor 合法")
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 7, _action_applied_payload("KAN", {
			"meld": _meld_view("MINKAN", 0, other),
		}, actor)
	)), "MINKAN from_seat!=actor 合法")
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 7, _action_applied_payload("KAN", {
			"meld": _meld_view("ADDED_KAN", 0, other),
		}, actor)
	)), "ADDED_KAN from_seat!=actor 合法")

	# ANKAN：from_seat=-1 正例
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 7, _action_applied_payload("KAN", {
			"meld": _meld_view("ANKAN"),
		}, actor)
	)), "ANKAN from_seat=-1 合法")

	# 反例：from_seat == actor（每类）
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 7, _action_applied_payload("CHI", {
			"meld": _meld_view("CHI", 0, actor),
		}, actor)
	)), "CHI from_seat==actor 拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 7, _action_applied_payload("PON", {
			"meld": _meld_view("PON", 0, actor),
		}, actor)
	)), "PON from_seat==actor 拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 7, _action_applied_payload("KAN", {
			"meld": _meld_view("MINKAN", 0, actor),
		}, actor)
	)), "MINKAN from_seat==actor 拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 7, _action_applied_payload("KAN", {
			"meld": _meld_view("ADDED_KAN", 0, actor),
		}, actor)
	)), "ADDED_KAN from_seat==actor 拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 7, _action_applied_payload("KAN", {
			"meld": _meld_view("ANKAN", 0, actor, -1, -1, [
				_tile_view(20, TileId.W5, false, 0),
				_tile_view(21, TileId.W5, false, 0),
				_tile_view(22, TileId.W5, false, 0),
				_tile_view(23, TileId.W5, false, 0),
			]),
		}, actor)
	)), "ANKAN from_seat==actor 拒绝")


# ---- UUID canonical lowercase：所有 UUID 出口拒绝大写 ----

func test_uuid_uppercase_rejected_on_all_networked_event_outlets() -> void:
	# ACTION_APPLIED：causation_command_id / decision_id
	var aa := _action_applied_payload("DISCARD")
	var aa_cmd := aa.duplicate(true)
	aa_cmd["causation_command_id"] = "550E8400-E29B-41D4-A716-446655440000"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 3, aa_cmd)),
		"ACTION_APPLIED 大写 causation_command_id 拒绝"
	)
	var aa_dec := aa.duplicate(true)
	aa_dec["decision_id"] = "550E8400-E29B-41D4-A716-4466554400AA"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 3, aa_dec)),
		"ACTION_APPLIED 大写 decision_id 拒绝"
	)
	var aa_mixed := aa.duplicate(true)
	aa_mixed["causation_command_id"] = "550e8400-E29b-41d4-a716-446655440000"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 3, aa_mixed)),
		"ACTION_APPLIED 混大小写 causation_command_id 拒绝"
	)
	# version / variant 负例
	var aa_ver := aa.duplicate(true)
	aa_ver["causation_command_id"] = "550e8400-e29b-11d4-a716-446655440000"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 3, aa_ver)),
		"ACTION_APPLIED causation_command_id version≠4 拒绝"
	)
	var aa_ver_d := aa.duplicate(true)
	aa_ver_d["decision_id"] = "550e8400-e29b-11d4-a716-4466554400aa"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 3, aa_ver_d)),
		"ACTION_APPLIED decision_id version≠4 拒绝"
	)
	var aa_var := aa.duplicate(true)
	aa_var["causation_command_id"] = "550e8400-e29b-41d4-7716-446655440000"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 3, aa_var)),
		"ACTION_APPLIED causation_command_id variant 7xxx 拒绝"
	)
	var aa_var_c := aa.duplicate(true)
	aa_var_c["decision_id"] = "550e8400-e29b-41d4-c716-4466554400aa"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 3, aa_var_c)),
		"ACTION_APPLIED decision_id variant cxxx 拒绝"
	)

	# TURN_PROMPT：decision_id
	var tp := _turn_prompt_payload(1)
	tp["decision_id"] = "550E8400-E29B-41D4-A716-4466554400AA"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 4, tp)),
		"TURN_PROMPT 大写 decision_id 拒绝"
	)
	var tp_ver := _turn_prompt_payload(1)
	tp_ver["decision_id"] = "550e8400-e29b-11d4-a716-4466554400aa"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 4, tp_ver)),
		"TURN_PROMPT decision_id version≠4 拒绝"
	)
	var tp_var := _turn_prompt_payload(1)
	tp_var["decision_id"] = "550e8400-e29b-41d4-7716-4466554400aa"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 4, tp_var)),
		"TURN_PROMPT decision_id variant 7xxx 拒绝"
	)

	# CLAIM_WINDOW：decision_id
	var cw := _claim_window_payload(0)
	cw["decision_id"] = "550E8400-E29B-41D4-A716-4466554400AA"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 5, cw)),
		"CLAIM_WINDOW 大写 decision_id 拒绝"
	)
	var cw_ver := _claim_window_payload(0)
	cw_ver["decision_id"] = "550e8400-e29b-11d4-a716-4466554400aa"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 5, cw_ver)),
		"CLAIM_WINDOW decision_id version≠4 拒绝"
	)
	var cw_var := _claim_window_payload(0)
	cw_var["decision_id"] = "550e8400-e29b-41d4-c716-4466554400aa"
	assert_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 5, cw_var)),
		"CLAIM_WINDOW decision_id variant cxxx 拒绝"
	)

	# 正例：全部 lowercase v4+variant 合法
	assert_not_null(
		NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 3, _action_applied_payload("DISCARD"))),
		"ACTION_APPLIED lowercase UUID 正例"
	)
	assert_not_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 4, _turn_prompt_payload(1))),
		"TURN_PROMPT lowercase decision_id 正例"
	)
	assert_not_null(
		NetworkedEvent.from_dict(_flat_event("CLAIM_WINDOW", 5, _claim_window_payload(0))),
		"CLAIM_WINDOW lowercase decision_id 正例"
	)


# ---- ROOM_SNAPSHOT 模块化 v1（唯一协议；禁止 flat 12 键顶层）----

func test_room_snapshot_core_only_exact_keys_seq_hash_order_and_deep_copy() -> void:
	# 全数组保序：dora/river/meld/concealed/MeldView.tiles 均保留输入顺序（canonical hash 忠实数组序）
	# hand_seq=5 → 实体 id 必须落在 [680,815] 且跨区全局唯一
	var recipient := 1
	var seq := 11
	var hs := 5
	var river_input: Array = [
		_tile_view(_ns(hs, 50), TileId.W9, false, recipient), # 时间序先
		_tile_view(_ns(hs, 40), TileId.W3, false, recipient), # serial 更小但后弃
	]
	var concealed_input: Array = [
		_tile_view(_ns(hs, 22), TileId.S2, false, recipient),
		_tile_view(_ns(hs, 12), TileId.S1, false, recipient),
		_tile_view(_ns(hs, 18), TileId.S3, false, recipient),
	]
	# melds 时间序：先 PON(meld_id=2) 后 CHI(meld_id=1)；非 meld_id 升序
	# MeldView.tiles 故意非 instance_id 升序（PON），CHI 同花连续升序；输出必须原样保留
	# 实体与河/手/dora 全局唯一；physical 组互不重叠
	# holder=recipient=1：PON from≠holder；CHI from 必须上家 (1+3)%4=0
	# PON=HAKU 三 copies（from=2 called）；CHI=T2-T3-T4（from=0 called=T4）
	var pon_t1 := _canonical_tile_view(TileId.HAKU, 1, hs) # serial 125，非升序首
	var pon_t0 := _canonical_tile_view(TileId.HAKU, 0, hs) # serial 124
	var pon_called := _canonical_tile_view(TileId.HAKU, 2, hs) # serial 126，from=2
	var meld_pon := _order_preserving_meld_view(_meld_view(
		"PON", 2, 2, int(pon_called["instance_id"]), -1,
		[pon_t1, pon_t0, pon_called], hs
	))
	var chi_t2 := _canonical_tile_view(TileId.T2, 1, hs) # serial 41
	var chi_t3 := _canonical_tile_view(TileId.T3, 1, hs) # serial 45
	var chi_called := _canonical_tile_view(TileId.T4, 0, hs) # serial 48，from=0
	var meld_chi := _order_preserving_meld_view(_meld_view(
		"CHI", 1, 0, int(chi_called["instance_id"]), -1,
		[chi_t2, chi_t3, chi_called], hs
	))
	var melds_input: Array = [meld_pon, meld_chi]
	var seats: Array = []
	for i in range(4):
		if i == recipient:
			seats.append(_seat_view(
				i, SEAT_WINDS[i], 26000, 3, concealed_input, _ns(hs, 18),
				melds_input, river_input, true, false, 1
			))
		else:
			seats.append(_seat_view(
				i, SEAT_WINDS[i], 24000, 13, [], -1, [], [], false, false, -1
			))
	var dora_input: Array = [
		_tile_view(_ns(hs, 9), TileId.T5, true, -1), # 先翻
		_tile_view(_ns(hs, 3), TileId.W1, false, -1), # 后翻；serial 更小
	]
	var core := _core_table_payload(recipient, hs, "DISCARD", seats, dora_input)
	var src := _room_snapshot_payload(seq, recipient, [_core_module(core)])
	var wire := _room_snapshot_event(seq, src)
	var expected_hash: String = _snapshot_view_hash(src)
	assert_eq(expected_hash.length(), 64, "_snapshot_view_hash 须 64 hex")
	assert_eq(str(wire["view_hash"]), expected_hash,
		"ROOM_SNAPSHOT view_hash 必须等于完整四键 payload 的 _snapshot_view_hash")
	assert_eq(int(wire["server_seq"]), int(src["snapshot_server_seq"]),
		"envelope.server_seq == snapshot_server_seq")
	assert_eq(int(src["next_server_seq"]), int(src["snapshot_server_seq"]) + 1,
		"next_server_seq == snapshot_server_seq + 1")

	var ne: NetworkedEvent = NetworkedEvent.from_dict(wire)
	assert_not_null(ne, "合法 core-only ROOM_SNAPSHOT 应解析")
	if ne == null:
		return
	assert_eq(ne.server_seq, seq)
	assert_eq(str(ne.view_hash), expected_hash)

	var out: Dictionary = ne.to_dict()["payload"] as Dictionary
	assert_true(_exact_keys(out, ROOM_SNAPSHOT_TOP_KEYS), "ROOM_SNAPSHOT.payload exact 4 键")
	assert_eq(typeof(out["snapshot_server_seq"]), TYPE_INT)
	assert_eq(typeof(out["next_server_seq"]), TYPE_INT)
	assert_eq(int(out["snapshot_server_seq"]), seq)
	assert_eq(int(out["next_server_seq"]), seq + 1)
	assert_eq(typeof(out["seat_view"]), TYPE_INT)
	assert_eq(int(out["seat_view"]), recipient)
	assert_eq(ne.server_seq, int(out["snapshot_server_seq"]))

	var modules_out: Array = out["modules"]
	assert_eq(modules_out.size(), 1, "core-only 恰 1 module")
	var mod0: Dictionary = modules_out[0]
	assert_true(_exact_keys(mod0, MODULE_ENTRY_KEYS), "module exact 3 键")
	assert_eq(str(mod0["module_key"]), "core_table")
	assert_eq(int(mod0["schema_version"]), 1)
	assert_eq(typeof(mod0["payload"]), TYPE_DICTIONARY)

	var core_out: Dictionary = mod0["payload"]
	assert_true(_exact_keys(core_out, CORE_TABLE_KEYS), "core_table.payload exact 12 键")
	assert_eq(int(core_out["recipient_seat"]), recipient)
	assert_eq(int(core_out["recipient_seat"]), int(out["seat_view"]),
		"top seat_view 必须等于 core recipient_seat")
	assert_eq(int(core_out["hand_seq"]), 5)
	assert_eq(int(core_out["round_wind"]), TileId.E)
	assert_eq(int(core_out["hand_number"]), 1)
	assert_eq(int(core_out["dealer_seat"]), 0)
	assert_eq(int(core_out["current_seat"]), 0)
	assert_eq(str(core_out["phase"]), "DISCARD")
	assert_eq(int(core_out["honba"]), 0)
	assert_eq(int(core_out["riichi_sticks"]), 0)
	assert_eq(int(core_out["live_wall_count"]), 70)
	assert_false(core_out.has("wall_tiles"), "live wall 只公开 count")
	assert_false(core_out.has("ura_indicators"))
	assert_false(out.has("hand_seq"), "禁止 flat 顶层 hand_seq")
	assert_false(out.has("seats"), "禁止 flat 顶层 seats")
	assert_false(out.has("recipient_seat"), "禁止 flat 顶层 recipient_seat")

	# dora_indicators：外层 = 输入时间序，不按 instance_id 排序
	var dora_out: Array = core_out["dora_indicators"]
	assert_eq(dora_out.size(), 2)
	assert_eq(int((dora_out[0] as Dictionary)["instance_id"]), _ns(5, 9))
	assert_eq(int((dora_out[1] as Dictionary)["instance_id"]), _ns(5, 3))

	var seats_out: Array = core_out["seats"]
	assert_eq(seats_out.size(), 4)
	for i in range(4):
		var sv: Dictionary = seats_out[i]
		assert_true(_exact_keys(sv, SEAT_VIEW_KEYS), "SeatView exact 11 键 seat=%d" % i)
		assert_eq(int(sv["seat"]), i, "seats 顺序必须 0..3")
		assert_eq(int(sv["seat_wind"]), SEAT_WINDS[i])
		assert_eq(typeof(sv["riichi_double"]), TYPE_BOOL)
		if i == recipient:
			assert_eq(int(sv["concealed_count"]), 3)
			var ct: Array = sv["concealed_tiles"]
			assert_eq(ct.size(), 3)
			# 输入顺序 22,12,18 必须保留（禁止按 iid 升序）
			assert_eq(int((ct[0] as Dictionary)["instance_id"]), _ns(5, 22))
			assert_eq(int((ct[1] as Dictionary)["instance_id"]), _ns(5, 12))
			assert_eq(int((ct[2] as Dictionary)["instance_id"]), _ns(5, 18))
			assert_eq(int(sv["last_drawn_tile_instance_id"]), _ns(5, 18))
			var river: Array = sv["river"]
			assert_eq(int((river[0] as Dictionary)["instance_id"]), _ns(5, 50))
			assert_eq(int((river[1] as Dictionary)["instance_id"]), _ns(5, 40))
			assert_true(bool(sv["riichi_declared"]))
			assert_false(bool(sv["riichi_double"]))
			assert_eq(int(sv["riichi_discard_index"]), 1)
			# melds 外层 = 输入时间序（PON then CHI）；禁止按 meld_id 排序
			var melds_out: Array = sv["melds"]
			assert_eq(melds_out.size(), 2)
			assert_eq(int((melds_out[0] as Dictionary)["meld_id"]), 2)
			assert_eq(str((melds_out[0] as Dictionary)["kind"]), "PON")
			assert_eq(int((melds_out[1] as Dictionary)["meld_id"]), 1)
			assert_eq(str((melds_out[1] as Dictionary)["kind"]), "CHI")
			# MeldView.tiles 保序：输入/领域顺序，禁止 instance_id 升序重排
			var pon_tiles: Array = (melds_out[0] as Dictionary)["tiles"]
			assert_eq(pon_tiles.size(), 3)
			assert_eq(int((pon_tiles[0] as Dictionary)["instance_id"]), _ns(5, 125))
			assert_eq(int((pon_tiles[1] as Dictionary)["instance_id"]), _ns(5, 124))
			assert_eq(int((pon_tiles[2] as Dictionary)["instance_id"]), _ns(5, 126))
			assert_eq(int((melds_out[0] as Dictionary)["called_tile_instance_id"]), _ns(5, 126))
			var chi_tiles: Array = (melds_out[1] as Dictionary)["tiles"]
			assert_eq(chi_tiles.size(), 3)
			assert_eq(int((chi_tiles[0] as Dictionary)["instance_id"]), _ns(5, 41))
			assert_eq(int((chi_tiles[0] as Dictionary)["tile_id"]), TileId.T2)
			assert_eq(int((chi_tiles[1] as Dictionary)["instance_id"]), _ns(5, 45))
			assert_eq(int((chi_tiles[1] as Dictionary)["tile_id"]), TileId.T3)
			assert_eq(int((chi_tiles[2] as Dictionary)["instance_id"]), _ns(5, 48))
			assert_eq(int((chi_tiles[2] as Dictionary)["tile_id"]), TileId.T4)
			assert_eq(int((melds_out[1] as Dictionary)["called_tile_instance_id"]), _ns(5, 48))
		else:
			assert_eq((sv["concealed_tiles"] as Array).size(), 0)
			assert_eq(int(sv["last_drawn_tile_instance_id"]), -1)
			assert_eq(int(sv["concealed_count"]), 13)
			assert_eq(int(sv["riichi_discard_index"]), -1)
			assert_false(bool(sv["riichi_double"]))

	# deep copy：改输入 / to_dict 输出不得污染内部
	src["snapshot_server_seq"] = 999
	(src["modules"] as Array)[0]["schema_version"] = 99
	(((src["modules"] as Array)[0] as Dictionary)["payload"] as Dictionary)["live_wall_count"] = 1
	var core_src: Dictionary = ((src["modules"] as Array)[0] as Dictionary)["payload"]
	(core_src["dora_indicators"] as Array)[0] = _tile_view(999, TileId.W9, false, -1)
	((core_src["seats"] as Array)[recipient] as Dictionary)["score"] = 1
	var ne_core: Dictionary = _core_from_snapshot(ne.payload)
	assert_eq(int(ne.payload["snapshot_server_seq"]), seq, "from_dict 后改输入不得污染 top")
	assert_eq(int(ne_core["live_wall_count"]), 70, "from_dict 后改输入不得污染 core")
	assert_eq(int((ne_core["seats"] as Array)[recipient]["score"]), 26000)
	var mutated: Dictionary = ne.to_dict()["payload"]
	mutated["snapshot_server_seq"] = 0
	var mut_core: Dictionary = (((mutated["modules"] as Array)[0] as Dictionary)["payload"] as Dictionary)
	mut_core["live_wall_count"] = 0
	((mut_core["seats"] as Array)[recipient] as Dictionary)["score"] = 0
	var again: Dictionary = _core_from_snapshot(ne.payload)
	assert_eq(int(ne.payload["snapshot_server_seq"]), seq, "to_dict deep copy top")
	assert_eq(int(again["live_wall_count"]), 70, "to_dict deep copy core")
	assert_eq(int((again["seats"] as Array)[recipient]["score"]), 26000)


func test_room_snapshot_core_plus_unknown_json_safe_module_roundtrip() -> void:
	# modules 已按 module_key 升序：core_table < z_test_ext
	var seq := 7
	var seat_view := 2
	var core := _core_table_payload(seat_view, 3, "CLAIM")
	var unknown_payload := {
		"flag": true,
		"n": 42,
		"s": "ok",
		"none": null,
		"arr": [1, "x", false, null],
		"nested": {"k": "v", "i": 0},
	}
	var modules: Array = [
		_core_module(core),
		_module_entry("z_test_ext", 2, unknown_payload),
	]
	var src := _room_snapshot_payload(seq, seat_view, modules)
	var wire := _room_snapshot_event(seq, src)
	assert_eq(str(wire["view_hash"]), _snapshot_view_hash(src))

	var ne: NetworkedEvent = NetworkedEvent.from_dict(wire)
	assert_not_null(ne, "core_table + unknown JSON-safe module 应 roundtrip")
	var out: Dictionary = ne.to_dict()["payload"] as Dictionary
	assert_true(_exact_keys(out, ROOM_SNAPSHOT_TOP_KEYS))
	assert_eq(int(out["seat_view"]), seat_view)
	var mods: Array = out["modules"]
	assert_eq(mods.size(), 2)
	assert_eq(str((mods[0] as Dictionary)["module_key"]), "core_table")
	assert_eq(str((mods[1] as Dictionary)["module_key"]), "z_test_ext")
	assert_eq(int((mods[1] as Dictionary)["schema_version"]), 2)
	var up: Dictionary = (mods[1] as Dictionary)["payload"]
	assert_eq(bool(up["flag"]), true)
	assert_eq(int(up["n"]), 42)
	assert_eq(str(up["s"]), "ok")
	assert_eq(up["none"], null)
	assert_eq((up["arr"] as Array).size(), 4)
	assert_eq(str((up["nested"] as Dictionary)["k"]), "v")
	# 改 unknown payload 不得污染内部
	unknown_payload["n"] = 0
	(up as Dictionary)["n"] = -1
	var again: Dictionary = ((ne.to_dict()["payload"]["modules"] as Array)[1] as Dictionary)["payload"]
	assert_eq(int(again["n"]), 42, "unknown module payload deep copy")


func test_room_snapshot_rejects_seq_seat_view_and_view_hash_mismatch() -> void:
	var good := _room_snapshot_payload(10, 0)
	var correct: String = _snapshot_view_hash(good)
	assert_eq(correct.length(), 64)
	assert_true(correct != VIEW_HASH, "fixture 与 VIEW_HASH 占位必须不同")
	assert_not_null(
		NetworkedEvent.from_dict(_room_snapshot_event(10, good)),
		"合法四键 + 匹配 view_hash 正例"
	)
	assert_null(
		NetworkedEvent.from_dict(_room_snapshot_event(10, good, VIEW_HASH)),
		"合法 payload 配不相等 view_hash 必须拒绝"
	)

	# envelope.server_seq != snapshot_server_seq
	assert_null(
		NetworkedEvent.from_dict(_room_snapshot_event(9, good)),
		"server_seq != snapshot_server_seq 拒绝"
	)

	# next_server_seq != snapshot + 1
	var bad_next := good.duplicate(true)
	bad_next["next_server_seq"] = 12
	assert_null(
		NetworkedEvent.from_dict(_room_snapshot_event(10, bad_next)),
		"next_server_seq != snapshot+1 拒绝"
	)
	var bad_next_type := good.duplicate(true)
	bad_next_type["next_server_seq"] = "11"
	assert_null(
		NetworkedEvent.from_dict(_room_snapshot_event(10, bad_next_type)),
		"next_server_seq 非 strict int 拒绝"
	)
	var bad_snap_type := good.duplicate(true)
	bad_snap_type["snapshot_server_seq"] = 10.0
	assert_null(
		NetworkedEvent.from_dict(_room_snapshot_event(10, bad_snap_type)),
		"snapshot_server_seq float 拒绝"
	)
	# 安全域：next 越界
	var oob := _room_snapshot_payload(MAX_SAFE_INT, 0)
	# next = MAX_SAFE+1 已写入 helper；envelope 也无法同时满足两式与安全域
	assert_null(
		NetworkedEvent.from_dict(_room_snapshot_event(MAX_SAFE_INT, oob)),
		"next_server_seq 越安全域拒绝"
	)

	# top seat_view 与 core recipient 不一致
	var mismatch_seat := _room_snapshot_payload(
		3, 0, [_core_module(_core_table_payload(1))]
	)
	assert_null(
		NetworkedEvent.from_dict(_room_snapshot_event(3, mismatch_seat)),
		"seat_view != core.recipient_seat 拒绝"
	)
	var bad_sv := good.duplicate(true)
	bad_sv["seat_view"] = 4
	assert_null(
		NetworkedEvent.from_dict(_room_snapshot_event(10, bad_sv)),
		"seat_view 越界拒绝"
	)
	var bad_sv_type := good.duplicate(true)
	bad_sv_type["seat_view"] = "0"
	assert_null(
		NetworkedEvent.from_dict(_room_snapshot_event(10, bad_sv_type)),
		"seat_view 非 int 拒绝"
	)


func test_room_snapshot_rejects_top_module_structure_and_aliases() -> void:
	var full := _room_snapshot_payload(2, 0)
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(2, full)),
		"最小合法模块化 ROOM_SNAPSHOT 正例")

	# 顶层 exact 4 键：缺 / 多
	for key in ROOM_SNAPSHOT_TOP_KEYS:
		var miss := full.duplicate(true)
		miss.erase(key)
		assert_null(
			NetworkedEvent.from_dict(_room_snapshot_event(2, miss)),
			"ROOM_SNAPSHOT 缺 top %s 拒绝" % key
		)
	for extra_key in [
		"hand_seq", "recipient_seat", "seats", "phase", "wall_tiles",
		"ura_indicators", "opponent_hands", "decision_intents",
		"state_hash", "full_state_hash", "last_server_seq",
	]:
		var extra := full.duplicate(true)
		if extra_key in ["wall_tiles", "ura_indicators", "opponent_hands", "decision_intents", "seats"]:
			extra[extra_key] = []
		elif extra_key in ["hand_seq", "recipient_seat", "last_server_seq"]:
			extra[extra_key] = 0
		elif extra_key == "phase":
			extra[extra_key] = "DRAW"
		else:
			extra[extra_key] = "x"
		assert_null(
			NetworkedEvent.from_dict(_room_snapshot_event(2, extra)),
			"ROOM_SNAPSHOT 顶层多余/泄漏键 %s 拒绝" % extra_key
		)

	# 旧 flat 12 键整体当 payload 必须拒绝（不保留双协议）
	var flat12 := _core_table_payload(0)
	assert_null(
		NetworkedEvent.from_dict(_room_snapshot_event(2, flat12)),
		"flat 12 键不得作为 ROOM_SNAPSHOT.payload"
	)

	# modules 空 / 非 Array
	var empty_mods := full.duplicate(true)
	empty_mods["modules"] = []
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(2, empty_mods)),
		"modules 至少一个")
	var bad_mods_type := full.duplicate(true)
	bad_mods_type["modules"] = {}
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(2, bad_mods_type)),
		"modules 非 Array 拒绝")

	# missing core_table
	var no_core := _room_snapshot_payload(2, 0, [
		_module_entry("z_only", 1, {"ok": true}),
	])
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(2, no_core)),
		"缺少 core_table 拒绝")

	# 重复 module_key
	var dup := _room_snapshot_payload(2, 0, [
		_core_module(_core_table_payload(0)),
		_module_entry("core_table", 1, _core_table_payload(0)),
	])
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(2, dup)),
		"重复 module_key 拒绝")

	# 未排序：z_first 在 core_table 前（输入已乱序，禁止静默排序）
	var unsorted := _room_snapshot_payload(2, 0, [
		_module_entry("z_first", 1, {"a": 1}),
		_core_module(_core_table_payload(0)),
	])
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(2, unsorted)),
		"modules 未按 module_key 升序拒绝")
	# 另一乱序：core 后跟 alphabetically 更小的 key
	var unsorted2 := _room_snapshot_payload(2, 0, [
		_core_module(_core_table_payload(0)),
		_module_entry("aaa_ext", 1, {"a": 1}),
	])
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(2, unsorted2)),
		"modules 降序片段拒绝")

	# core schema_version 必须 1
	var core_v2 := _room_snapshot_payload(2, 0, [
		_module_entry("core_table", 2, _core_table_payload(0)),
	])
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(2, core_v2)),
		"core_table schema_version 非 1 拒绝")

	# module_key 空 / 首尾空白
	for bad_key in ["", "  core_table", "core_table  ", " core "]:
		var bad_mk := full.duplicate(true)
		var m0: Dictionary = ((bad_mk["modules"] as Array)[0] as Dictionary).duplicate(true)
		m0["module_key"] = bad_key
		bad_mk["modules"] = [m0]
		assert_null(
			NetworkedEvent.from_dict(_room_snapshot_event(2, bad_mk)),
			"module_key 非法 %s 拒绝" % str(bad_key)
		)

	# module exact 3 键：缺 / 多 / 别名 module_version / data
	var miss_mk := full.duplicate(true)
	var m_miss: Dictionary = ((miss_mk["modules"] as Array)[0] as Dictionary).duplicate(true)
	m_miss.erase("module_key")
	miss_mk["modules"] = [m_miss]
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(2, miss_mk)),
		"module 缺 module_key 拒绝")
	var miss_sv := full.duplicate(true)
	var m_sv: Dictionary = ((miss_sv["modules"] as Array)[0] as Dictionary).duplicate(true)
	m_sv.erase("schema_version")
	miss_sv["modules"] = [m_sv]
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(2, miss_sv)),
		"module 缺 schema_version 拒绝")
	var miss_pl := full.duplicate(true)
	var m_pl: Dictionary = ((miss_pl["modules"] as Array)[0] as Dictionary).duplicate(true)
	m_pl.erase("payload")
	miss_pl["modules"] = [m_pl]
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(2, miss_pl)),
		"module 缺 payload 拒绝")

	var alias_ver := {
		"module_key": "core_table",
		"module_version": 1,
		"payload": _core_table_payload(0),
	}
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(2, _room_snapshot_payload(
		2, 0, [alias_ver]
	))), "module_version 别名拒绝")
	var alias_data := {
		"module_key": "core_table",
		"schema_version": 1,
		"data": _core_table_payload(0),
	}
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(2, _room_snapshot_payload(
		2, 0, [alias_data]
	))), "module data 别名拒绝")
	var alias_both := {
		"module_key": "core_table",
		"schema_version": 1,
		"payload": _core_table_payload(0),
		"module_version": 1,
	}
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(2, _room_snapshot_payload(
		2, 0, [alias_both]
	))), "module 多余 module_version 拒绝")


func test_room_snapshot_rejects_unknown_module_schema_and_payload_domain() -> void:
	var core := _core_module(_core_table_payload(0))

	# unknown schema_version 必须 strict int >= 1
	for bad_ver in [0, -1]:
		var bad_int := _room_snapshot_payload(4, 0, [
			core, _module_entry("z_ext", int(bad_ver), {"ok": true}),
		])
		assert_null(
			NetworkedEvent.from_dict(_room_snapshot_event(4, bad_int)),
			"unknown schema_version=%s 拒绝" % str(bad_ver)
		)
	for bad_ver in [1.5, "1", null]:
		var bad_type := _room_snapshot_payload(4, 0, [
			core,
			{
				"module_key": "z_ext",
				"schema_version": bad_ver,
				"payload": {"ok": true},
			},
		])
		assert_null(
			NetworkedEvent.from_dict(_room_snapshot_event(4, bad_type)),
			"unknown schema_version typeof 非法=%s 拒绝" % str(bad_ver)
		)

	# unknown payload：float / Object / 非 String key / 越界 int
	var bad_float := _room_snapshot_payload(4, 0, [
		core, _module_entry("z_ext", 1, {"x": 1.5}),
	])
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(4, bad_float)),
		"unknown payload float 拒绝")
	var bad_obj := _room_snapshot_payload(4, 0, [
		core, _module_entry("z_ext", 1, {"o": RefCounted.new()}),
	])
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(4, bad_obj)),
		"unknown payload Object 拒绝")
	var bad_key := _room_snapshot_payload(4, 0, [
		core,
		{
			"module_key": "z_ext",
			"schema_version": 1,
			"payload": {1: "a"},
		},
	])
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(4, bad_key)),
		"unknown payload 非 String key 拒绝")
	var bad_oob := _room_snapshot_payload(4, 0, [
		core, _module_entry("z_ext", 1, {"n": MAX_SAFE_INT + 1}),
	])
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(4, bad_oob)),
		"unknown payload 越界 int 拒绝")
	var bad_nested_float := _room_snapshot_payload(4, 0, [
		core, _module_entry("z_ext", 1, {"arr": [1, 2.0]}),
	])
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(4, bad_nested_float)),
		"unknown nested float 拒绝")

	# 合法 JSON-safe 对照（已在 roundtrip 覆盖）；schema_version=1 正例
	var ok_ext := _room_snapshot_payload(4, 0, [
		core, _module_entry("z_ext", 1, {
			"a": null, "b": true, "c": "s", "d": 0, "e": MAX_SAFE_INT,
			"f": [1, "x"], "g": {"k": false},
		}),
	])
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(4, ok_ext)),
		"unknown JSON-safe opaque 正例")


func test_room_snapshot_rejects_core_privacy_type_range_and_seat_cross() -> void:
	var seq := 2
	var full := _room_snapshot_payload(seq, 0)
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(seq, full)),
		"最小合法 core-only 正例")

	# core exact 12：缺 / 隐私泄漏多余键
	for key in CORE_TABLE_KEYS:
		var miss_core := full.duplicate(true)
		var core_miss: Dictionary = (
			((miss_core["modules"] as Array)[0] as Dictionary)["payload"] as Dictionary
		).duplicate(true)
		core_miss.erase(key)
		((miss_core["modules"] as Array)[0] as Dictionary)["payload"] = core_miss
		assert_null(
			NetworkedEvent.from_dict(_room_snapshot_event(seq, miss_core)),
			"core 缺 %s 拒绝" % key
		)
	for leak_key in [
		"wall_tiles", "ura_indicators", "hidden_uradora", "dead_wall",
		"state_hash", "full_state_hash", "decision_intents", "opponent_hands",
	]:
		var core_with_leak := full.duplicate(true)
		var core_leak: Dictionary = (
			((core_with_leak["modules"] as Array)[0] as Dictionary)["payload"] as Dictionary
		).duplicate(true)
		if leak_key in ["wall_tiles", "ura_indicators", "hidden_uradora", "dead_wall", "decision_intents", "opponent_hands"]:
			core_leak[leak_key] = []
		else:
			core_leak[leak_key] = "x"
		((core_with_leak["modules"] as Array)[0] as Dictionary)["payload"] = core_leak
		assert_null(
			NetworkedEvent.from_dict(_room_snapshot_event(seq, core_with_leak)),
			"core 隐私/多余键 %s 拒绝" % leak_key
		)

	# type / range（改 core.payload）
	var bad_phase := full.duplicate(true)
	(((bad_phase["modules"] as Array)[0] as Dictionary)["payload"] as Dictionary)["phase"] = "WAIT"
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(seq, bad_phase)),
		"phase 非法拒绝")
	var bad_rw := full.duplicate(true)
	(((bad_rw["modules"] as Array)[0] as Dictionary)["payload"] as Dictionary)["round_wind"] = TileId.W_WIND
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(seq, bad_rw)),
		"round_wind 仅 E/S_WIND")
	var ok_south_core := _core_table_payload(0)
	ok_south_core["round_wind"] = TileId.S_WIND
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [_core_module(ok_south_core)])
	)), "round_wind=S_WIND 合法")
	var bad_hn := full.duplicate(true)
	(((bad_hn["modules"] as Array)[0] as Dictionary)["payload"] as Dictionary)["hand_number"] = 0
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(seq, bad_hn)),
		"hand_number 0 拒绝")
	(((bad_hn["modules"] as Array)[0] as Dictionary)["payload"] as Dictionary)["hand_number"] = 5
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(seq, bad_hn)),
		"hand_number 5 拒绝")
	var bad_live := full.duplicate(true)
	(((bad_live["modules"] as Array)[0] as Dictionary)["payload"] as Dictionary)["live_wall_count"] = -1
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(seq, bad_live)),
		"live_wall_count 负拒绝")
	var bad_hs := full.duplicate(true)
	(((bad_hs["modules"] as Array)[0] as Dictionary)["payload"] as Dictionary)["hand_seq"] = -1
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(seq, bad_hs)))
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, MAX_HAND_SEQ)),
		])
	)), "hand_seq=MAX_HAND_SEQ 合法")
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, MAX_HAND_SEQ + 1)),
		])
	)), "hand_seq=MAX_HAND_SEQ+1 拒绝")
	var bad_rs := full.duplicate(true)
	(((bad_rs["modules"] as Array)[0] as Dictionary)["payload"] as Dictionary)["recipient_seat"] = 4
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(seq, bad_rs)),
		"recipient_seat 越界拒绝")
	var bad_type := full.duplicate(true)
	(((bad_type["modules"] as Array)[0] as Dictionary)["payload"] as Dictionary)["honba"] = "0"
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(seq, bad_type)),
		"honba 不得 str 强转")

	# seats 必须恰 4 且 seat 顺序 0..3
	var core_full: Dictionary = _core_from_snapshot(full)
	var bad_count_core := core_full.duplicate(true)
	bad_count_core["seats"] = (core_full["seats"] as Array).slice(0, 3)
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [_core_module(bad_count_core)])
	)), "seats 非 4 拒绝")
	var reordered: Array = []
	reordered.append((core_full["seats"] as Array)[1])
	reordered.append((core_full["seats"] as Array)[0])
	reordered.append((core_full["seats"] as Array)[2])
	reordered.append((core_full["seats"] as Array)[3])
	var bad_order_core := core_full.duplicate(true)
	bad_order_core["seats"] = reordered
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [_core_module(bad_order_core)])
	)), "seats 顺序非 0..3 拒绝")

	# 四风不重复
	var bad_winds := _default_seats(0)
	(bad_winds[1] as Dictionary)["seat_wind"] = TileId.E
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", bad_winds)),
		])
	)), "seat_wind 重复拒绝")

	# 非 recipient 默认 count-only；信息能力可投影不超过 concealed_count 的可见子集。
	# 权限由服务端 RecipientViewProjector 决定，wire validator 只验证子集结构边界。
	var seats_partial_reveal := _default_seats(0)
	(seats_partial_reveal[2] as Dictionary)["concealed_tiles"] = [
		_tile_view(99, TileId.W1, false, 2)]
	(seats_partial_reveal[2] as Dictionary)["concealed_count"] = 2
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", seats_partial_reveal)),
		])
	)), "非 recipient 可携带服务端授权的部分可见手牌")
	var too_many_revealed := _default_seats(0)
	(too_many_revealed[2] as Dictionary)["concealed_tiles"] = [
		_tile_view(99, TileId.W1, false, 2),
		_tile_view(100, TileId.W2, false, 2),
	]
	(too_many_revealed[2] as Dictionary)["concealed_count"] = 1
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", too_many_revealed)),
		])
	)), "可见子集不得超过真实 concealed_count")
	var leak_drawn := _default_seats(0)
	(leak_drawn[3] as Dictionary)["last_drawn_tile_instance_id"] = 5
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", leak_drawn)),
		])
	)), "非 recipient last_drawn 非 -1 拒绝")

	# recipient：size==concealed_count；last_drawn 必须 -1 或命中 concealed iid
	var mismatch := _default_seats(0)
	(mismatch[0] as Dictionary)["concealed_count"] = 3
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", mismatch)),
		])
	)), "recipient size!=concealed_count 拒绝")
	var bad_drawn := _default_seats(0)
	(bad_drawn[0] as Dictionary)["last_drawn_tile_instance_id"] = 999
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", bad_drawn)),
		])
	)), "last_drawn 不在 concealed_tiles 拒绝")

	# riichi 交叉：
	# - 未立直 discard_index 必须 -1
	# - 已立直 index=-1 合法；非 -1 必须指向河内合法索引
	# - riichi_double true => riichi_declared true
	var no_riichi_idx := _default_seats(0)
	(no_riichi_idx[0] as Dictionary)["riichi_declared"] = false
	(no_riichi_idx[0] as Dictionary)["riichi_discard_index"] = 0
	(no_riichi_idx[0] as Dictionary)["river"] = [_tile_view(70, TileId.W1, false, 0)]
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", no_riichi_idx)),
		])
	)), "未立直 riichi_discard_index 必须 -1")
	# 正例：riichi_declared=true 且 index=-1 合法
	var riichi_neg1 := _default_seats(0)
	(riichi_neg1[0] as Dictionary)["riichi_declared"] = true
	(riichi_neg1[0] as Dictionary)["riichi_discard_index"] = -1
	(riichi_neg1[0] as Dictionary)["river"] = [_tile_view(70, TileId.W1, false, 0)]
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", riichi_neg1)),
		])
	)), "riichi_declared=true 且 index=-1 合法")
	var riichi_neg1_empty := _default_seats(0)
	(riichi_neg1_empty[0] as Dictionary)["riichi_declared"] = true
	(riichi_neg1_empty[0] as Dictionary)["riichi_discard_index"] = -1
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", riichi_neg1_empty)),
		])
	)), "立直 index=-1 且空河合法")
	var riichi_oob := _default_seats(0)
	(riichi_oob[0] as Dictionary)["riichi_declared"] = true
	(riichi_oob[0] as Dictionary)["river"] = [_tile_view(70, TileId.W1, false, 0)]
	(riichi_oob[0] as Dictionary)["riichi_discard_index"] = 1
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", riichi_oob)),
		])
	)), "立直非 -1 index 越界拒绝")
	var double_without := _default_seats(0)
	(double_without[0] as Dictionary)["riichi_double"] = true
	(double_without[0] as Dictionary)["riichi_declared"] = false
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", double_without)),
		])
	)), "riichi_double true 要求 riichi_declared true")
	var double_type := _default_seats(0)
	(double_type[0] as Dictionary)["riichi_double"] = 1
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", double_type)),
		])
	)), "riichi_double 非 bool 拒绝")
	# 合法 double riichi + 合法河索引
	var ok_double := _default_seats(0)
	(ok_double[0] as Dictionary)["riichi_declared"] = true
	(ok_double[0] as Dictionary)["riichi_double"] = true
	(ok_double[0] as Dictionary)["river"] = [_tile_view(70, TileId.W1, false, 0)]
	(ok_double[0] as Dictionary)["riichi_discard_index"] = 0
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", ok_double)),
		])
	)), "riichi_double 合法正例")

	# SeatView missing / extra
	var seat_miss := _default_seats(0)
	(seat_miss[0] as Dictionary).erase("score")
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", seat_miss)),
		])
	)), "SeatView 缺 score 拒绝")
	var seat_miss_double := _default_seats(0)
	(seat_miss_double[0] as Dictionary).erase("riichi_double")
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", seat_miss_double)),
		])
	)), "SeatView 缺 riichi_double 拒绝")
	var seat_extra := _default_seats(0)
	(seat_extra[0] as Dictionary)["hand"] = []
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", seat_extra)),
		])
	)), "SeatView 多余 hand 拒绝")

	# dora / river 必须 TileView；melds 必须 MeldView
	var bad_dora_core := _core_table_payload(0)
	bad_dora_core["dora_indicators"] = [{"tile_id": TileId.W1}]
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [_core_module(bad_dora_core)])
	)), "dora 非 TileView 拒绝")
	var bad_meld := _default_seats(0)
	(bad_meld[0] as Dictionary)["melds"] = [{"kind": "PON"}]
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 0, "DRAW", bad_meld)),
		])
	)), "melds 非 MeldView 拒绝")


# ---- 唯一构造 API ----

func test_networked_event_unique_make_api_no_business_aliases() -> void:
	# 反射：仅保留 make(kind,seq,room,payload,hash)；五参必填、default_args 空。
	# 不得再暴露 business / make_business。测试不得动态 skip。
	var script: GDScript = load(NE_SCRIPT) as GDScript
	assert_not_null(script, "networked_event.gd 须可 load")
	assert_true(_script_has_static("make"), "必须保留 make")
	assert_false(_script_has_static("business"), "不得暴露 business")
	assert_false(_script_has_static("make_business"), "不得暴露 make_business")

	var found_make := false
	for m in script.get_script_method_list():
		if str(m.get("name", "")) != "make":
			continue
		found_make = true
		var args: Array = m.get("args", [])
		assert_eq(args.size(), 5, "make 必须五参 kind/seq/room/payload/hash")
		var defaults: Array = m.get("default_args", [])
		assert_eq(defaults.size(), 0, "make 五参均必填：default_args 必须空")
		break
	assert_true(found_make, "反射必须找到 make")


# ---- PLAYER_JOINED recipient DTO ----

func test_player_joined_valid_and_rejects() -> void:
	for kind in ["HUMAN", "AI"]:
		var ne: NetworkedEvent = NetworkedEvent.from_dict(
			_flat_event("PLAYER_JOINED", 1, _player_joined_payload(2, kind, "Alice", true))
		)
		assert_not_null(ne, "PLAYER_JOINED %s 合法" % kind)
		if ne == null:
			continue
		var p: Dictionary = ne.to_dict()["payload"] as Dictionary
		assert_true(_exact_keys(p, PLAYER_JOINED_KEYS), "PLAYER_JOINED exact 4 键")
		assert_eq(int(p["seat"]), 2)
		assert_eq(str(p["participant_kind"]), kind)
		assert_eq(str(p["display_name"]), "Alice")
		assert_eq(typeof(p["connected"]), TYPE_BOOL)
		assert_true(bool(p["connected"]))

	# authoritative wire：strip_edges 后非空，且原值已无首尾空白；禁止输出 trim
	assert_null(NetworkedEvent.from_dict(
		_flat_event("PLAYER_JOINED", 1, _player_joined_payload(0, "HUMAN", "  Bob  ", false))
	), "display_name 首尾空白必须拒绝，不得 strip 后接受")
	var spaced: NetworkedEvent = NetworkedEvent.from_dict(
		_flat_event("PLAYER_JOINED", 1, _player_joined_payload(0, "HUMAN", "Alice Bob", true))
	)
	assert_not_null(spaced, "display_name 内部空格合法")
	if spaced != null:
		assert_eq(
			str((spaced.to_dict()["payload"] as Dictionary)["display_name"]),
			"Alice Bob",
			"内部空格原样保留"
		)

	var full := _player_joined_payload()
	for key in PLAYER_JOINED_KEYS:
		var miss := full.duplicate(true)
		miss.erase(key)
		assert_null(NetworkedEvent.from_dict(_flat_event("PLAYER_JOINED", 1, miss)),
			"PLAYER_JOINED 缺 %s" % key)
	var extra := full.duplicate(true)
	extra["avatar_url"] = "x"
	assert_null(NetworkedEvent.from_dict(_flat_event("PLAYER_JOINED", 1, extra)),
		"PLAYER_JOINED 多余键拒绝")

	assert_null(NetworkedEvent.from_dict(_flat_event(
		"PLAYER_JOINED", 1, _player_joined_payload(4)
	)), "seat>3 拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"PLAYER_JOINED", 1, _player_joined_payload(-1)
	)), "seat<0 拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"PLAYER_JOINED", 1, _player_joined_payload(0, "BOT")
	)), "participant_kind 非法拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"PLAYER_JOINED", 1, _player_joined_payload(0, "HUMAN", "")
	)), "display_name 空拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"PLAYER_JOINED", 1, _player_joined_payload(0, "HUMAN", "   ")
	)), "display_name 纯空白拒绝")
	var bad_conn := full.duplicate(true)
	bad_conn["connected"] = 1
	assert_null(NetworkedEvent.from_dict(_flat_event("PLAYER_JOINED", 1, bad_conn)),
		"connected 非 bool 拒绝")
	var bad_name_type := full.duplicate(true)
	bad_name_type["display_name"] = 42
	assert_null(NetworkedEvent.from_dict(_flat_event("PLAYER_JOINED", 1, bad_name_type)),
		"display_name 非 String 拒绝")


# ---- HAND_SETTLED recipient DTO ----

func test_hand_settled_valid_outcomes_and_cross_rules() -> void:
	# RON：恰好单 winner；多 winner 必须拒绝（生产缺口 Red）
	var ron_in := _hand_settled_payload(
		"RON", [2], 1,
		[-1000, 0, 1000, 0],
		[24000, 25000, 26000, 25000]
	)
	var ron_ev: NetworkedEvent = NetworkedEvent.from_dict(
		_flat_event("HAND_SETTLED", 8, ron_in)
	)
	assert_not_null(ron_ev, "RON 单 winner 合法")
	if ron_ev != null:
		var rp: Dictionary = ron_ev.to_dict()["payload"] as Dictionary
		assert_true(_exact_keys(rp, HAND_SETTLED_KEYS), "HAND_SETTLED exact 11 键")
		assert_eq(str(rp["outcome"]), "RON")
		assert_eq(rp["winner_seats"], [2], "RON winner_seats 恰好一人")
		assert_eq(int(rp["loser_seat"]), 1)
		assert_eq((rp["score_deltas"] as Array).size(), 4)
		assert_eq((rp["scores"] as Array).size(), 4)
		# A 契约：score_deltas = final - start；局前桌上立直棒入赢家时
		# 局内 delta 和可合法非零，禁止静态 sum==0 协议限制。

	# 多 winner RON 必须拒绝（即使升序 unique）
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 8, _hand_settled_payload(
			"RON", [0, 2], 1,
			[1500, -3000, 1500, 0],
			[26500, 22000, 26500, 25000]
		)
	)), "RON 多 winner 必须拒绝")

	# 未升序输入必须拒绝（禁止静默 sort）—— 多 winner 路径同样拒绝
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 8, _hand_settled_payload(
			"RON", [2, 0], 1,
			[1500, -3000, 1500, 0],
			[26500, 22000, 26500, 25000]
		)
	)), "winner_seats 未升序 [2,0] 必须拒绝，禁止静默 sort")

	# TSUMO：恰 1 winner，loser=-1
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 8, _hand_settled_payload("TSUMO", [3], -1,
			[-1000, -1000, -1000, 3000], [24000, 24000, 24000, 28000])
	)), "TSUMO 合法")

	# 两种流局
	for outcome in ["EXHAUSTIVE_DRAW", "ABORTIVE_DRAW"]:
		var draw_ev: NetworkedEvent = NetworkedEvent.from_dict(_flat_event(
			"HAND_SETTLED", 8, _hand_settled_payload(outcome, [], -1,
				[0, 0, 0, 0], [25000, 25000, 25000, 25000])
		))
		assert_not_null(draw_ev, "%s 合法" % outcome)
		if draw_ev != null:
			var dp: Dictionary = draw_ev.to_dict()["payload"] as Dictionary
			assert_eq((dp["winner_seats"] as Array).size(), 0)
			assert_eq(int(dp["loser_seat"]), -1)


func test_hand_settled_rejects_missing_extra_type_range_and_cross() -> void:
	var full := _hand_settled_payload()
	assert_not_null(NetworkedEvent.from_dict(_flat_event("HAND_SETTLED", 3, full)))

	for key in HAND_SETTLED_KEYS:
		var miss := full.duplicate(true)
		miss.erase(key)
		assert_null(NetworkedEvent.from_dict(_flat_event("HAND_SETTLED", 3, miss)),
			"HAND_SETTLED 缺 %s" % key)
	var extra := full.duplicate(true)
	extra["yaku"] = ["RIICHI"]
	assert_null(NetworkedEvent.from_dict(_flat_event("HAND_SETTLED", 3, extra)),
		"HAND_SETTLED 多余键拒绝")
	extra = full.duplicate(true)
	extra["state_hash"] = VIEW_HASH
	assert_null(NetworkedEvent.from_dict(_flat_event("HAND_SETTLED", 3, extra)),
		"HAND_SETTLED state_hash 拒绝")

	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload("WIN", [0], -1)
	)), "非法 outcome 拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload("TSUMO", [], -1)
	)), "TSUMO winner 空拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload("TSUMO", [0, 1], -1)
	)), "TSUMO 多 winner 拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload("TSUMO", [0], 2)
	)), "TSUMO loser 必须 -1")

	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload("RON", [], 1)
	)), "RON winner 空拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload(
			"RON", [0, 2], 1,
			[1500, -3000, 1500, 0],
			[26500, 22000, 26500, 25000]
		)
	)), "RON 多 winner 拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload("RON", [0], -1)
	)), "RON loser 无效拒绝")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload("RON", [1], 1)
	)), "RON loser 不得在 winners")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload("RON", [0, 0], 1)
	)), "winner_seats 不得重复")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload("RON", [4], 1)
	)), "winner seat 越界")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload(
			"RON", [2, 0], 1,
			[1500, -3000, 1500, 0],
			[26500, 22000, 26500, 25000]
		)
	)), "winner_seats 未升序拒绝")

	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload("EXHAUSTIVE_DRAW", [0], -1)
	)), "流局 winner 必须空")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload("ABORTIVE_DRAW", [], 0)
	)), "流局 loser 必须 -1")

	# A 契约：局前立直棒进入赢家分数 → sum(score_deltas) 可合法非零
	var nonzero_sum := _hand_settled_payload(
		"TSUMO", [0], -1,
		[1000, 0, 0, 0],
		[26000, 25000, 25000, 25000]
	)
	assert_not_null(NetworkedEvent.from_dict(_flat_event("HAND_SETTLED", 3, nonzero_sum)),
		"score_deltas 合法非零和须接受（局前立直棒入赢家）")
	var nonzero_ron := _hand_settled_payload(
		"RON", [2], 1,
		[0, -1000, 2000, 0],
		[25000, 24000, 27000, 25000]
	)
	assert_not_null(NetworkedEvent.from_dict(_flat_event("HAND_SETTLED", 3, nonzero_ron)),
		"RON score_deltas 非零和须接受")
	var bad_len := full.duplicate(true)
	bad_len["score_deltas"] = [0, 0, 0]
	assert_null(NetworkedEvent.from_dict(_flat_event("HAND_SETTLED", 3, bad_len)),
		"score_deltas 长度非 4")
	bad_len = full.duplicate(true)
	bad_len["scores"] = [1, 2, 3]
	assert_null(NetworkedEvent.from_dict(_flat_event("HAND_SETTLED", 3, bad_len)),
		"scores 长度非 4")
	var bad_type := full.duplicate(true)
	bad_type["hand_seq"] = "1"
	assert_null(NetworkedEvent.from_dict(_flat_event("HAND_SETTLED", 3, bad_type)),
		"hand_seq 不得 str")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload("TSUMO", [0], -1,
			[3000, -1000, -1000, -1000], [28000, 24000, 24000, 24000], -1)
	)), "hand_seq 负拒绝")
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload("TSUMO", [0], -1,
			[3000, -1000, -1000, -1000], [28000, 24000, 24000, 24000], MAX_HAND_SEQ)
	)), "hand_seq=MAX 合法")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"HAND_SETTLED", 3, _hand_settled_payload("TSUMO", [0], -1,
			[3000, -1000, -1000, -1000], [28000, 24000, 24000, 24000], MAX_HAND_SEQ + 1)
	)), "hand_seq=MAX+1 拒绝")


# ---- MATCH_SETTLED recipient DTO ----

func test_match_settled_valid_and_rejects() -> void:
	for rk in ["EAST", "HANCHAN"]:
		var ne: NetworkedEvent = NetworkedEvent.from_dict(
			_flat_event("MATCH_SETTLED", 20, _match_settled_payload(rk, [32000, 28000, 22000, 18000], [0, 1, 2, 3]))
		)
		assert_not_null(ne, "MATCH_SETTLED %s 合法" % rk)
		if ne == null:
			continue
		var p: Dictionary = ne.to_dict()["payload"] as Dictionary
		assert_true(_exact_keys(p, MATCH_SETTLED_KEYS), "MATCH_SETTLED exact 3 键")
		assert_eq(str(p["round_kind"]), rk)
		assert_eq((p["final_scores"] as Array).size(), 4)
		assert_eq(p["seat_order"], [0, 1, 2, 3])

	# seat_order 必须按 final_scores 降序；同分 seat 升序
	var sorted_ok: NetworkedEvent = NetworkedEvent.from_dict(
		_flat_event("MATCH_SETTLED", 21, _match_settled_payload("EAST",
			[18000, 32000, 22000, 28000], [1, 3, 2, 0]))
	)
	assert_not_null(sorted_ok, "seat_order 按分降序合法")
	if sorted_ok != null:
		assert_eq((sorted_ok.to_dict()["payload"] as Dictionary)["seat_order"], [1, 3, 2, 0])

	# 同分 seat 升序：scores[1]==scores[2]=25000 → seat 1 先于 2
	assert_not_null(NetworkedEvent.from_dict(
		_flat_event("MATCH_SETTLED", 22, _match_settled_payload("EAST",
			[30000, 25000, 25000, 20000], [0, 1, 2, 3]))
	), "同分 seat 升序正例")
	assert_null(NetworkedEvent.from_dict(
		_flat_event("MATCH_SETTLED", 22, _match_settled_payload("EAST",
			[30000, 25000, 25000, 20000], [0, 2, 1, 3]))
	), "同分 seat 未升序必须拒绝")
	# 非分数降序排列拒绝
	assert_null(NetworkedEvent.from_dict(
		_flat_event("MATCH_SETTLED", 23, _match_settled_payload("EAST",
			[18000, 32000, 22000, 28000], [0, 1, 2, 3]))
	), "seat_order 未按 final_scores 降序必须拒绝")

	var full := _match_settled_payload()
	for key in MATCH_SETTLED_KEYS:
		var miss := full.duplicate(true)
		miss.erase(key)
		assert_null(NetworkedEvent.from_dict(_flat_event("MATCH_SETTLED", 20, miss)),
			"MATCH_SETTLED 缺 %s" % key)
	var extra := full.duplicate(true)
	extra["uma"] = [15, 5, -5, -15]
	assert_null(NetworkedEvent.from_dict(_flat_event("MATCH_SETTLED", 20, extra)),
		"MATCH_SETTLED 多余键拒绝")

	assert_null(NetworkedEvent.from_dict(_flat_event(
		"MATCH_SETTLED", 20, _match_settled_payload("TONPUU")
	)), "round_kind 非法拒绝")
	var bad_scores := full.duplicate(true)
	bad_scores["final_scores"] = [1, 2, 3]
	assert_null(NetworkedEvent.from_dict(_flat_event("MATCH_SETTLED", 20, bad_scores)),
		"final_scores 长度非 4")
	var bad_type := full.duplicate(true)
	bad_type["final_scores"] = [1, 2, 3, "4"]
	assert_null(NetworkedEvent.from_dict(_flat_event("MATCH_SETTLED", 20, bad_type)),
		"final_scores 元素非 int")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"MATCH_SETTLED", 20, _match_settled_payload("EAST", [1, 2, 3, 4], [0, 1, 2])
	)), "seat_order 长度非 4")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"MATCH_SETTLED", 20, _match_settled_payload("EAST", [1, 2, 3, 4], [0, 1, 2, 2])
	)), "seat_order 重复非排列")
	assert_null(NetworkedEvent.from_dict(_flat_event(
		"MATCH_SETTLED", 20, _match_settled_payload("EAST", [1, 2, 3, 4], [0, 1, 2, 4])
	)), "seat_order 越界")
	var bad_rk_type := full.duplicate(true)
	bad_rk_type["round_kind"] = 1
	assert_null(NetworkedEvent.from_dict(_flat_event("MATCH_SETTLED", 20, bad_rk_type)),
		"round_kind 非 String 拒绝")

# ---- #232 跨局命名空间 / 实体全局唯一 / 生产缺口 Red ----

## 将合法 MeldView 中第 tile_index 张牌的 instance_id 改为 new_iid，
## 并同步 called/added 引用。保持 tile_id/顺序/交叉约束，避免非法 meld 假 Red。
func _meld_with_tile_iid(meld: Dictionary, tile_index: int, new_iid: int) -> Dictionary:
	var m: Dictionary = meld.duplicate(true)
	var tiles: Array = (m["tiles"] as Array).duplicate(true)
	assert(tile_index >= 0 and tile_index < tiles.size(), "tile_index 越界")
	var old_iid: int = int((tiles[tile_index] as Dictionary)["instance_id"])
	var td: Dictionary = (tiles[tile_index] as Dictionary).duplicate(true)
	td["instance_id"] = new_iid
	tiles[tile_index] = td
	m["tiles"] = tiles
	if int(m.get("called_tile_instance_id", -1)) == old_iid:
		m["called_tile_instance_id"] = new_iid
	if int(m.get("added_tile_instance_id", -1)) == old_iid:
		m["added_tile_instance_id"] = new_iid
	return m


func test_action_applied_rejects_resolved_entity_outside_hand_seq_namespace() -> void:
	# hand_seq=2 合法域 [272,407]；out_low 属 hand_seq=0；out_high=上界+1
	var hs := 2
	var actor := 0
	var other := 1
	var out_low: int = 10
	var out_high: int = _ns(hs, 136)
	var lo: int = _ns(hs, 0)
	var hi: int = _ns(hs, 135)

	# ---- DISCARD（保留既有反例 + 边界正例）----
	var bad_discard := _action_applied_payload("DISCARD", {
		"tile": _tile_view(out_low, TileId.W5, false, actor),
		"discard_source": "DRAWN",
	}, actor, hs)
	assert_null(
		NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 9, bad_discard)),
		"ACTION_APPLIED DISCARD resolved tile 超出 hand_seq 命名空间必须拒绝"
	)
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 9, _action_applied_payload("DISCARD", {
			"tile": _tile_view(lo, TileId.W5, false, actor),
			"discard_source": "DRAWN",
		}, actor, hs)
	)), "DISCARD serial=0 边界正例")
	assert_not_null(NetworkedEvent.from_dict(_flat_event(
		"ACTION_APPLIED", 9, _action_applied_payload("DISCARD", {
			"tile": _tile_view(hi, TileId.W5, false, actor),
			"discard_source": "HAND",
		}, actor, hs)
	)), "DISCARD serial=135 边界正例")

	# ---- 表驱动：RIICHI / CHI / PON / KAN.* / RON / TSUMO ----
	# 每类至少一个命名空间外实体；meld 改的是 tiles/called/added 内实体，
	# 不是顶层单一 tile wrapper。fixture 先用 _meld_view_ns 保证结构合法。
	var cases: Array = [
		{
			"label": "RIICHI.tile",
			"action_kind": "RIICHI",
			"resolved": {
				"tile": _tile_view(out_low, TileId.W5, false, actor),
				"discard_source": "HAND",
			},
		},
		{
			"label": "CHI.tiles[0]",
			"action_kind": "CHI",
			"resolved": {
				"meld": _meld_with_tile_iid(
					_meld_view_ns(hs, "CHI", 0, other), 0, out_low
				),
			},
		},
		{
			"label": "PON.called_tile",
			"action_kind": "PON",
			# called 默认在 tiles 末位（serial 30）；改 called 同步 tiles 内引用
			"resolved": {
				"meld": _meld_with_tile_iid(
					_meld_view_ns(hs, "PON", 0, other), 2, out_high
				),
			},
		},
		{
			"label": "KAN.MINKAN.tiles[1]",
			"action_kind": "KAN",
			"resolved": {
				"meld": _meld_with_tile_iid(
					_meld_view_ns(hs, "MINKAN", 0, other), 1, out_low
				),
			},
		},
		{
			"label": "KAN.ANKAN.tiles[3]",
			"action_kind": "KAN",
			"resolved": {
				"meld": _meld_with_tile_iid(
					_meld_view_ns(hs, "ANKAN", 0, -1), 3, out_high
				),
			},
		},
		{
			"label": "KAN.ADDED_KAN.added_tile",
			"action_kind": "KAN",
			# ADDED_KAN tiles 末位是 added（serial 40）
			"resolved": {
				"meld": _meld_with_tile_iid(
					_meld_view_ns(hs, "ADDED_KAN", 0, other), 3, out_low
				),
			},
		},
		{
			"label": "RON.winning_tile",
			"action_kind": "RON",
			"resolved": {
				"winning_tile": _tile_view(out_low, TileId.S5, false, other),
				"from_seat": other,
			},
		},
		{
			"label": "TSUMO.winning_tile",
			"action_kind": "TSUMO",
			"resolved": {
				"winning_tile": _tile_view(out_high, TileId.S5, false, actor),
			},
		},
	]
	for c in cases:
		var cd: Dictionary = c
		var payload: Dictionary = _action_applied_payload(
			str(cd["action_kind"]), cd["resolved"] as Dictionary, actor, hs
		)
		assert_null(
			NetworkedEvent.from_dict(_flat_event("ACTION_APPLIED", 9, payload)),
			"ACTION_APPLIED %s 超出 hand_seq 命名空间必须拒绝" % str(cd["label"])
		)

	# 正例：每类至少一合法边界 fixture（实体全在 [lo,hi]）
	var ok_cases: Array = [
		{
			"label": "RIICHI.boundary",
			"action_kind": "RIICHI",
			"resolved": {
				"tile": _tile_view(hi, TileId.W5, false, actor),
				"discard_source": "DRAWN",
			},
		},
		{
			"label": "CHI.ns",
			"action_kind": "CHI",
			"resolved": {"meld": _meld_view_ns(hs, "CHI", 0, other)},
		},
		{
			"label": "PON.ns",
			"action_kind": "PON",
			"resolved": {"meld": _meld_view_ns(hs, "PON", 0, other)},
		},
		{
			"label": "KAN.MINKAN.ns",
			"action_kind": "KAN",
			"resolved": {"meld": _meld_view_ns(hs, "MINKAN", 0, other)},
		},
		{
			"label": "KAN.ANKAN.ns",
			"action_kind": "KAN",
			"resolved": {"meld": _meld_view_ns(hs, "ANKAN", 0, -1)},
		},
		{
			"label": "KAN.ADDED_KAN.ns",
			"action_kind": "KAN",
			"resolved": {"meld": _meld_view_ns(hs, "ADDED_KAN", 0, other)},
		},
		{
			"label": "RON.boundary",
			"action_kind": "RON",
			"resolved": {
				"winning_tile": _tile_view(lo, TileId.S5, false, other),
				"from_seat": other,
			},
		},
		{
			"label": "TSUMO.boundary",
			"action_kind": "TSUMO",
			"resolved": {
				"winning_tile": _tile_view(hi, TileId.S5, false, actor),
			},
		},
	]
	for c in ok_cases:
		var od: Dictionary = c
		assert_not_null(NetworkedEvent.from_dict(_flat_event(
			"ACTION_APPLIED", 9, _action_applied_payload(
				str(od["action_kind"]), od["resolved"] as Dictionary, actor, hs
			)
		)), "ACTION_APPLIED %s 命名空间内实体合法" % str(od["label"]))


func test_room_snapshot_rejects_entities_outside_hand_seq_namespace() -> void:
	var seq := 15
	# hand_seq=1 但 seats 用 hand_seq=0 的 default ids
	var seats := _default_seats(0, 0)
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 1, "DRAW", seats)),
		])
	)), "ROOM_SNAPSHOT 手牌实体超出 hand_seq 命名空间拒绝")
	# dora 越界
	var ok_seats := _default_seats(0, 1)
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 1, "DRAW", ok_seats, [
				_tile_view(10, TileId.W5, false, -1), # 不在 [136,271]
			])),
		])
	)), "ROOM_SNAPSHOT dora 超出命名空间拒绝")
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 1)),
		])
	)), "ROOM_SNAPSHOT 命名空间正例")


func test_room_snapshot_rejects_duplicate_entities_across_zones() -> void:
	# 跨手牌/河/副露/dora 实体必须全局唯一（ura 字段当前 schema 不表达，仅 dora）
	var seq := 16
	var hs := 0
	var shared := _ns(hs, 40)
	var seats := _default_seats(0, hs)
	# 河与手牌撞 id
	(seats[0] as Dictionary)["river"] = [_tile_view(shared, TileId.W9, false, 0)]
	(seats[0] as Dictionary)["concealed_tiles"] = [
		_tile_view(shared, TileId.W1, false, 0),
		_tile_view(_ns(hs, 11), TileId.W2, false, 0),
	]
	(seats[0] as Dictionary)["concealed_count"] = 2
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, hs, "DRAW", seats)),
		])
	)), "手牌与河实体 id 重复必须拒绝")

	# dora 与手牌撞
	var seats2 := _default_seats(0, hs)
	var dora_hit := int(((seats2[0] as Dictionary)["concealed_tiles"] as Array)[0]["instance_id"])
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, hs, "DRAW", seats2, [
				_tile_view(dora_hit, TileId.W5, false, -1),
			])),
		])
	)), "dora 与手牌实体 id 重复必须拒绝")

	# 跨席河重复
	var seats3 := _default_seats(0, hs)
	(seats3[0] as Dictionary)["river"] = [_tile_view(_ns(hs, 70), TileId.W1, false, 0)]
	(seats3[1] as Dictionary)["river"] = [_tile_view(_ns(hs, 70), TileId.W1, false, 1)]
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, hs, "DRAW", seats3)),
		])
	)), "跨席河实体 id 重复必须拒绝")

	# 副露 tiles 与河撞
	var seats4 := _default_seats(0, hs)
	(seats4[0] as Dictionary)["river"] = [_tile_view(_ns(hs, 80), TileId.W9, false, 0)]
	(seats4[0] as Dictionary)["melds"] = [_meld_view_ns(hs, "PON", 0, 1, 80, 40)]
	# called serial 80 → same as river
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, hs, "DRAW", seats4)),
		])
	)), "副露与河实体 id 重复必须拒绝")


func test_room_snapshot_rejects_duplicate_meld_id_same_seat() -> void:
	# 干净 paired baseline：PON(W8)/CHI(T2-T4) 各自合法、不同 physical 组、不撞 dora
	# holder seat0 → CHI from=3 上家；先不同 meld_id 正例，再仅改 CHI.meld_id=0 负例
	var seq := 17
	var hs := 0
	var pon := _meld_view_ns(hs, "PON", 0, 1, 30) # called_serial 30 → W8
	var chi := _meld_view_ns(hs, "CHI", 1, 3, 48) # called_serial 48 → T4 → T2-T3-T4
	var seats: Array = []
	for i in range(4):
		if i == 0:
			seats.append(_seat_view(
				0, SEAT_WINDS[0], 25000, 0, [], -1,
				[pon, chi],
				[], false, false, -1
			))
		else:
			seats.append(_seat_view(
				i, SEAT_WINDS[i], 25000, 13, [], -1, [], [], false, false, -1
			))
	var dora: Array = [_tile_view(_ns(hs, 1), TileId.W5, false, -1)]
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, hs, "DRAW", seats, dora)),
		])
	)), "同席不同 meld_id 合法")
	# 仅将 CHI meld_id 改为 0，与 PON 冲突；其余保持合法
	var chi_dup: Dictionary = chi.duplicate(true)
	chi_dup["meld_id"] = 0
	(seats[0] as Dictionary)["melds"] = [pon, chi_dup]
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, hs, "DRAW", seats, dora)),
		])
	)), "同席 meld_id 重复必须拒绝")


# 公开 core_table 合理硬上限（非阶段精确牌数）：
# live_wall_count 0..70；dora_indicators 1..5；每席 concealed_count 0..14；
# 每席 river 0..70；每席 melds 0..4。边界正例 + 超一反例。
func test_room_snapshot_freezes_core_table_public_hard_caps() -> void:
	var seq := 50

	# ---- live_wall_count 0..70 ----
	var core_lw0 := _core_table_payload(0, 10)
	core_lw0["live_wall_count"] = 0
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [_core_module(core_lw0)])
	)), "live_wall_count=0 合法")
	var core_lw70 := _core_table_payload(0, 10)
	core_lw70["live_wall_count"] = 70
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [_core_module(core_lw70)])
	)), "live_wall_count=70 合法")
	var core_lw71 := _core_table_payload(0, 10)
	core_lw71["live_wall_count"] = 71
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [_core_module(core_lw71)])
	)), "live_wall_count=71 拒绝")

	# ---- dora_indicators 1..5 ----
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [_core_module(_core_table_payload(0, 11))])
	)), "dora_indicators size=1 合法")
	var dora5: Array = []
	for i in range(5):
		dora5.append(_tile_view(_ns(12, i), TileId.W5, false, -1))
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 12, "DRAW", [], dora5)),
		])
	)), "dora_indicators size=5 合法")
	var dora6: Array = dora5.duplicate(true)
	dora6.append(_tile_view(_ns(12, 5), TileId.W6, false, -1))
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 12, "DRAW", [], dora6)),
		])
	)), "dora_indicators size=6 拒绝")
	var core_dora0 := _core_table_payload(0, 13)
	core_dora0["dora_indicators"] = []
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [_core_module(core_dora0)])
	)), "dora_indicators size=0 拒绝")

	# ---- 每席 concealed_count 0..14 ----
	var seats_c0: Array = []
	for i in range(4):
		seats_c0.append(_seat_view(
			i, SEAT_WINDS[i], 25000, 0, [], -1, [], [], false, false, -1
		))
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 14, "DRAW", seats_c0, [
				_tile_view(_ns(14, 0), TileId.W5, false, -1),
			])),
		])
	)), "concealed_count=0 合法")
	var tiles14: Array = []
	for i in range(14):
		tiles14.append(_tile_view(_ns(15, i), TileId.W1, false, 0))
	var seats_c14: Array = []
	for i in range(4):
		if i == 0:
			seats_c14.append(_seat_view(
				0, SEAT_WINDS[0], 25000, 14, tiles14, -1, [], [], false, false, -1
			))
		else:
			# 非 recipient 仅 count；边界 14
			seats_c14.append(_seat_view(
				i, SEAT_WINDS[i], 25000, 14, [], -1, [], [], false, false, -1
			))
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 15, "DRAW", seats_c14, [
				_tile_view(_ns(15, 20), TileId.W5, false, -1),
			])),
		])
	)), "concealed_count=14 合法")
	var tiles15: Array = []
	for i in range(15):
		tiles15.append(_tile_view(_ns(16, i), TileId.W1, false, 0))
	var seats_c15: Array = []
	for i in range(4):
		if i == 0:
			seats_c15.append(_seat_view(
				0, SEAT_WINDS[0], 25000, 15, tiles15, -1, [], [], false, false, -1
			))
		else:
			seats_c15.append(_seat_view(
				i, SEAT_WINDS[i], 25000, 0, [], -1, [], [], false, false, -1
			))
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 16, "DRAW", seats_c15, [
				_tile_view(_ns(16, 20), TileId.W5, false, -1),
			])),
		])
	)), "concealed_count=15 拒绝")
	# 非 recipient count-only 超一
	var seats_nr15: Array = []
	for i in range(4):
		seats_nr15.append(_seat_view(
			i, SEAT_WINDS[i], 25000, 15 if i != 0 else 0, [], -1, [], [], false, false, -1
		))
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 17, "DRAW", seats_nr15, [
				_tile_view(_ns(17, 0), TileId.W5, false, -1),
			])),
		])
	)), "非 recipient concealed_count=15 拒绝")

	# ---- 每席 river 0..70（拆 hand_seq 以容纳实体）----
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 18, "DRAW", seats_c0.duplicate(true), [
				_tile_view(_ns(18, 0), TileId.W5, false, -1),
			])),
		])
	)), "river size=0 合法")
	var river70: Array = []
	for i in range(70):
		river70.append(_tile_view(_ns(19, i), TileId.W1, false, 0))
	var seats_r70: Array = []
	for i in range(4):
		if i == 0:
			seats_r70.append(_seat_view(
				0, SEAT_WINDS[0], 25000, 0, [], -1, [], river70, false, false, -1
			))
		else:
			seats_r70.append(_seat_view(
				i, SEAT_WINDS[i], 25000, 0, [], -1, [], [], false, false, -1
			))
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 19, "DRAW", seats_r70, [
				_tile_view(_ns(19, 70), TileId.W5, false, -1),
			])),
		])
	)), "river size=70 合法")
	var river71: Array = []
	for i in range(71):
		river71.append(_tile_view(_ns(20, i), TileId.W1, false, 0))
	var seats_r71: Array = []
	for i in range(4):
		if i == 0:
			seats_r71.append(_seat_view(
				0, SEAT_WINDS[0], 25000, 0, [], -1, [], river71, false, false, -1
			))
		else:
			seats_r71.append(_seat_view(
				i, SEAT_WINDS[i], 25000, 0, [], -1, [], [], false, false, -1
			))
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 20, "DRAW", seats_r71, [
				_tile_view(_ns(20, 71), TileId.W5, false, -1),
			])),
		])
	)), "river size=71 拒绝")

	# ---- 每席 melds 0..4 ----
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 21, "DRAW", seats_c0.duplicate(true), [
				_tile_view(_ns(21, 0), TileId.W5, false, -1),
			])),
		])
	)), "melds size=0 合法")
	var melds4: Array = []
	for m in range(4):
		var base: int = m * 4
		var tid: int = TileId.W1 + m
		melds4.append({
			"meld_id": m,
			"kind": "ANKAN",
			"from_seat": -1,
			"called_tile_instance_id": -1,
			"added_tile_instance_id": -1,
			"tiles": [
				_tile_view(_ns(22, base), tid, false, 0),
				_tile_view(_ns(22, base + 1), tid, false, 0),
				_tile_view(_ns(22, base + 2), tid, false, 0),
				_tile_view(_ns(22, base + 3), tid, false, 0),
			],
		})
	var seats_m4: Array = []
	for i in range(4):
		if i == 0:
			seats_m4.append(_seat_view(
				0, SEAT_WINDS[0], 25000, 0, [], -1, melds4, [], false, false, -1
			))
		else:
			seats_m4.append(_seat_view(
				i, SEAT_WINDS[i], 25000, 0, [], -1, [], [], false, false, -1
			))
	assert_not_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 22, "DRAW", seats_m4, [
				_tile_view(_ns(22, 16), TileId.W5, false, -1),
			])),
		])
	)), "melds size=4 合法")
	var melds5: Array = melds4.duplicate(true)
	melds5.append({
		"meld_id": 4,
		"kind": "ANKAN",
		"from_seat": -1,
		"called_tile_instance_id": -1,
		"added_tile_instance_id": -1,
		"tiles": [
			_tile_view(_ns(22, 20), TileId.T1, false, 0),
			_tile_view(_ns(22, 21), TileId.T1, false, 0),
			_tile_view(_ns(22, 22), TileId.T1, false, 0),
			_tile_view(_ns(22, 23), TileId.T1, false, 0),
		],
	})
	var seats_m5: Array = []
	for i in range(4):
		if i == 0:
			seats_m5.append(_seat_view(
				0, SEAT_WINDS[0], 25000, 0, [], -1, melds5, [], false, false, -1
			))
		else:
			seats_m5.append(_seat_view(
				i, SEAT_WINDS[i], 25000, 0, [], -1, [], [], false, false, -1
			))
	assert_null(NetworkedEvent.from_dict(_room_snapshot_event(
		seq, _room_snapshot_payload(seq, 0, [
			_core_module(_core_table_payload(0, 22, "DRAW", seats_m5, [
				_tile_view(_ns(22, 30), TileId.W5, false, -1),
			])),
		])
	)), "melds size=5 拒绝")
