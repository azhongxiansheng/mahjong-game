extends GutTest

# E2 JSON transport decoder 契约（实体 Action + view_hash NetworkedEvent）
# 冻结 API：
#   decode_action(String) -> Action / null
#   decode_event(String) -> NetworkedEvent / null
# JSON 数字→int 安全规范化仅允许有限整数；实体字段小数拒绝。

const JsonTransportDecoder := preload("res://protocol/json_transport_decoder.gd")
const ViewCodecScript := preload("res://protocol/protocol_view_codec.gd")

const CMD := "550e8400-e29b-41d4-a716-446655440000"
const DECISION := "550e8400-e29b-41d4-a716-4466554400aa"
const ROOM := "room_x"
const WINDOW_ID := "w-decode-1"
const VIEW_HASH := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
const PRIZE_POOL := ["item_a", "item_b", "item_c", "item_d"]
const MAX_HAND_SEQ := 66229406284859
const MAX_SAFE_INT := 9007199254740991
const TILES_PER_HAND := 136


func _ns(hand_seq: int, serial: int) -> int:
	return hand_seq * TILES_PER_HAND + serial


## serial = iid % 136；tile = ALL[serial/4]；owner = serial%4；W5/T5/S5 copy0 赤
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


## iid = ALL.find(tile_id)*4 + copy + hand_seq*136
func _canonical_tile_view(tile_id: int, copy_index: int, hand_seq: int) -> Dictionary:
	var iid: int = TileId.ALL.find(tile_id) * 4 + copy_index + hand_seq * TILES_PER_HAND
	return _canonical_tile_view_for_iid(iid)


func _action_wire(kind: String, payload: Dictionary, seat: int = 0, client_seq: int = 1, hand_seq: int = 0) -> Dictionary:
	return {
		"protocol_version": 1,
		"command_id": CMD,
		"room_id": ROOM,
		"seat": seat,
		"hand_seq": hand_seq,
		"decision_id": DECISION,
		"kind": kind,
		"payload": payload.duplicate(true),
		"client_seq": client_seq,
	}


func _event_wire(kind: String, seq: int, payload: Dictionary) -> Dictionary:
	return {
		"protocol_version": 1,
		"server_seq": seq,
		"room_id": ROOM,
		"kind": kind,
		"payload": payload.duplicate(true),
		"view_hash": VIEW_HASH,
	}


func _action_json_from_wire(wire: Dictionary) -> String:
	return JSON.stringify(wire)


func _event_json_from_wire(wire: Dictionary) -> String:
	return JSON.stringify(wire)


func _snapshot_seat(seat: int, recipient: int, hand_seq: int = 2) -> Dictionary:
	var concealed: Array = []
	var concealed_count := 13
	var last_drawn := -1
	var river: Array = []
	var melds: Array = []
	if seat == recipient:
		# 可见 iid 全局不冲突：dora serial1；此席 concealed/river/CHI 另占
		var c_tv: Dictionary = _canonical_tile_view(TileId.S1, 0, hand_seq)
		var r_tv: Dictionary = _canonical_tile_view(TileId.T9, 0, hand_seq)
		var m0: Dictionary = _canonical_tile_view(TileId.W2, 0, hand_seq)
		var m1: Dictionary = _canonical_tile_view(TileId.W3, 0, hand_seq)
		var m2: Dictionary = _canonical_tile_view(TileId.W4, 0, hand_seq)
		var called_iid: int = int(m2["instance_id"])
		var from_seat: int = (seat + 3) % 4
		concealed = [c_tv]
		concealed_count = 1
		last_drawn = int(c_tv["instance_id"])
		river = [r_tv]
		melds = [{
			"meld_id": 0,
			"kind": "CHI",
			"from_seat": from_seat,
			"called_tile_instance_id": called_iid,
			"added_tile_instance_id": -1,
			"tiles": [m0, m1, m2],
		}]
	return {
		"seat": seat,
		"seat_wind": [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N][seat],
		"score": 25000,
		"concealed_tiles": concealed,
		"concealed_count": concealed_count,
		"last_drawn_tile_instance_id": last_drawn,
		"river": river,
		"melds": melds,
		"riichi_declared": false,
		"riichi_double": false,
		"riichi_discard_index": -1,
	}


func _room_snapshot_payload(
	seq: int = 7,
	recipient: int = 0,
	unknown_payload: Variant = null
) -> Dictionary:
	var hs := 2
	var seats: Array = []
	for seat in range(4):
		seats.append(_snapshot_seat(seat, recipient, hs))
	var modules: Array = [{
		"module_key": "core_table",
		"schema_version": 1,
		"payload": {
			"recipient_seat": recipient,
			"hand_seq": hs,
			"dealer_seat": 0,
			"current_seat": 1,
			"phase": "DISCARD",
			"round_wind": TileId.E,
			"hand_number": 1,
			"honba": 0,
			"riichi_sticks": 0,
			"live_wall_count": 69,
			"dora_indicators": [_canonical_tile_view_for_iid(_ns(hs, 1))],
			"seats": seats,
		},
	}]
	if unknown_payload != null:
		modules.append({
			"module_key": "z_test_ext",
			"schema_version": 2,
			"payload": unknown_payload,
		})
	return {
		"snapshot_server_seq": seq,
		"next_server_seq": seq + 1,
		"seat_view": recipient,
		"modules": modules,
	}


func _assert_int_field(d: Dictionary, key: String, expected: int, msg: String = "") -> void:
	var v = d.get(key)
	assert_eq(typeof(v), TYPE_INT, msg if not msg.is_empty() else "%s 应为 TYPE_INT" % key)
	assert_eq(int(v), expected, msg if not msg.is_empty() else "%s 值" % key)


# --- Action 成功路径 ---

func test_decode_action_discard_entity_success() -> void:
	var iid: int = _ns(3, 7)
	var wire := _action_wire("DISCARD", {"tile_instance_id": iid}, 1, 42, 3)
	var decoded: Action = JsonTransportDecoder.decode_action(_action_json_from_wire(wire))
	assert_not_null(decoded, "DISCARD 实体 Action JSON 应成功解码")
	if decoded == null:
		return
	assert_eq(decoded.kind, "DISCARD")
	assert_eq(decoded.seat, 1)
	assert_eq(decoded.client_seq, 42)
	assert_eq(decoded.hand_seq, 3)
	assert_eq(decoded.decision_id, DECISION)
	_assert_int_field(decoded.payload, "tile_instance_id", iid)


func test_decode_action_riichi_entity_success() -> void:
	var iid: int = _ns(1, 12)
	var wire := _action_wire("RIICHI", {"tile_instance_id": iid}, 0, 3, 1)
	var decoded: Action = JsonTransportDecoder.decode_action(_action_json_from_wire(wire))
	assert_not_null(decoded, "RIICHI 应成功解码")
	if decoded == null:
		return
	assert_eq(decoded.kind, "RIICHI")
	_assert_int_field(decoded.payload, "tile_instance_id", iid)


func test_decode_action_chi_companion_sorted_success() -> void:
	var c0: int = _ns(2, 3)
	var c1: int = _ns(2, 4)
	var wire := _action_wire("CHI", {"companion_tile_instance_ids": [c1, c0]}, 2, 10, 2)
	var decoded: Action = JsonTransportDecoder.decode_action(_action_json_from_wire(wire))
	assert_not_null(decoded, "CHI companion 两元素应成功解码")
	if decoded == null:
		return
	assert_eq(decoded.kind, "CHI")
	var companions: Array = decoded.payload.get("companion_tile_instance_ids", [])
	assert_eq(companions.size(), 2)
	assert_eq(typeof(companions[0]), TYPE_INT)
	assert_eq(typeof(companions[1]), TYPE_INT)
	assert_eq(int(companions[0]), c0)
	assert_eq(int(companions[1]), c1)


func test_decode_action_pon_success() -> void:
	var wire := _action_wire("PON", {"companion_tile_instance_ids": [8, 9]}, 1, 7)
	var decoded: Action = JsonTransportDecoder.decode_action(_action_json_from_wire(wire))
	assert_not_null(decoded, "PON 应成功解码")
	if decoded == null:
		return
	assert_eq(decoded.kind, "PON")
	var companions: Array = decoded.payload.get("companion_tile_instance_ids", [])
	assert_eq(companions.size(), 2)


func test_decode_action_ron_tsumo_pass_empty_payload_success() -> void:
	for kind in ["RON", "TSUMO", "PASS"]:
		var wire := _action_wire(kind, {}, 2, 11)
		var decoded: Action = JsonTransportDecoder.decode_action(_action_json_from_wire(wire))
		assert_not_null(decoded, "%s 应成功解码" % kind)
		if decoded != null:
			assert_eq(decoded.payload.keys().size(), 0)


func test_decode_action_kan_three_kinds_success() -> void:
	var minkan := _action_wire("KAN", {
		"kan_kind": "MINKAN",
		"companion_tile_instance_ids": [3, 1, 2],
	}, 0, 99)
	var d1: Action = JsonTransportDecoder.decode_action(_action_json_from_wire(minkan))
	assert_not_null(d1, "KAN MINKAN 应成功解码")
	if d1 != null:
		assert_eq(str(d1.payload.get("kan_kind", "")), "MINKAN")
		var c: Array = d1.payload.get("companion_tile_instance_ids", [])
		assert_eq(c.size(), 3)
		assert_eq(int(c[0]), 1)

	var ankan := _action_wire("KAN", {
		"kan_kind": "ANKAN",
		"tile_instance_ids": [4, 1, 3, 2],
	}, 3, 5)
	var d2: Action = JsonTransportDecoder.decode_action(_action_json_from_wire(ankan))
	assert_not_null(d2, "KAN ANKAN 应成功解码")
	if d2 != null:
		assert_eq(str(d2.payload.get("kan_kind", "")), "ANKAN")
		assert_eq((d2.payload.get("tile_instance_ids", []) as Array).size(), 4)

	var added := _action_wire("KAN", {
		"kan_kind": "ADDED_KAN",
		"meld_id": 2,
		"added_tile_instance_id": 77,
	}, 1, 6)
	var d3: Action = JsonTransportDecoder.decode_action(_action_json_from_wire(added))
	assert_not_null(d3, "KAN ADDED_KAN 应成功解码")
	if d3 != null:
		_assert_int_field(d3.payload, "meld_id", 2)
		_assert_int_field(d3.payload, "added_tile_instance_id", 77)


# --- Action 拒绝路径 ---

func test_decode_action_tile_instance_id_float_rejected() -> void:
	var raw := (
		'{"protocol_version":1,"command_id":"%s","room_id":"%s","seat":0,'
		+ '"hand_seq":0,"decision_id":"%s","kind":"DISCARD",'
		+ '"payload":{"tile_instance_id":1.5},"client_seq":1}'
	) % [CMD, ROOM, DECISION]
	assert_null(JsonTransportDecoder.decode_action(raw), "tile_instance_id=1.5 应拒绝")


func test_decode_action_old_tile_id_schema_rejected() -> void:
	var raw := (
		'{"protocol_version":1,"command_id":"%s","room_id":"%s","seat":0,'
		+ '"hand_seq":0,"decision_id":"%s","kind":"DISCARD",'
		+ '"payload":{"tile_id":1,"is_red_dora":false},"client_seq":1}'
	) % [CMD, ROOM, DECISION]
	assert_null(JsonTransportDecoder.decode_action(raw), "旧 tile_id schema 应拒绝")


func test_decode_action_missing_hand_seq_or_decision_id_rejected() -> void:
	var no_hand := (
		'{"protocol_version":1,"command_id":"%s","room_id":"%s","seat":0,'
		+ '"decision_id":"%s","kind":"PASS","payload":{},"client_seq":1}'
	) % [CMD, ROOM, DECISION]
	assert_null(JsonTransportDecoder.decode_action(no_hand), "缺 hand_seq 应拒绝")

	var no_dec := (
		'{"protocol_version":1,"command_id":"%s","room_id":"%s","seat":0,'
		+ '"hand_seq":0,"kind":"PASS","payload":{},"client_seq":1}'
	) % [CMD, ROOM]
	assert_null(JsonTransportDecoder.decode_action(no_dec), "缺 decision_id 应拒绝")


func test_decode_action_client_seq_beyond_safe_integer_rejected() -> void:
	var raw := (
		'{"protocol_version":1,"command_id":"%s","room_id":"%s","seat":0,'
		+ '"hand_seq":0,"decision_id":"%s","kind":"DISCARD",'
		+ '"payload":{"tile_instance_id":1},"client_seq":9007199254740992}'
	) % [CMD, ROOM, DECISION]
	assert_null(JsonTransportDecoder.decode_action(raw), "client_seq 超安全整数应拒绝")

	# MAX_SAFE 边界与 hand_seq MAX_HAND_SEQ
	var max_client := _action_wire("PASS", {}, 0, MAX_SAFE_INT, 0)
	assert_not_null(
		JsonTransportDecoder.decode_action(_action_json_from_wire(max_client)),
		"client_seq=MAX_SAFE 合法"
	)
	var max_hand := _action_wire("PASS", {}, 0, 1, MAX_HAND_SEQ)
	assert_not_null(
		JsonTransportDecoder.decode_action(_action_json_from_wire(max_hand)),
		"hand_seq=MAX_HAND_SEQ 合法"
	)
	var over_hand := _action_wire("PASS", {}, 0, 1, MAX_HAND_SEQ + 1)
	assert_null(
		JsonTransportDecoder.decode_action(_action_json_from_wire(over_hand)),
		"hand_seq=MAX_HAND_SEQ+1 拒绝"
	)


func test_decode_action_seat_beyond_safe_integer_rejected() -> void:
	var raw := (
		'{"protocol_version":1,"command_id":"%s","room_id":"%s","seat":9007199254740992,'
		+ '"hand_seq":0,"decision_id":"%s","kind":"DISCARD",'
		+ '"payload":{"tile_instance_id":1},"client_seq":1}'
	) % [CMD, ROOM, DECISION]
	assert_null(JsonTransportDecoder.decode_action(raw), "seat 超出 2^53-1 应拒绝")


func test_decode_action_uppercase_uuid_returns_null() -> void:
	var upper_cmd := "550E8400-E29B-41D4-A716-446655440000"
	var upper_dec := "550E8400-E29B-41D4-A716-4466554400AA"
	var wire := _action_wire("PASS", {})
	wire["command_id"] = upper_cmd
	wire["decision_id"] = upper_dec
	assert_null(
		JsonTransportDecoder.decode_action(_action_json_from_wire(wire)),
		"大写 UUID Action JSON 必须返回 null"
	)

	var only_cmd := _action_wire("PASS", {})
	only_cmd["command_id"] = upper_cmd
	assert_null(
		JsonTransportDecoder.decode_action(_action_json_from_wire(only_cmd)),
		"仅大写 command_id 拒绝"
	)
	var only_dec := _action_wire("PASS", {})
	only_dec["decision_id"] = upper_dec
	assert_null(
		JsonTransportDecoder.decode_action(_action_json_from_wire(only_dec)),
		"仅大写 decision_id 拒绝"
	)


func test_decode_action_non_v4_and_bad_variant_uuid_returns_null() -> void:
	var non_v4 := _action_wire("PASS", {})
	non_v4["command_id"] = "550e8400-e29b-11d4-a716-446655440000"
	assert_null(
		JsonTransportDecoder.decode_action(_action_json_from_wire(non_v4)),
		"JSON command_id version≠4 拒绝"
	)
	var non_v4_dec := _action_wire("PASS", {})
	non_v4_dec["decision_id"] = "550e8400-e29b-11d4-a716-4466554400aa"
	assert_null(
		JsonTransportDecoder.decode_action(_action_json_from_wire(non_v4_dec)),
		"JSON decision_id version≠4 拒绝"
	)

	var bad_var7 := _action_wire("PASS", {})
	bad_var7["command_id"] = "550e8400-e29b-41d4-7716-446655440000"
	assert_null(
		JsonTransportDecoder.decode_action(_action_json_from_wire(bad_var7)),
		"JSON command_id variant 7xxx 拒绝"
	)
	var bad_var_c := _action_wire("PASS", {})
	bad_var_c["decision_id"] = "550e8400-e29b-41d4-c716-4466554400aa"
	assert_null(
		JsonTransportDecoder.decode_action(_action_json_from_wire(bad_var_c)),
		"JSON decision_id variant cxxx 拒绝"
	)

	# 正例：lowercase v4+variant JSON 仍成功
	assert_not_null(
		JsonTransportDecoder.decode_action(_action_json_from_wire(_action_wire("PASS", {}))),
		"lowercase v4 Action JSON 正例"
	)


func test_decode_action_session_kinds_rejected() -> void:
	for kind in ["JOIN", "READY", "RESYNC_REQUEST"]:
		var wire := _action_wire(kind, {})
		assert_null(
			JsonTransportDecoder.decode_action(_action_json_from_wire(wire)),
			"%s 必须拒绝" % kind
		)


func test_decode_action_malformed_json_rejected() -> void:
	assert_null(JsonTransportDecoder.decode_action("{not valid json"), "错误 JSON 应拒绝")


func test_decode_action_array_root_rejected() -> void:
	assert_null(JsonTransportDecoder.decode_action("[1,2,3]"), "数组根应拒绝")


# --- Event 成功路径 ---

func test_decode_event_action_applied_resolved_payload_success() -> void:
	var hs := 2
	var iid: int = _ns(hs, 9)
	var wire := _event_wire("ACTION_APPLIED", 100, {
		"causation_command_id": CMD,
		"hand_seq": hs,
		"decision_id": DECISION,
		"seat": 1,
		"action_kind": "DISCARD",
		"resolved_payload": {
			"tile": _canonical_tile_view_for_iid(iid),
			"discard_source": "HAND",
		},
	})
	var decoded: NetworkedEvent = JsonTransportDecoder.decode_event(_event_json_from_wire(wire))
	assert_not_null(decoded, "ACTION_APPLIED DISCARD resolved 应成功解码")
	if decoded == null:
		return
	assert_eq(decoded.kind, "ACTION_APPLIED")
	assert_eq(decoded.server_seq, 100)
	assert_eq(decoded.room_id, ROOM)
	var p: Dictionary = decoded.payload
	_assert_int_field(p, "seat", 1)
	_assert_int_field(p, "hand_seq", 2)
	assert_eq(str(p.get("action_kind", "")), "DISCARD")
	assert_true(p.get("resolved_payload") is Dictionary)
	var rp: Dictionary = p.get("resolved_payload")
	assert_true(rp.has("tile"))
	assert_eq(str(rp.get("discard_source", "")), "HAND")
	_assert_int_field(rp["tile"] as Dictionary, "instance_id", iid)
	var out: Dictionary = decoded.to_dict()
	assert_true(out.has("view_hash"))
	assert_eq(str(out.get("view_hash")).length(), 64)
	assert_false(out.has("state_hash"))


func test_decode_event_action_applied_pass_and_ron_success() -> void:
	var pass_wire := _event_wire("ACTION_APPLIED", 50, {
		"causation_command_id": CMD,
		"hand_seq": 1,
		"decision_id": DECISION,
		"seat": 2,
		"action_kind": "PASS",
		"resolved_payload": {},
	})
	var pass_ev: NetworkedEvent = JsonTransportDecoder.decode_event(
		_event_json_from_wire(pass_wire)
	)
	assert_not_null(pass_ev, "ACTION_APPLIED PASS 合法")
	if pass_ev != null:
		assert_eq((pass_ev.payload.get("resolved_payload") as Dictionary).keys().size(), 0)

	var ron_wire := _event_wire("ACTION_APPLIED", 51, {
		"causation_command_id": CMD,
		"hand_seq": 1,
		"decision_id": DECISION,
		"seat": 2,
		"action_kind": "RON",
		"resolved_payload": {
			"winning_tile": _canonical_tile_view_for_iid(_ns(1, 9)),
			"from_seat": 0,
		},
	})
	var ron_ev: NetworkedEvent = JsonTransportDecoder.decode_event(
		_event_json_from_wire(ron_wire)
	)
	assert_not_null(ron_ev, "ACTION_APPLIED RON from_seat 合法")
	if ron_ev != null:
		var rp: Dictionary = ron_ev.payload.get("resolved_payload") as Dictionary
		assert_true(rp.has("winning_tile"))
		assert_eq(int(rp.get("from_seat", -1)), 0)
		assert_false(rp.has("winner_seat"))


func test_decode_event_reward_window_opened_success() -> void:
	var wire := _event_wire("REWARD_WINDOW_OPENED", 10, {
		"window_id": WINDOW_ID,
		"hand_seq": 3,
		"window_index": 1,
		"prize_pool": PRIZE_POOL.duplicate(),
		"rule_version": "reward_v2",
		"phase": "OPEN",
		"window_exit": null,
	})
	var decoded: NetworkedEvent = JsonTransportDecoder.decode_event(_event_json_from_wire(wire))
	assert_not_null(decoded, "REWARD_WINDOW_OPENED 应成功解码")
	if decoded == null:
		return
	assert_eq(decoded.kind, "REWARD_WINDOW_OPENED")
	_assert_int_field(decoded.payload, "hand_seq", 3)
	_assert_int_field(decoded.payload, "window_index", 1)


func test_decode_event_reward_window_closing_success() -> void:
	var wire := _event_wire("REWARD_WINDOW_CLOSING", 110, {
		"window_id": WINDOW_ID,
		"hand_seq": 3,
		"closing_boundary_server_seq": 110,
		"grace_deadline_at": "2026-07-22T12:00:01.500Z",
		"phase": "CLOSING",
		"window_exit": null,
	})
	var decoded: NetworkedEvent = JsonTransportDecoder.decode_event(_event_json_from_wire(wire))
	assert_not_null(decoded, "REWARD_WINDOW_CLOSING 应成功解码")
	if decoded == null:
		return
	_assert_int_field(decoded.payload, "hand_seq", 3)
	_assert_int_field(decoded.payload, "closing_boundary_server_seq", 110)


func test_decode_event_reward_window_settled_success() -> void:
	var wire := _event_wire("REWARD_WINDOW_SETTLED", 120, {
		"window_id": WINDOW_ID,
		"outcome": "FULL_GRANT",
		"settle_reason": "FULL_24_NO_WIN",
		"rule_version": "reward_v2",
		"assignment_version": "assign_v1",
		"prize_pool": PRIZE_POOL.duplicate(),
		"matrix_summary": {
			"scores": [
				[1000, 0, 0, 0],
				[0, 1000, 0, 0],
				[0, 0, 1000, 0],
				[0, 0, 0, 1000],
			],
		},
		"assignment": {"0": "item_a", "1": "item_b", "2": "item_c", "3": "item_d"},
		"closing_boundary_server_seq": 110,
		"context_boundary_server_seq": 118,
		"grace_deadline_at": "2026-07-22T12:00:01.500Z",
		"grant_count": 4,
		"hand_seq": 3,
		"transcript_summary": {},
	})
	var decoded: NetworkedEvent = JsonTransportDecoder.decode_event(_event_json_from_wire(wire))
	assert_not_null(decoded, "REWARD_WINDOW_SETTLED 应成功解码")
	if decoded == null:
		return
	_assert_int_field(decoded.payload, "closing_boundary_server_seq", 110)
	_assert_int_field(decoded.payload, "grant_count", 4)
	var scores: Array = (decoded.payload.get("matrix_summary", {}) as Dictionary).get("scores", [])
	assert_true(scores.size() > 0)
	var row0: Array = scores[0]
	assert_eq(typeof(row0[0]), TYPE_INT, "SETTLED opaque 嵌套安全整数应规范化为 TYPE_INT")


func test_decode_event_reward_window_settled_opaque_json_domain_rejects_bad_numbers() -> void:
	for field_name in ["matrix_summary", "assignment", "transcript_summary"]:
		for invalid_number in [1.5, float(MAX_SAFE_INT) + 2.0]:
			var wire := _event_wire("REWARD_WINDOW_SETTLED", 120, {
				"window_id": WINDOW_ID,
				"outcome": "FULL_GRANT",
				"settle_reason": "FULL_24_NO_WIN",
				"rule_version": "reward_v2",
				"assignment_version": "assign_v1",
				"prize_pool": PRIZE_POOL.duplicate(),
				"matrix_summary": {},
				"assignment": {},
				"closing_boundary_server_seq": 110,
				"context_boundary_server_seq": 118,
				"grace_deadline_at": "2026-07-22T12:00:01.500Z",
				"grant_count": 4,
				"hand_seq": 3,
				"transcript_summary": {},
			})
			wire["payload"][field_name] = {"outer": [invalid_number]}
			assert_null(
				JsonTransportDecoder.decode_event(_event_json_from_wire(wire)),
				"%s 嵌套小数或越界数字必须拒绝" % field_name
			)


func test_decode_event_reward_window_cancelled_null_closing_boundary_success() -> void:
	var wire := _event_wire("REWARD_WINDOW_CANCELLED", 50, {
		"window_id": "w-cancel-1",
		"cancel_reason": "CANCELLED_BY_WIN",
		"closing_boundary_server_seq": null,
		"grace_aborted": true,
		"scored": false,
		"grant_count": 0,
		"hand_seq": 2,
	})
	var decoded: NetworkedEvent = JsonTransportDecoder.decode_event(_event_json_from_wire(wire))
	assert_not_null(decoded, "REWARD_WINDOW_CANCELLED closing_boundary=null 应成功")
	if decoded == null:
		return
	assert_true(decoded.payload.get("closing_boundary_server_seq") == null)
	_assert_int_field(decoded.payload, "hand_seq", 2)


func test_decode_event_item_granted_seat_hand_seq_score_success() -> void:
	var wire := _event_wire("ITEM_GRANTED", 20, {
		"window_id": "w-grant-1",
		"rule_version": "rv1",
		"assignment_version": "av1",
		"matched_rule_ids": ["r1"],
		"item_id": "item_x",
		"item_instance_id": "inst_x",
		"seat": 2,
		"hand_seq": 3,
		"score": 25000,
		"affinity_match": false,
		"armed_for_window_id": null,
	})
	var decoded: NetworkedEvent = JsonTransportDecoder.decode_event(_event_json_from_wire(wire))
	assert_not_null(decoded, "ITEM_GRANTED 应成功解码")
	if decoded == null:
		return
	_assert_int_field(decoded.payload, "seat", 2)
	_assert_int_field(decoded.payload, "hand_seq", 3)
	_assert_int_field(decoded.payload, "score", 25000)


func test_decode_event_room_snapshot_modules_convert_json_ints_and_preserve_hash() -> void:
	var unknown_payload := {
		"whole": 3,
		"nested": {"zero": 0, "negative": -2},
		"array": [1, -4, {"deep": 8}],
		"text": "3",
	}
	var payload := _room_snapshot_payload(7, 0, unknown_payload)
	var expected_hash: String = ViewCodecScript.compute_view_hash(payload)
	assert_eq(expected_hash.length(), 64, "stringify 前的严格 int payload 必须可计算 hash")
	var wire := _event_wire("ROOM_SNAPSHOT", 7, payload)
	wire["view_hash"] = expected_hash
	var decoded: NetworkedEvent = JsonTransportDecoder.decode_event(_event_json_from_wire(wire))
	assert_not_null(decoded, "模块化 ROOM_SNAPSHOT JSON 应成功解码且 hash 一致")
	if decoded == null:
		return
	var out: Dictionary = decoded.payload
	_assert_int_field(out, "snapshot_server_seq", 7)
	_assert_int_field(out, "next_server_seq", 8)
	_assert_int_field(out, "seat_view", 0)
	var modules: Array = out.get("modules", [])
	assert_eq(modules.size(), 2)
	var core_module: Dictionary = modules[0]
	_assert_int_field(core_module, "schema_version", 1)
	var core: Dictionary = core_module.get("payload", {})
	_assert_int_field(core, "hand_seq", 2)
	_assert_int_field(core, "live_wall_count", 69)
	var dora: Dictionary = (core.get("dora_indicators", []) as Array)[0]
	_assert_int_field(dora, "instance_id", _ns(2, 1))
	var recipient: Dictionary = (core.get("seats", []) as Array)[0]
	_assert_int_field(recipient, "score", 25000)
	var meld: Dictionary = (recipient.get("melds", []) as Array)[0]
	_assert_int_field(meld, "meld_id", 0)
	var unknown_module: Dictionary = modules[1]
	_assert_int_field(unknown_module, "schema_version", 2)
	var unknown: Dictionary = unknown_module.get("payload", {})
	_assert_int_field(unknown, "whole", 3)
	_assert_int_field(unknown.get("nested", {}), "negative", -2)
	_assert_int_field((unknown.get("array", []) as Array)[2], "deep", 8)
	assert_eq(str(unknown.get("text")), "3", "unknown module 不解释字符串业务键")
	assert_eq(decoded.view_hash, expected_hash)


func test_decode_event_room_snapshot_unknown_fractional_and_unsafe_numbers_rejected() -> void:
	for bad_value in [1.5, 9007199254740992]:
		var payload := _room_snapshot_payload(7, 0, {"bad": bad_value})
		var wire := _event_wire("ROOM_SNAPSHOT", 7, payload)
		assert_null(
			JsonTransportDecoder.decode_event(_event_json_from_wire(wire)),
			"unknown module 非安全整数应拒绝: %s" % str(bad_value)
		)


func test_decode_event_strict_recipient_dtos_convert_json_numbers() -> void:
	var joined: NetworkedEvent = JsonTransportDecoder.decode_event(_event_json_from_wire(
		_event_wire("PLAYER_JOINED", 21, {
			"seat": 2,
			"participant_kind": "HUMAN",
			"display_name": "Player 2",
			"connected": true,
		})
	))
	assert_not_null(joined, "PLAYER_JOINED JSON 整数应转换")
	if joined != null:
		_assert_int_field(joined.payload, "seat", 2)

	var hand: NetworkedEvent = JsonTransportDecoder.decode_event(_event_json_from_wire(
		_event_wire("HAND_SETTLED", 22, {
			"hand_seq": 4,
			"outcome": "RON",
			"winner_seats": [2],
			"loser_seat": 1,
			"score_deltas": [-1000, 0, 1000, 0],
			"scores": [24000, 25000, 26000, 25000],
			"dealer_seat": 0,
			"renchan": false,
			"honba": 0,
			"riichi_sticks": 0,
			"adjustments": [],
		})
	))
	assert_not_null(hand, "HAND_SETTLED JSON 整数与数组应转换")
	if hand != null:
		_assert_int_field(hand.payload, "hand_seq", 4)
		_assert_int_field({"winner": (hand.payload.get("winner_seats", []) as Array)[0]}, "winner", 2)
		_assert_int_field({"delta": (hand.payload.get("score_deltas", []) as Array)[0]}, "delta", -1000)

	var match_settled: NetworkedEvent = JsonTransportDecoder.decode_event(_event_json_from_wire(
		_event_wire("MATCH_SETTLED", 23, {
			"round_kind": "EAST",
			"final_scores": [33000, 27000, 22000, 18000],
			"seat_order": [0, 1, 2, 3],
		})
	))
	assert_not_null(match_settled, "MATCH_SETTLED JSON 整数数组应转换")
	if match_settled != null:
		_assert_int_field(
			{"score": (match_settled.payload.get("final_scores", []) as Array)[0]},
			"score",
			33000
		)


func test_decode_event_strict_recipient_dtos_reject_fractional_numbers() -> void:
	var bad_joined := _event_wire("PLAYER_JOINED", 21, {
		"seat": 1.5,
		"participant_kind": "HUMAN",
		"display_name": "Player",
		"connected": true,
	})
	assert_null(JsonTransportDecoder.decode_event(_event_json_from_wire(bad_joined)))

	var bad_hand := _event_wire("HAND_SETTLED", 22, {
		"hand_seq": 4,
		"outcome": "TSUMO",
		"winner_seats": [0],
		"loser_seat": -1,
		"score_deltas": [3000, -1000.5, -1000, -1000],
		"scores": [28000, 24000, 24000, 24000],
		"dealer_seat": 0,
		"renchan": true,
		"honba": 1,
		"riichi_sticks": 0,
		"adjustments": [],
	})
	assert_null(JsonTransportDecoder.decode_event(_event_json_from_wire(bad_hand)))

	var bad_match := _event_wire("MATCH_SETTLED", 23, {
		"round_kind": "EAST",
		"final_scores": [9007199254740992, 27000, 22000, 18000],
		"seat_order": [0, 1, 2, 3],
	})
	assert_null(JsonTransportDecoder.decode_event(_event_json_from_wire(bad_match)))


func test_decode_event_turn_prompt_success() -> void:
	var hs := 2
	var t0: int = _ns(hs, 10)
	var t1: int = _ns(hs, 11)
	var wire := _event_wire("TURN_PROMPT", 15, {
		"hand_seq": hs,
		"decision_id": DECISION,
		"seat": 1,
		"hand": [
			_canonical_tile_view_for_iid(t0),
			_canonical_tile_view_for_iid(t1),
		],
		"last_drawn_tile_instance_id": t1,
		"allowed_actions": [
			{"kind": "DISCARD", "payload_options": [{"tile_instance_id": t0}, {"tile_instance_id": t1}]},
			{"kind": "TSUMO", "payload_options": [{}]},
		],
	})
	var decoded: NetworkedEvent = JsonTransportDecoder.decode_event(_event_json_from_wire(wire))
	assert_not_null(decoded, "TURN_PROMPT JSON 应成功解码")
	if decoded == null:
		return
	assert_eq(decoded.kind, "TURN_PROMPT")
	assert_eq(decoded.server_seq, 15)
	var p: Dictionary = decoded.payload
	_assert_int_field(p, "seat", 1)
	_assert_int_field(p, "hand_seq", 2)
	_assert_int_field(p, "last_drawn_tile_instance_id", t1)
	assert_eq((p.get("hand") as Array).size(), 2)
	assert_eq((p.get("allowed_actions") as Array).size(), 2)
	assert_true(decoded.to_dict().has("view_hash"))
	assert_eq(str(decoded.to_dict().get("view_hash")).length(), 64)


func test_decode_event_claim_window_success() -> void:
	var hs := 3
	var discarded: Dictionary = _canonical_tile_view(TileId.W5, 0, hs)
	var discarded_id: int = int(discarded["instance_id"])
	var pon_a: int = int(_canonical_tile_view(TileId.W5, 1, hs)["instance_id"])
	var pon_b: int = int(_canonical_tile_view(TileId.W5, 2, hs)["instance_id"])
	var wire := _event_wire("CLAIM_WINDOW", 16, {
		"hand_seq": hs,
		"decision_id": DECISION,
		"discarded_by_seat": 0,
		"discarded_tile": discarded,
		"allowed_actions": [
			{"kind": "PASS", "payload_options": [{}]},
			{"kind": "PON", "payload_options": [{"companion_tile_instance_ids": [pon_a, pon_b]}]},
			{"kind": "RON", "payload_options": [{}]},
		],
	})
	var decoded: NetworkedEvent = JsonTransportDecoder.decode_event(_event_json_from_wire(wire))
	assert_not_null(decoded, "CLAIM_WINDOW JSON 应成功解码")
	if decoded == null:
		return
	assert_eq(decoded.kind, "CLAIM_WINDOW")
	var p: Dictionary = decoded.payload
	_assert_int_field(p, "discarded_by_seat", 0)
	_assert_int_field(p, "hand_seq", 3)
	assert_true(p.get("discarded_tile") is Dictionary)
	_assert_int_field(p["discarded_tile"] as Dictionary, "instance_id", discarded_id)
	var offers: Array = p.get("allowed_actions", [])
	assert_eq(offers.size(), 3)
	assert_eq(str((offers[0] as Dictionary).get("kind")), "PASS")
	assert_false(p.has("offers_by_seat"))
	assert_false(p.has("allowed_actions_by_seat"))
	assert_false(p.has("eligible_seats"))


# --- Event 拒绝路径 ---

func test_decode_event_missing_view_hash_rejected() -> void:
	var raw := (
		'{"protocol_version":1,"server_seq":1,"room_id":"%s",'
		+ '"kind":"ROOM_SNAPSHOT","payload":{}}'
	) % ROOM
	assert_null(JsonTransportDecoder.decode_event(raw), "缺 view_hash 应拒绝")


func test_decode_event_state_hash_rejected() -> void:
	var raw := (
		'{"protocol_version":1,"server_seq":1,"room_id":"%s",'
		+ '"kind":"ROOM_SNAPSHOT","payload":{},'
		+ '"view_hash":"%s","state_hash":"%s"}'
	) % [ROOM, VIEW_HASH, VIEW_HASH]
	assert_null(JsonTransportDecoder.decode_event(raw), "state_hash 多余键应拒绝")


func test_decode_event_server_seq_float_rejected() -> void:
	var raw := (
		'{"protocol_version":1,"server_seq":1.5,"room_id":"%s",'
		+ '"kind":"ROOM_SNAPSHOT","payload":{},"view_hash":"%s"}'
	) % [ROOM, VIEW_HASH]
	assert_null(JsonTransportDecoder.decode_event(raw), "server_seq=1.5 应拒绝")


func test_decode_event_server_seq_beyond_safe_integer_rejected() -> void:
	var raw := (
		'{"protocol_version":1,"server_seq":9007199254740992,"room_id":"%s",'
		+ '"kind":"ROOM_SNAPSHOT","payload":{},"view_hash":"%s"}'
	) % [ROOM, VIEW_HASH]
	assert_null(JsonTransportDecoder.decode_event(raw), "server_seq 超安全整数应拒绝")


func test_decode_event_payload_hand_seq_fractional_rejected() -> void:
	var raw := (
		'{"protocol_version":1,"server_seq":10,"room_id":"%s",'
		+ '"kind":"REWARD_WINDOW_OPENED","payload":{'
		+ '"window_id":"%s","hand_seq":1.5,"window_index":1,'
		+ '"prize_pool":["a","b","c","d"],"rule_version":"rv",'
		+ '"phase":"OPEN","window_exit":null},"view_hash":"%s"}'
	) % [ROOM, WINDOW_ID, VIEW_HASH]
	assert_null(JsonTransportDecoder.decode_event(raw), "hand_seq=1.5 应拒绝")


func test_decode_event_action_applied_entity_float_rejected() -> void:
	var hs := 1
	var iid: int = _ns(hs, 9)
	var base_wire := _event_wire("ACTION_APPLIED", 1, {
		"causation_command_id": CMD,
		"hand_seq": hs,
		"decision_id": DECISION,
		"seat": 0,
		"action_kind": "DISCARD",
		"resolved_payload": {
			"tile": _canonical_tile_view_for_iid(iid),
			"discard_source": "HAND",
		},
	})
	assert_not_null(
		JsonTransportDecoder.decode_event(_event_json_from_wire(base_wire)),
		"paired baseline: integer canonical DISCARD TileView 可 decode"
	)
	var float_wire: Dictionary = base_wire.duplicate(true)
	(((float_wire["payload"] as Dictionary)["resolved_payload"] as Dictionary)["tile"] as Dictionary)["instance_id"] = (
		float(iid) + 0.5
	)
	assert_null(
		JsonTransportDecoder.decode_event(_event_json_from_wire(float_wire)),
		"TileView.instance_id float 应拒绝"
	)


func test_decode_event_turn_prompt_entity_float_rejected() -> void:
	var hs := 1
	var iid: int = _ns(hs, 10)
	# TSUMO-only：避免 DISCARD 引用与 float hand iid 脱节
	var base_wire := _event_wire("TURN_PROMPT", 15, {
		"hand_seq": hs,
		"decision_id": DECISION,
		"seat": 0,
		"hand": [_canonical_tile_view_for_iid(iid)],
		"last_drawn_tile_instance_id": -1,
		"allowed_actions": [{"kind": "TSUMO", "payload_options": [{}]}],
	})
	assert_not_null(
		JsonTransportDecoder.decode_event(_event_json_from_wire(base_wire)),
		"paired baseline: integer canonical TURN_PROMPT 可 decode"
	)
	var float_wire: Dictionary = base_wire.duplicate(true)
	(((float_wire["payload"] as Dictionary)["hand"] as Array)[0] as Dictionary)["instance_id"] = (
		float(iid) + 0.5
	)
	assert_null(
		JsonTransportDecoder.decode_event(_event_json_from_wire(float_wire)),
		"TURN_PROMPT hand TileView.instance_id float 应拒绝"
	)


func test_decode_event_claim_window_cross_seat_fields_rejected() -> void:
	var hs := 1
	var base_payload := {
		"hand_seq": hs,
		"decision_id": DECISION,
		"discarded_by_seat": 0,
		"discarded_tile": _canonical_tile_view(TileId.W5, 0, hs),
		"allowed_actions": [{"kind": "PASS", "payload_options": [{}]}],
	}
	var base_wire := _event_wire("CLAIM_WINDOW", 16, base_payload)
	assert_not_null(
		JsonTransportDecoder.decode_event(_event_json_from_wire(base_wire)),
		"paired baseline: canonical PASS-only CLAIM_WINDOW 可 decode"
	)
	var cross_wire: Dictionary = base_wire.duplicate(true)
	(cross_wire["payload"] as Dictionary)["offers_by_seat"] = {
		"1": [{"kind": "PASS", "payload_options": [{}]}],
	}
	(cross_wire["payload"] as Dictionary)["allowed_actions_by_seat"] = {
		"2": [{"kind": "PASS", "payload_options": [{}]}],
	}
	assert_null(
		JsonTransportDecoder.decode_event(_event_json_from_wire(cross_wire)),
		"CLAIM_WINDOW 跨席 offers_by_seat / allowed_actions_by_seat 应拒绝"
	)

	var eligible_wire: Dictionary = base_wire.duplicate(true)
	(eligible_wire["payload"] as Dictionary)["eligible_seats"] = [1, 2, 3]
	assert_null(
		JsonTransportDecoder.decode_event(_event_json_from_wire(eligible_wire)),
		"CLAIM_WINDOW eligible_seats 跨席容器应拒绝"
	)


func test_decode_event_action_applied_missing_discard_source_rejected() -> void:
	var hs := 1
	var iid: int = _ns(hs, 1)
	var base_wire := _event_wire("ACTION_APPLIED", 1, {
		"causation_command_id": CMD,
		"hand_seq": hs,
		"decision_id": DECISION,
		"seat": 0,
		"action_kind": "DISCARD",
		"resolved_payload": {
			"tile": _canonical_tile_view_for_iid(iid),
			"discard_source": "HAND",
		},
	})
	assert_not_null(
		JsonTransportDecoder.decode_event(_event_json_from_wire(base_wire)),
		"paired baseline: 完整 DISCARD resolved 可 decode"
	)
	var wire: Dictionary = base_wire.duplicate(true)
	((wire["payload"] as Dictionary)["resolved_payload"] as Dictionary).erase("discard_source")
	assert_null(
		JsonTransportDecoder.decode_event(_event_json_from_wire(wire)),
		"DISCARD 缺 discard_source 拒绝"
	)


func test_decode_event_action_applied_unknown_action_kind_rejected() -> void:
	# PASS 合法；ITEM_USE / DRAW 等拒绝
	var pass_raw := (
		'{"protocol_version":1,"server_seq":1,"room_id":"%s",'
		+ '"kind":"ACTION_APPLIED","payload":{'
		+ '"causation_command_id":"%s","hand_seq":1,"decision_id":"%s",'
		+ '"seat":0,"action_kind":"PASS",'
		+ '"resolved_payload":{}},"view_hash":"%s"}'
	) % [ROOM, CMD, DECISION, VIEW_HASH]
	assert_not_null(
		JsonTransportDecoder.decode_event(pass_raw),
		"ACTION_APPLIED.action_kind=PASS 合法"
	)
	for bad_kind in ["ITEM_USE", "JOIN", "READY", "RESYNC_REQUEST", "DRAW", "PASS_CLAIM"]:
		var raw := (
			'{"protocol_version":1,"server_seq":1,"room_id":"%s",'
			+ '"kind":"ACTION_APPLIED","payload":{'
			+ '"causation_command_id":"%s","hand_seq":1,"decision_id":"%s",'
			+ '"seat":0,"action_kind":"%s",'
			+ '"resolved_payload":{}},"view_hash":"%s"}'
		) % [ROOM, CMD, DECISION, bad_kind, VIEW_HASH]
		assert_null(
			JsonTransportDecoder.decode_event(raw),
			"ACTION_APPLIED.action_kind=%s 拒绝" % bad_kind
		)


# ---- #232 decode 路径：跨局命名空间反例（生产缺口 Red）----

func test_decode_event_rejects_out_of_hand_seq_namespace_entities() -> void:
	# iid 按自身 canonical；仅 hand_seq=2 时 9/10 落在 [0,135] 外
	var oor_disc_iid := 9
	var base_disc := _event_wire("ACTION_APPLIED", 100, {
		"causation_command_id": CMD,
		"hand_seq": 0,
		"decision_id": DECISION,
		"seat": 1,
		"action_kind": "DISCARD",
		"resolved_payload": {
			"tile": _canonical_tile_view_for_iid(oor_disc_iid),
			"discard_source": "HAND",
		},
	})
	assert_not_null(
		JsonTransportDecoder.decode_event(_event_json_from_wire(base_disc)),
		"paired baseline: iid=9 + hand_seq=0 命名空间合法可 decode"
	)
	var wire := _event_wire("ACTION_APPLIED", 100, {
		"causation_command_id": CMD,
		"hand_seq": 2,
		"decision_id": DECISION,
		"seat": 1,
		"action_kind": "DISCARD",
		"resolved_payload": {
			"tile": _canonical_tile_view_for_iid(oor_disc_iid),
			"discard_source": "HAND",
		},
	})
	assert_null(
		JsonTransportDecoder.decode_event(_event_json_from_wire(wire)),
		"decode_event 必须拒绝跨局命名空间外的 ACTION_APPLIED 实体"
	)
	var oor_turn_iid := 10
	var base_turn := _event_wire("TURN_PROMPT", 15, {
		"hand_seq": 0,
		"decision_id": DECISION,
		"seat": 1,
		"hand": [_canonical_tile_view_for_iid(oor_turn_iid)],
		"last_drawn_tile_instance_id": -1,
		"allowed_actions": [
			{"kind": "DISCARD", "payload_options": [{"tile_instance_id": oor_turn_iid}]},
		],
	})
	assert_not_null(
		JsonTransportDecoder.decode_event(_event_json_from_wire(base_turn)),
		"paired baseline: iid=10 + hand_seq=0 命名空间合法可 decode"
	)
	var turn := _event_wire("TURN_PROMPT", 15, {
		"hand_seq": 2,
		"decision_id": DECISION,
		"seat": 1,
		"hand": [_canonical_tile_view_for_iid(oor_turn_iid)],
		"last_drawn_tile_instance_id": -1,
		"allowed_actions": [
			{"kind": "DISCARD", "payload_options": [{"tile_instance_id": oor_turn_iid}]},
		],
	})
	assert_null(
		JsonTransportDecoder.decode_event(_event_json_from_wire(turn)),
		"decode_event 必须拒绝跨局命名空间外的 TURN_PROMPT hand 实体"
	)
