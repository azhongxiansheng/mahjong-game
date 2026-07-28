extends GutTest

# E2-02（#232）Red：E5 仅 fixture — 冻结 REWARD_WINDOW_* / ITEM_* /
# CHARACTER_ABILITY_* 必填 schema、固定枚举、FULL_GRANT 四席 grant、
# DISPLAY_ONLY 零 grant、CANCELLED 无 outcome/矩阵，以及 ADR 合法/非法偏序。
# envelope 强制 view_hash；ACTION_APPLIED 用 resolved 实体 payload。
# 只消费静态 fixture，不得要求生产 BattleController 发射 E5 事件。

const ROOM := "room_x"
const WINDOW_ID := "hand_3_window_1"
const PRIZE_POOL := ["item_a", "item_b", "item_c", "item_d"]
const CMD := "550e8400-e29b-41d4-a716-446655440000"
const DECISION := "550e8400-e29b-41d4-a716-4466554400aa"
const VIEW_HASH := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
const ORDER_SCRIPT := "res://protocol/e5_event_order.gd"
const NE_SCRIPT := "res://protocol/networked_event.gd"
const MAX_SAFE_INT := 9007199254740991
const MAX_HAND_SEQ := 66229406284859
const TILES_PER_HAND := 136
const FIXTURE_HAND_SEQ := 3


func _ns(serial: int, hand_seq: int = FIXTURE_HAND_SEQ) -> int:
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
	hand_seq: int = FIXTURE_HAND_SEQ
) -> Dictionary:
	var idx: int = TileId.ALL.find(tile_id)
	var iid: int = idx * 4 + copy_index + hand_seq * TILES_PER_HAND
	return _canonical_tile_view_for_iid(iid)


## DISCARD seat0 / CLAIM discarded / RON winning 同源 entity
func _fixture_discarded_tile() -> Dictionary:
	return _canonical_tile_view(TileId.W5, 0, FIXTURE_HAND_SEQ)


## called_serial 仅用于选合法 tile type（serial/4 → ALL）；不伪造 tid/red/owner
func _meld_view(kind: String = "PON", from_seat: int = 0, called_serial: int = 50) -> Dictionary:
	var tiles: Array = []
	var added: int = -1
	var fs: int = from_seat
	var called_id: int = -1
	@warning_ignore("integer_division")
	var type_index: int = (called_serial % TILES_PER_HAND) / 4
	if type_index < 0 or type_index >= TileId.ALL.size():
		type_index = 0
	var type_tid: int = TileId.ALL[type_index]

	if kind == "ANKAN":
		fs = -1
		called_id = -1
		for o in range(4):
			tiles.append(_canonical_tile_view(type_tid, o))
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
		var t_a := _canonical_tile_view(a_tid, 0)
		var t_b := _canonical_tile_view(b_tid, 0)
		var t_called := _canonical_tile_view(called_tid, fs)
		called_id = int(t_called["instance_id"])
		tiles = [t_a, t_b, t_called]
	elif kind == "MINKAN" or kind == "ADDED_KAN":
		var t_called := _canonical_tile_view(type_tid, fs)
		called_id = int(t_called["instance_id"])
		if kind == "ADDED_KAN":
			var added_owner: int = 3 if fs != 3 else 1
			var t_added := _canonical_tile_view(type_tid, added_owner)
			added = int(t_added["instance_id"])
			for o in range(4):
				if o == fs or o == added_owner:
					continue
				tiles.append(_canonical_tile_view(type_tid, o))
			tiles.append(t_called)
			tiles.append(t_added)
		else:
			for o in range(4):
				if o == fs:
					continue
				tiles.append(_canonical_tile_view(type_tid, o))
			tiles.append(t_called)
	else:
		# PON：同 tile 三 copies；called=from 成员
		var t_called := _canonical_tile_view(type_tid, fs)
		called_id = int(t_called["instance_id"])
		var picked := 0
		for o in range(4):
			if o == fs:
				continue
			tiles.append(_canonical_tile_view(type_tid, o))
			picked += 1
			if picked == 2:
				break
		tiles.append(t_called)
	return {
		"meld_id": 0,
		"kind": kind,
		"from_seat": fs,
		"called_tile_instance_id": called_id,
		"added_tile_instance_id": added,
		"tiles": tiles,
	}


func _resolved_for(action_kind: String, seat: int = 0) -> Dictionary:
	match action_kind:
		"DISCARD", "RIICHI":
			# seat0 与 CLAIM discarded / RON winning 同源；其它 seat 用同牌其它 copy
			var discard_tile: Dictionary = (
				_fixture_discarded_tile()
				if seat == 0
				else _canonical_tile_view(TileId.W5, seat % 4, FIXTURE_HAND_SEQ)
			)
			return {
				"tile": discard_tile,
				"discard_source": "DRAWN",
			}
		"CHI":
			return {"meld": _meld_view("CHI", (seat + 1) % 4, 50)}
		"PON":
			return {"meld": _meld_view("PON", (seat + 1) % 4, 51)}
		"KAN":
			return {"meld": _meld_view("MINKAN", (seat + 1) % 4, 52)}
		"RON":
			var from_seat: int = (seat + 1) % 4
			return {
				"winning_tile": _fixture_discarded_tile(),
				"from_seat": from_seat,
			}
		"TSUMO":
			return {
				"winning_tile": _canonical_tile_view(TileId.W5, seat % 4, FIXTURE_HAND_SEQ),
			}
		"PASS":
			return {}
		"DECLARE_ABORTIVE_DRAW":
			return {"reason": "KYUUSYU_KYUUHAI"}
		_:
			return {}


func _env(kind: String, seq: int, payload: Dictionary) -> Dictionary:
	return {
		"protocol_version": 1,
		"server_seq": seq,
		"room_id": ROOM,
		"kind": kind,
		"payload": payload.duplicate(true),
		"view_hash": VIEW_HASH,
	}


func _action_applied(seq: int, action_kind: String, seat: int = 0, resolved: Dictionary = {}) -> Dictionary:
	var rp: Dictionary = resolved
	if rp.is_empty():
		rp = _resolved_for(action_kind, seat)
	return _env("ACTION_APPLIED", seq, {
		"causation_command_id": CMD,
		"hand_seq": 3,
		"decision_id": DECISION,
		"seat": seat,
		"action_kind": action_kind,
		"resolved_payload": rp.duplicate(true),
	})


func _opened(seq: int = 10) -> Dictionary:
	return _env("REWARD_WINDOW_OPENED", seq, {
		"window_id": WINDOW_ID,
		"hand_seq": 3,
		"window_index": 1,
		"prize_pool": PRIZE_POOL.duplicate(),
		"rule_version": "reward_v2",
		"phase": "OPEN",
		"window_exit": null,
	})


func _closing(seq: int = 110) -> Dictionary:
	return _env("REWARD_WINDOW_CLOSING", seq, {
		"window_id": WINDOW_ID,
		"hand_seq": 3,
		"closing_boundary_server_seq": 110,
		"grace_deadline_at": "2026-07-22T12:00:01.500Z",
		"phase": "CLOSING",
		"window_exit": null,
	})


func _settled_full(seq: int = 120) -> Dictionary:
	return _env("REWARD_WINDOW_SETTLED", seq, {
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


func _settled_display(seq: int = 120) -> Dictionary:
	var base: Dictionary = _settled_full(seq)
	var p: Dictionary = (base["payload"] as Dictionary).duplicate(true)
	p["outcome"] = "DISPLAY_ONLY"
	p["settle_reason"] = "MATCH_END_NO_WIN"
	p["grant_count"] = 0
	return _env("REWARD_WINDOW_SETTLED", seq, p)


func _cancelled(seq: int = 121, closing_boundary = 110) -> Dictionary:
	return _env("REWARD_WINDOW_CANCELLED", seq, {
		"window_id": WINDOW_ID,
		"cancel_reason": "CANCELLED_BY_WIN",
		"closing_boundary_server_seq": closing_boundary,
		"grace_aborted": true,
		"scored": false,
		"grant_count": 0,
		"hand_seq": 3,
	})


func _item_granted(seat: int, seq: int, armed_for_window_id = "hand_3_window_2") -> Dictionary:
	return _env("ITEM_GRANTED", seq, {
		"window_id": WINDOW_ID,
		"rule_version": "reward_v2",
		"assignment_version": "assign_v1",
		"matched_rule_ids": ["stable_rule_id"],
		"item_id": PRIZE_POOL[seat],
		"item_instance_id": "inst_seat_%d" % seat,
		"seat": seat,
		"hand_seq": 3,
		"score": 1000,
		"affinity_match": seat == 0,
		"armed_for_window_id": armed_for_window_id,
	})


func _item_consumed(seq: int = 130) -> Dictionary:
	return _env("ITEM_CONSUMED", seq, {
		"seat": 0,
		"item_id": "item_a",
		"item_instance_id": "inst_abc",
		"command_id": "550e8400-e29b-41d4-a716-446655440001",
	})


func _item_applied(seq: int = 131) -> Dictionary:
	return _env("ITEM_APPLIED", seq, {
		"seat": 0,
		"item_id": "item_a",
		"item_instance_id": "inst_abc",
		"effect_id": "stable_effect_id",
		"command_id": "550e8400-e29b-41d4-a716-446655440001",
	})


func _armed(seq: int = 11) -> Dictionary:
	return _env("CHARACTER_ABILITY_ARMED", seq, {
		"seat": 0,
		"window_id": WINDOW_ID,
		"character_id": "lin_yeche",
		"ability_id": "char_passive_v1",
		"active_window_id": WINDOW_ID,
	})


func _disarmed(seq: int = 125) -> Dictionary:
	return _env("CHARACTER_ABILITY_DISARMED", seq, {
		"seat": 0,
		"window_id": WINDOW_ID,
		"character_id": "lin_yeche",
		"ability_id": "char_passive_v1",
		"active_window_id": null,
	})


func _claim_window(seq: int = 111) -> Dictionary:
	# #232 strict CLAIM_WINDOW：每 recipient 仅自己的 allowed_actions，至少 PASS。
	# 不改 E5 偏序 kind 序列，只冻结合法私有 payload。
	# discarded_tile 与 DISCARD seat0 / RON winning 同源 canonical entity。
	return _env("CLAIM_WINDOW", seq, {
		"hand_seq": 3,
		"decision_id": DECISION,
		"discarded_by_seat": 0,
		"discarded_tile": _fixture_discarded_tile(),
		"allowed_actions": [
			{"kind": "PASS", "payload_options": [{}]},
		],
	})


func _hand_settled(seq: int = 52, outcome: String = "RON") -> Dictionary:
	var winner_seats: Array = [2]
	var loser_seat := 0
	var score_deltas: Array = [-1000, 0, 1000, 0]
	var renchan := false
	if outcome in ["EXHAUSTIVE_DRAW", "ABORTIVE_DRAW"]:
		winner_seats = []
		loser_seat = -1
		score_deltas = [0, 0, 0, 0]
	if outcome == "ABORTIVE_DRAW":
		renchan = true
	return _env("HAND_SETTLED", seq, {
		"hand_seq": 3,
		"outcome": outcome,
		"winner_seats": winner_seats,
		"loser_seat": loser_seat,
		"score_deltas": score_deltas,
		"scores": [24000, 25000, 26000, 25000],
		"dealer_seat": 0,
		"renchan": renchan,
		"honba": 1 if renchan else 0,
		"riichi_sticks": 0,
		"adjustments": [],
	})


func _match_settled(seq: int) -> Dictionary:
	return _env("MATCH_SETTLED", seq, {
		"round_kind": "EAST",
		"final_scores": [24000, 25000, 26000, 25000],
		"seat_order": [2, 1, 3, 0],
	})


func _payload_of(ev: NetworkedEvent) -> Dictionary:
	var d: Dictionary = ev.to_dict()
	assert_true(d.has("payload"), "ServerEvent wire 必须有 payload")
	assert_true(d.has("view_hash"), "ServerEvent wire 必须有 view_hash")
	assert_false(d.has("state_hash"), "不得出现 state_hash")
	var raw: Variant = d.get("payload", null)
	assert_eq(typeof(raw), TYPE_DICTIONARY, "payload 必须是 Dictionary")
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw as Dictionary


func _parse_all(fixtures: Array) -> Array:
	var out: Array = []
	for f in fixtures:
		var ev: NetworkedEvent = NetworkedEvent.from_dict(f)
		assert_not_null(ev, "fixture 必须可被业务事件解析: %s" % str(f.get("kind")))
		if ev != null:
			out.append(ev)
	return out


func _script_has_method(path: String, method_name: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var script: GDScript = load(path) as GDScript
	if script == null:
		return false
	for m in script.get_script_method_list():
		if str(m.get("name", "")) == method_name:
			return true
	return false


func _assert_order_legal(kinds: Array, label: String) -> void:
	if ResourceLoader.exists(ORDER_SCRIPT) and _script_has_method(ORDER_SCRIPT, "is_legal_sequence"):
		var script: GDScript = load(ORDER_SCRIPT) as GDScript
		assert_true(bool(script.call("is_legal_sequence", kinds)), "%s 应合法" % label)
		return
	if _script_has_method(NE_SCRIPT, "is_legal_e5_sequence"):
		var ne_script: GDScript = load(NE_SCRIPT) as GDScript
		assert_true(bool(ne_script.call("is_legal_e5_sequence", kinds)), "%s 应合法" % label)
		return
	assert_true(
		false,
		"需要 E5 偏序校验 API：%s 或 NetworkedEvent.is_legal_e5_sequence（%s）" % [
			ORDER_SCRIPT, label,
		]
	)


func _assert_order_illegal(kinds: Array, label: String) -> void:
	if ResourceLoader.exists(ORDER_SCRIPT) and _script_has_method(ORDER_SCRIPT, "is_legal_sequence"):
		var script: GDScript = load(ORDER_SCRIPT) as GDScript
		assert_false(bool(script.call("is_legal_sequence", kinds)), "%s 应非法" % label)
		return
	if _script_has_method(NE_SCRIPT, "is_legal_e5_sequence"):
		var ne_script: GDScript = load(NE_SCRIPT) as GDScript
		assert_false(bool(ne_script.call("is_legal_e5_sequence", kinds)), "%s 应非法" % label)
		return
	assert_true(false, "需要 E5 偏序校验 API（%s）" % label)


func _assert_order_illegal_with_meta(kinds: Array, meta: Dictionary, label: String) -> void:
	if ResourceLoader.exists(ORDER_SCRIPT) and _script_has_method(ORDER_SCRIPT, "is_legal_sequence"):
		var script: GDScript = load(ORDER_SCRIPT) as GDScript
		assert_false(bool(script.call("is_legal_sequence", kinds, meta)), label)
		return
	if _script_has_method(NE_SCRIPT, "is_legal_e5_sequence"):
		var ne_script: GDScript = load(NE_SCRIPT) as GDScript
		assert_false(bool(ne_script.call("is_legal_e5_sequence", kinds, meta)), label)
		return
	assert_true(false, "需要 E5 偏序校验 API（%s）" % label)


func _assert_order_legal_with_meta(kinds: Array, meta: Dictionary, label: String) -> void:
	if ResourceLoader.exists(ORDER_SCRIPT) and _script_has_method(ORDER_SCRIPT, "is_legal_sequence"):
		var script: GDScript = load(ORDER_SCRIPT) as GDScript
		assert_true(bool(script.call("is_legal_sequence", kinds, meta)), "%s 应合法" % label)
		return
	if _script_has_method(NE_SCRIPT, "is_legal_e5_sequence"):
		var ne_script: GDScript = load(NE_SCRIPT) as GDScript
		assert_true(bool(ne_script.call("is_legal_e5_sequence", kinds, meta)), "%s 应合法" % label)
		return
	assert_true(false, "需要 E5 偏序校验 API（%s）" % label)


func _required_fields_for(kind: String) -> Array:
	match kind:
		"REWARD_WINDOW_OPENED":
			return [
				"window_id", "hand_seq", "window_index", "prize_pool",
				"rule_version", "phase", "window_exit",
			]
		"REWARD_WINDOW_CLOSING":
			return [
				"window_id", "hand_seq", "closing_boundary_server_seq",
				"grace_deadline_at", "phase", "window_exit",
			]
		"REWARD_WINDOW_SETTLED":
			return [
				"window_id", "outcome", "settle_reason", "rule_version",
				"assignment_version", "prize_pool", "matrix_summary", "assignment",
				"closing_boundary_server_seq", "context_boundary_server_seq",
				"grace_deadline_at", "grant_count", "hand_seq", "transcript_summary",
			]
		"REWARD_WINDOW_CANCELLED":
			return [
				"window_id", "cancel_reason", "closing_boundary_server_seq",
				"grace_aborted", "scored", "grant_count", "hand_seq",
			]
		"ITEM_GRANTED":
			return [
				"window_id", "rule_version", "assignment_version", "matched_rule_ids",
				"item_id", "item_instance_id", "seat", "hand_seq", "score",
				"affinity_match", "armed_for_window_id",
			]
		"ITEM_CONSUMED":
			return ["seat", "item_id", "item_instance_id", "command_id"]
		"ITEM_APPLIED":
			return ["seat", "item_id", "item_instance_id", "effect_id", "command_id"]
		"CHARACTER_ABILITY_ARMED":
			return ["seat", "window_id", "character_id", "ability_id", "active_window_id"]
		"CHARACTER_ABILITY_DISARMED":
			return ["seat", "window_id", "character_id", "ability_id", "active_window_id"]
		_:
			return []


func _fixture_for_kind(kind: String) -> Dictionary:
	match kind:
		"REWARD_WINDOW_OPENED":
			return _opened()
		"REWARD_WINDOW_CLOSING":
			return _closing()
		"REWARD_WINDOW_SETTLED":
			return _settled_full()
		"REWARD_WINDOW_CANCELLED":
			return _cancelled()
		"ITEM_GRANTED":
			return _item_granted(0, 122)
		"ITEM_CONSUMED":
			return _item_consumed()
		"ITEM_APPLIED":
			return _item_applied()
		"CHARACTER_ABILITY_ARMED":
			return _armed()
		"CHARACTER_ABILITY_DISARMED":
			return _disarmed()
		_:
			return {}


# ---- 必填 schema / 固定枚举 ----

func test_action_applied_fixture_required_resolved_fields() -> void:
	var f := _action_applied(109, "DISCARD", 0)
	var ev: NetworkedEvent = NetworkedEvent.from_dict(f)
	assert_not_null(ev)
	if ev == null:
		return
	var p: Dictionary = _payload_of(ev)
	for k in [
		"causation_command_id", "hand_seq", "decision_id",
		"seat", "action_kind", "resolved_payload",
	]:
		assert_true(p.has(k), "ACTION_APPLIED 必含 %s" % k)
	assert_eq(str(p.get("action_kind")), "DISCARD")
	assert_eq(typeof(p.get("resolved_payload")), TYPE_DICTIONARY)
	var rp: Dictionary = p.get("resolved_payload") as Dictionary
	assert_true(rp.has("tile"))
	assert_true(rp.has("discard_source"), "DISCARD resolved 必须 discard_source")
	assert_true(str(rp.get("discard_source")) in ["DRAWN", "HAND"])
	assert_false(rp.has("winner_seat"))
	assert_false(p.has("normalized_payload"), "不得使用旧 normalized_payload")
	assert_false(p.has("command_id"), "causation 使用 causation_command_id")


func test_reward_window_opened_required_schema() -> void:
	var f := _opened()
	var ev: NetworkedEvent = NetworkedEvent.from_dict(f)
	assert_not_null(ev)
	if ev == null:
		return
	var p: Dictionary = _payload_of(ev)
	assert_eq(str(p.get("window_id", "")), WINDOW_ID)
	assert_eq(p.get("prize_pool", []).size(), 4)
	assert_eq(p.get("window_exit"), null)
	assert_eq(str(p.get("phase", "")), "OPEN")
	var dup := _opened()
	dup["payload"]["prize_pool"] = ["item_a", "item_a", "item_c", "item_d"]
	assert_null(NetworkedEvent.from_dict(dup), "奖池重复 item_id 失败")


func test_reward_window_closing_required_schema() -> void:
	var ev: NetworkedEvent = NetworkedEvent.from_dict(_closing())
	assert_not_null(ev)
	if ev == null:
		return
	var p: Dictionary = _payload_of(ev)
	assert_eq(int(p.get("closing_boundary_server_seq", -1)), 110)
	assert_true(str(p.get("grace_deadline_at", "")).length() > 0)
	assert_eq(p.get("window_exit"), null)


func test_settled_outcome_enum_and_full_grant_count() -> void:
	var full: NetworkedEvent = NetworkedEvent.from_dict(_settled_full())
	assert_not_null(full)
	if full != null:
		var p: Dictionary = _payload_of(full)
		assert_eq(str(p.get("outcome", "")), "FULL_GRANT")
		assert_eq(int(p.get("grant_count", -1)), 4)
		assert_true(p.has("matrix_summary"))
		assert_true(p.has("assignment"))

	var bad := _settled_full()
	bad["payload"]["outcome"] = "CANCELLED_BY_WIN"
	assert_null(NetworkedEvent.from_dict(bad), "SETTLED.outcome 仅 FULL_GRANT|DISPLAY_ONLY")


func test_settled_opaque_summaries_are_json_safe_and_deep_copied() -> void:
	var source := _settled_full()
	var source_payload: Dictionary = source["payload"]
	source_payload["matrix_summary"] = {
		"scores": [[1000, 0], [0, 1000]],
		"meta": {"ready": true, "note": "ok", "optional": null},
	}
	source_payload["assignment"] = {
		"seat_0": {"items": ["item_a", "item_b"], "count": 2},
	}
	source_payload["transcript_summary"] = {
		"segments": [{"text": "来战", "final": true}],
	}

	var ev: NetworkedEvent = NetworkedEvent.from_dict(source)
	assert_not_null(ev, "合法嵌套 JSON-safe opaque 字典应通过")
	if ev == null:
		return

	(source_payload["matrix_summary"] as Dictionary)["late_mutation"] = true
	((source_payload["assignment"] as Dictionary)["seat_0"] as Dictionary)["count"] = 99
	var first: Dictionary = _payload_of(ev)
	assert_false((first["matrix_summary"] as Dictionary).has("late_mutation"), "输入改写不得污染事件")
	assert_eq(
		int(((first["assignment"] as Dictionary)["seat_0"] as Dictionary)["count"]),
		2,
		"嵌套输入必须 deep copy"
	)

	(first["transcript_summary"] as Dictionary)["late_mutation"] = true
	var second: Dictionary = _payload_of(ev)
	assert_false(
		(second["transcript_summary"] as Dictionary).has("late_mutation"),
		"payload getter 必须 deep copy"
	)


func test_settled_opaque_summaries_reject_non_json_safe_nested_values() -> void:
	for field_name in ["matrix_summary", "assignment", "transcript_summary"]:
		for invalid_value in [
			1.0,
			MAX_SAFE_INT + 1,
			RefCounted.new(),
			{1: "non_string_key"},
		]:
			var bad := _settled_full()
			bad["payload"][field_name] = {"outer": [invalid_value]}
			assert_null(
				NetworkedEvent.from_dict(bad),
				"%s 嵌套 %s 必须拒绝" % [field_name, type_string(typeof(invalid_value))]
			)


func test_e5_identity_strings_must_be_nonempty_and_canonical() -> void:
	var identity_cases: Array = [
		[_opened(), "window_id"],
		[_opened(), "rule_version"],
		[_settled_full(), "assignment_version"],
		[_item_granted(0, 122), "item_id"],
		[_item_granted(0, 122), "item_instance_id"],
		[_item_consumed(), "item_id"],
		[_item_consumed(), "item_instance_id"],
		[_item_applied(), "effect_id"],
		[_armed(), "character_id"],
		[_armed(), "ability_id"],
		[_armed(), "active_window_id"],
	]
	for identity_case in identity_cases:
		var base: Dictionary = identity_case[0]
		var key_name: String = identity_case[1]
		for bad_value in ["", "   ", " leading", "trailing "]:
			var bad: Dictionary = base.duplicate(true)
			bad["payload"][key_name] = bad_value
			assert_null(
				NetworkedEvent.from_dict(bad),
				"%s 必须非空且等于 strip_edges(): %s" % [key_name, JSON.stringify(bad_value)]
			)

	var bad_pool := _opened()
	bad_pool["payload"]["prize_pool"][0] = " item_a"
	assert_null(NetworkedEvent.from_dict(bad_pool), "prize_pool item_id 前导空白拒绝")

	var bad_rule := _item_granted(0, 122)
	bad_rule["payload"]["matched_rule_ids"] = ["stable_rule_id "]
	assert_null(NetworkedEvent.from_dict(bad_rule), "matched_rule_ids 元素尾随空白拒绝")

	var blank_rule := _item_granted(0, 122)
	blank_rule["payload"]["matched_rule_ids"] = ["   "]
	assert_null(NetworkedEvent.from_dict(blank_rule), "matched_rule_ids 元素纯空白拒绝")

	var bad_armed := _item_granted(0, 122, " hand_3_window_2")
	assert_null(NetworkedEvent.from_dict(bad_armed), "armed_for_window_id 前导空白拒绝")


func test_e5_numeric_boundaries_are_strict_and_json_safe() -> void:
	var opened_zero := _opened()
	opened_zero["payload"]["hand_seq"] = 0
	assert_not_null(NetworkedEvent.from_dict(opened_zero), "hand_seq=0 合法")
	var opened_max := _opened()
	opened_max["payload"]["hand_seq"] = MAX_HAND_SEQ
	assert_not_null(NetworkedEvent.from_dict(opened_max), "hand_seq=MAX_HAND_SEQ 合法")

	for invalid_hand_seq in [-1, MAX_HAND_SEQ + 1, 1.0]:
		for fixture in [_opened(), _closing(), _settled_full(), _cancelled(), _item_granted(0, 122)]:
			fixture["payload"]["hand_seq"] = invalid_hand_seq
			assert_null(
				NetworkedEvent.from_dict(fixture),
				"E5 hand_seq 越界或非严格 int 必须拒绝"
			)

	for invalid_window_index in [-1, MAX_SAFE_INT + 1, 1.0]:
		var bad_index := _opened()
		bad_index["payload"]["window_index"] = invalid_window_index
		assert_null(NetworkedEvent.from_dict(bad_index), "window_index 必须为非负安全整数")
	var max_index := _opened()
	max_index["payload"]["window_index"] = MAX_SAFE_INT
	assert_not_null(NetworkedEvent.from_dict(max_index), "window_index=MAX_SAFE_INT 合法")

	for boundary_key in ["closing_boundary_server_seq", "context_boundary_server_seq"]:
		for invalid_boundary in [0, -1, MAX_SAFE_INT + 1, 1.0]:
			var bad_boundary := _settled_full()
			bad_boundary["payload"][boundary_key] = invalid_boundary
			assert_null(
				NetworkedEvent.from_dict(bad_boundary),
				"%s 必须为正安全整数" % boundary_key
			)
	var cancelled_null := _cancelled(121, null)
	assert_not_null(NetworkedEvent.from_dict(cancelled_null), "CANCELLED boundary=null 合法")
	for invalid_cancelled_boundary in [0, -1, MAX_SAFE_INT + 1, 1.0]:
		var bad_cancelled := _cancelled(121, invalid_cancelled_boundary)
		assert_null(NetworkedEvent.from_dict(bad_cancelled), "非 null boundary 必须为正安全整数")

	for invalid_score in [-1, MAX_SAFE_INT + 1, 1.0]:
		var bad_score := _item_granted(0, 122)
		bad_score["payload"]["score"] = invalid_score
		assert_null(NetworkedEvent.from_dict(bad_score), "score 必须为非负安全整数")
	var max_score := _item_granted(0, 122)
	max_score["payload"]["score"] = MAX_SAFE_INT
	assert_not_null(NetworkedEvent.from_dict(max_score), "score=MAX_SAFE_INT 合法")


func test_settled_context_boundary_must_be_ge_closing_boundary() -> void:
	# 冻结语义：CLOSING 在第24弃后立即写 closing_boundary；
	# SETTLED.context_boundary 是随后 CLAIM 完成或无 CLAIM 同事务结果判定序号。
	# 因此 context_boundary_server_seq >= closing_boundary_server_seq（允许相等）。
	var equal_ok := _settled_full()
	equal_ok["payload"]["closing_boundary_server_seq"] = 110
	equal_ok["payload"]["context_boundary_server_seq"] = 110
	assert_not_null(
		NetworkedEvent.from_dict(equal_ok),
		"context_boundary == closing_boundary 合法（无 CLAIM 同事务）"
	)

	var context_lt_closing := _settled_full()
	context_lt_closing["payload"]["closing_boundary_server_seq"] = 110
	context_lt_closing["payload"]["context_boundary_server_seq"] = 109
	assert_null(
		NetworkedEvent.from_dict(context_lt_closing),
		"context_boundary < closing_boundary 必须拒绝"
	)


func test_display_only_zero_grants() -> void:
	var ev: NetworkedEvent = NetworkedEvent.from_dict(_settled_display())
	assert_not_null(ev)
	if ev == null:
		return
	var p: Dictionary = _payload_of(ev)
	assert_eq(str(p.get("outcome", "")), "DISPLAY_ONLY")
	assert_eq(int(p.get("grant_count", -1)), 0)


func test_cancelled_fixed_reason_no_outcome_or_matrix() -> void:
	var ev: NetworkedEvent = NetworkedEvent.from_dict(_cancelled())
	assert_not_null(ev)
	if ev == null:
		return
	var p: Dictionary = _payload_of(ev)
	assert_eq(str(p.get("cancel_reason", "")), "CANCELLED_BY_WIN")
	assert_false(p.has("outcome"), "CANCELLED 不含 outcome")
	assert_false(p.has("matrix_summary"), "CANCELLED 不含矩阵")
	assert_false(p.has("assignment"), "CANCELLED 不含 assignment")
	assert_eq(int(p.get("grant_count", -1)), 0)
	assert_eq(bool(p.get("scored", true)), false)

	var with_outcome := _cancelled()
	with_outcome["payload"]["outcome"] = "FULL_GRANT"
	assert_null(NetworkedEvent.from_dict(with_outcome), "CANCELLED 携带 outcome 拒绝")
	var with_matrix := _cancelled()
	with_matrix["payload"]["matrix_summary"] = {"scores": []}
	assert_null(NetworkedEvent.from_dict(with_matrix), "CANCELLED 携带 matrix 拒绝")
	var with_assign := _cancelled()
	with_assign["payload"]["assignment"] = {"0": "item_a"}
	assert_null(NetworkedEvent.from_dict(with_assign), "CANCELLED 携带 assignment 拒绝")


func test_item_granted_armed_for_window_id_null_or_nonempty() -> void:
	var with_next: NetworkedEvent = NetworkedEvent.from_dict(
		_item_granted(0, 122, "hand_3_window_2")
	)
	assert_not_null(with_next)
	if with_next != null:
		var p: Dictionary = _payload_of(with_next)
		assert_eq(str(p.get("armed_for_window_id")), "hand_3_window_2")

	var with_null: NetworkedEvent = NetworkedEvent.from_dict(
		_item_granted(1, 123, null)
	)
	assert_not_null(with_null, "armed_for_window_id=null 合法")
	if with_null != null:
		assert_eq(_payload_of(with_null).get("armed_for_window_id"), null)

	var empty_str := _item_granted(2, 124, "")
	assert_null(
		NetworkedEvent.from_dict(empty_str),
		"armed_for_window_id 不得用空串；应用 null 或非空字符串"
	)


func test_item_and_ability_required_fields() -> void:
	for f in [
		_item_granted(0, 122),
		_item_consumed(),
		_item_applied(),
		_armed(),
		_disarmed(),
	]:
		var ev: NetworkedEvent = NetworkedEvent.from_dict(f)
		assert_not_null(ev, "schema %s" % f["kind"])
		if ev == null:
			continue
		var p: Dictionary = _payload_of(ev)
		match str(f["kind"]):
			"ITEM_GRANTED":
				for k in [
					"window_id", "rule_version", "assignment_version", "matched_rule_ids",
					"item_id", "item_instance_id", "seat", "hand_seq", "score", "affinity_match",
					"armed_for_window_id",
				]:
					assert_true(p.has(k), "ITEM_GRANTED 缺 %s" % k)
			"ITEM_CONSUMED", "ITEM_APPLIED":
				assert_true(str(p.get("item_instance_id", "")).length() > 0)
				assert_true(str(p.get("command_id", "")).length() > 0)
			"CHARACTER_ABILITY_ARMED":
				assert_eq(str(p.get("active_window_id", "")), WINDOW_ID)
			"CHARACTER_ABILITY_DISARMED":
				assert_true(p.has("active_window_id"))


func test_each_e5_kind_fails_when_any_required_field_removed() -> void:
	var kinds := [
		"REWARD_WINDOW_OPENED", "REWARD_WINDOW_CLOSING", "REWARD_WINDOW_SETTLED",
		"REWARD_WINDOW_CANCELLED", "ITEM_GRANTED", "ITEM_CONSUMED", "ITEM_APPLIED",
		"CHARACTER_ABILITY_ARMED", "CHARACTER_ABILITY_DISARMED",
	]
	for kind in kinds:
		var base: Dictionary = _fixture_for_kind(kind)
		assert_not_null(NetworkedEvent.from_dict(base), "%s 完整 fixture 应通过" % kind)
		for field in _required_fields_for(kind):
			var bad: Dictionary = base.duplicate(true)
			var payload: Dictionary = (bad["payload"] as Dictionary).duplicate(true)
			assert_true(payload.has(field), "%s fixture 应含必填 %s" % [kind, field])
			payload.erase(field)
			bad["payload"] = payload
			assert_null(
				NetworkedEvent.from_dict(bad),
				"%s 删除必填字段 %s 后应解析失败" % [kind, field]
			)


func test_full_grant_exactly_four_item_granted_in_seat_order() -> void:
	var fixtures: Array = [
		_settled_full(120),
		_item_granted(0, 121),
		_item_granted(1, 122),
		_item_granted(2, 123),
		_item_granted(3, 124),
	]
	var parsed := _parse_all(fixtures)
	assert_eq(parsed.size(), 5)
	var seats: Array = []
	for i in range(1, fixtures.size()):
		var p: Dictionary = _payload_of(parsed[i] as NetworkedEvent)
		seats.append(int(p.get("seat", -1)))
	assert_eq(seats, [0, 1, 2, 3], "FULL_GRANT 强制恰好四次且 seat 0..3 顺序")

	_assert_order_illegal_with_meta([
		"REWARD_WINDOW_CLOSING",
		"REWARD_WINDOW_SETTLED",
		"ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED",
	], {"settled_outcome": "FULL_GRANT"}, "FULL_GRANT 少于 4 次 ITEM_GRANTED")
	_assert_order_illegal_with_meta([
		"REWARD_WINDOW_CLOSING",
		"REWARD_WINDOW_SETTLED",
		"ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED",
	], {"settled_outcome": "FULL_GRANT"}, "FULL_GRANT 多于 4 次 ITEM_GRANTED")


func test_display_only_forbids_any_item_granted() -> void:
	var fixtures: Array = [_closing(110), _settled_display(120), _disarmed(121)]
	_parse_all(fixtures)
	for f in fixtures:
		assert_ne(str(f["kind"]), "ITEM_GRANTED")
	_assert_order_illegal_with_meta([
		"REWARD_WINDOW_CLOSING",
		"REWARD_WINDOW_SETTLED",
		"ITEM_GRANTED",
	], {"settled_outcome": "DISPLAY_ONLY"}, "DISPLAY_ONLY 禁任何 ITEM_GRANTED")


# ---- 五条 ADR 合法偏序 + 第 24 弃 CLAIM 路径 ----
# 三出口偏序不弱化；CLAIM 后非和牌鸣牌用 PON
# PASS 可作为 ACTION_APPLIED（只投影提交者），但本 fixture 仍用 PON 表达鸣牌路径

func test_legal_order_full_24_no_win_with_claim_window() -> void:
	var kinds := [
		"ACTION_APPLIED",
		"REWARD_WINDOW_CLOSING",
		"CLAIM_WINDOW",
		"ACTION_APPLIED",
		"REWARD_WINDOW_SETTLED",
		"ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED",
	]
	_assert_order_legal(kinds, "满24无和牌+CLAIM")
	var fixtures: Array = [
		_action_applied(109, "DISCARD", 0),
		_closing(110),
		_claim_window(111),
		_action_applied(112, "PON", 1),
		_settled_full(120),
		_item_granted(0, 121),
		_item_granted(1, 122),
		_item_granted(2, 123),
		_item_granted(3, 124),
	]
	var parsed := _parse_all(fixtures)
	assert_eq(parsed.size(), 9)
	assert_eq(str(_payload_of(parsed[0] as NetworkedEvent).get("action_kind")), "DISCARD")
	assert_eq(str(fixtures[1]["kind"]), "REWARD_WINDOW_CLOSING")
	assert_eq(str(fixtures[2]["kind"]), "CLAIM_WINDOW")
	assert_eq(str(_payload_of(parsed[3] as NetworkedEvent).get("action_kind")), "PON")
	assert_eq(str(fixtures[4]["kind"]), "REWARD_WINDOW_SETTLED")
	for i in range(4):
		assert_eq(int(_payload_of(parsed[5 + i] as NetworkedEvent).get("seat", -1)), i)

	# CHI 变体同样合法
	_assert_order_legal(kinds, "满24无和牌+CHI")
	_parse_all([
		_action_applied(109, "DISCARD", 0),
		_closing(110),
		_claim_window(111),
		_action_applied(112, "CHI", 1),
		_settled_full(120),
		_item_granted(0, 121),
		_item_granted(1, 122),
		_item_granted(2, 123),
		_item_granted(3, 124),
	])


func test_legal_order_full_24_ron_cancel_no_settled_or_grant() -> void:
	var kinds := [
		"ACTION_APPLIED",
		"REWARD_WINDOW_CLOSING",
		"CLAIM_WINDOW",
		"ACTION_APPLIED",
		"REWARD_WINDOW_CANCELLED",
		"HAND_SETTLED",
	]
	_assert_order_legal(kinds, "第24弃荣和 cancel")
	var fixtures: Array = [
		_action_applied(109, "DISCARD", 0),
		_closing(110),
		_claim_window(111),
		_action_applied(112, "RON", 2),
		_cancelled(113),
		_hand_settled(114),
	]
	var parsed := _parse_all(fixtures)
	assert_eq(parsed.size(), 6)
	for f in fixtures:
		assert_ne(str(f["kind"]), "REWARD_WINDOW_SETTLED")
		assert_ne(str(f["kind"]), "ITEM_GRANTED")
	assert_eq(str(_payload_of(parsed[3] as NetworkedEvent).get("action_kind")), "RON")
	var ron_payload: Dictionary = _payload_of(parsed[3] as NetworkedEvent)
	var ron_rp: Dictionary = ron_payload.get("resolved_payload", {})
	assert_true(ron_rp.has("winning_tile"))
	assert_true(ron_rp.has("from_seat"), "RON resolved 必须 from_seat")
	assert_false(ron_rp.has("winner_seat"), "RON 不得 winner_seat")
	assert_ne(int(ron_rp.get("from_seat", -1)), int(ron_payload.get("seat", -1)),
		"RON from_seat != actor seat")
	assert_eq(str(fixtures[4]["kind"]), "REWARD_WINDOW_CANCELLED")
	assert_eq(str(fixtures[5]["kind"]), "HAND_SETTLED")


func test_legal_order_any_win_cancel() -> void:
	var kinds := [
		"REWARD_WINDOW_CANCELLED",
		"CHARACTER_ABILITY_DISARMED",
		"HAND_SETTLED",
	]
	_assert_order_legal(kinds, "任意和牌 cancel")
	_parse_all([
		_cancelled(50, null),
		_disarmed(51),
		_hand_settled(52),
	])


func test_legal_order_non_terminal_exhaustive_draw() -> void:
	var kinds := [
		"REWARD_WINDOW_CLOSING",
		"REWARD_WINDOW_SETTLED",
		"ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED",
		"CHARACTER_ABILITY_DISARMED",
		"HAND_SETTLED",
		"REWARD_WINDOW_OPENED",
		"CHARACTER_ABILITY_ARMED",
	]
	_assert_order_legal(kinds, "非终场流局")


func test_legal_order_terminal_display_only() -> void:
	var kinds := [
		"REWARD_WINDOW_CLOSING",
		"REWARD_WINDOW_SETTLED",
		"CHARACTER_ABILITY_DISARMED",
		"HAND_SETTLED",
		"MATCH_SETTLED",
	]
	_assert_order_legal(kinds, "终场非和牌展示")
	var fixtures: Array = [
		_closing(200),
		_settled_display(201),
		_disarmed(202),
		_hand_settled(203, "EXHAUSTIVE_DRAW"),
		_match_settled(204),
	]
	_parse_all(fixtures)
	for f in fixtures:
		assert_ne(str(f["kind"]), "ITEM_GRANTED")


func test_legal_order_open_direct_cancel_closing_boundary_null() -> void:
	var kinds := ["REWARD_WINDOW_OPENED", "REWARD_WINDOW_CANCELLED"]
	_assert_order_legal(kinds, "OPEN→CANCELLED")
	var cancelled_open := _cancelled(20, null)
	assert_eq(
		(cancelled_open["payload"] as Dictionary).get("closing_boundary_server_seq"),
		null,
		"OPEN→CANCELLED 的 closing_boundary_server_seq 应为 null"
	)
	_parse_all([_opened(10), cancelled_open])


func test_illegal_orders_typical() -> void:
	_assert_order_illegal([
		"REWARD_WINDOW_SETTLED", "REWARD_WINDOW_CANCELLED",
	], "SETTLED→CANCELLED")
	_assert_order_illegal([
		"REWARD_WINDOW_CANCELLED", "REWARD_WINDOW_SETTLED",
	], "CANCELLED→SETTLED")
	_assert_order_illegal_with_meta([
		"REWARD_WINDOW_CLOSING",
		"REWARD_WINDOW_SETTLED",
		"ITEM_GRANTED",
	], {"settled_outcome": "DISPLAY_ONLY"}, "DISPLAY_ONLY→ITEM_GRANTED")
	_assert_order_illegal([
		"REWARD_WINDOW_OPENED", "REWARD_WINDOW_SETTLED",
	], "OPEN 直接 SETTLED 跳过 CLOSING")
	_assert_order_illegal([
		"CHARACTER_ABILITY_ARMED", "REWARD_WINDOW_OPENED",
	], "ARM 不得先于目标窗 OPENED")


func test_fixtures_only_no_battle_controller_emission_required() -> void:
	var fixtures: Array = [_opened(), _closing(), _settled_full(), _cancelled()]
	assert_eq(fixtures.size(), 4)
	for f in fixtures:
		assert_eq(typeof(f), TYPE_DICTIONARY)
		assert_eq(int(f["protocol_version"]), 1)
		assert_true(f.has("view_hash"), "E5 fixture envelope 必须含 view_hash")
		assert_false(f.has("state_hash"), "E5 fixture 不得含 state_hash")


# ---- E5 payload exact reject extras ----

func test_e5_payloads_reject_extra_fields() -> void:
	var cases: Array = [
		["REWARD_WINDOW_OPENED", _opened()],
		["REWARD_WINDOW_CLOSING", _closing()],
		["REWARD_WINDOW_SETTLED", _settled_full()],
		["REWARD_WINDOW_CANCELLED", _cancelled()],
		["ITEM_GRANTED", _item_granted(0, 122)],
		["ITEM_CONSUMED", _item_consumed()],
		["ITEM_APPLIED", _item_applied()],
		["CHARACTER_ABILITY_ARMED", _armed()],
		["CHARACTER_ABILITY_DISARMED", _disarmed()],
	]
	for case in cases:
		var kind: String = case[0]
		var base: Dictionary = case[1]
		assert_not_null(NetworkedEvent.from_dict(base), "%s 完整 fixture 应先通过" % kind)
		var bad: Dictionary = base.duplicate(true)
		var payload: Dictionary = (bad["payload"] as Dictionary).duplicate(true)
		payload["unexpected_extra"] = true
		bad["payload"] = payload
		assert_null(
			NetworkedEvent.from_dict(bad),
			"%s payload 多余键 unexpected_extra 必须拒绝" % kind
		)

	var aa := _action_applied(1, "DISCARD", 0)
	assert_not_null(NetworkedEvent.from_dict(aa))
	var aa_extra: Dictionary = aa.duplicate(true)
	var aa_p: Dictionary = (aa_extra["payload"] as Dictionary).duplicate(true)
	aa_p["trace_id"] = "x"
	aa_extra["payload"] = aa_p
	assert_null(NetworkedEvent.from_dict(aa_extra), "ACTION_APPLIED payload extras 拒绝")


# ---- 偏序正例扩展 ----

func test_legal_order_terminal_win_to_match_settled() -> void:
	var omit_ability := [
		"REWARD_WINDOW_CANCELLED",
		"HAND_SETTLED",
		"MATCH_SETTLED",
	]
	_assert_order_legal(omit_ability, "终场和牌省略 ability")
	_parse_all([
		_cancelled(50, null),
		_hand_settled(51),
		_match_settled(52),
	])

	var with_disarms := [
		"REWARD_WINDOW_CANCELLED",
		"CHARACTER_ABILITY_DISARMED",
		"CHARACTER_ABILITY_DISARMED",
		"HAND_SETTLED",
		"MATCH_SETTLED",
	]
	_assert_order_legal(with_disarms, "终场和牌 2×DISARM→MATCH_SETTLED")


func test_legal_order_full_24_ron_terminal_to_match_settled() -> void:
	var kinds := [
		"ACTION_APPLIED",
		"REWARD_WINDOW_CLOSING",
		"CLAIM_WINDOW",
		"ACTION_APPLIED",
		"REWARD_WINDOW_CANCELLED",
		"CHARACTER_ABILITY_DISARMED",
		"HAND_SETTLED",
		"MATCH_SETTLED",
	]
	_assert_order_legal(kinds, "第24弃 RON 终场至 MATCH_SETTLED")
	_parse_all([
		_action_applied(109, "DISCARD", 0),
		_closing(110),
		_claim_window(111),
		_action_applied(112, "RON", 2),
		_cancelled(113),
		_disarmed(114),
		_hand_settled(115),
		_match_settled(116),
	])

	var omit_disarm := [
		"ACTION_APPLIED",
		"REWARD_WINDOW_CLOSING",
		"CLAIM_WINDOW",
		"ACTION_APPLIED",
		"REWARD_WINDOW_CANCELLED",
		"HAND_SETTLED",
		"MATCH_SETTLED",
	]
	_assert_order_legal(omit_disarm, "第24弃 RON 终场省略 DISARM")


func test_legal_order_full_24_grants_optional_0_to_4_disarm_open_arm() -> void:
	var base_grants := [
		"ACTION_APPLIED",
		"REWARD_WINDOW_CLOSING",
		"CLAIM_WINDOW",
		"ACTION_APPLIED",
		"REWARD_WINDOW_SETTLED",
		"ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED",
	]

	var omit := base_grants.duplicate()
	omit.append("REWARD_WINDOW_OPENED")
	_assert_order_legal(omit, "满24 grants 后省略 ability 直接 OPEN")

	var one := base_grants.duplicate()
	one.append_array([
		"CHARACTER_ABILITY_DISARMED",
		"REWARD_WINDOW_OPENED",
		"CHARACTER_ABILITY_ARMED",
	])
	_assert_order_legal(one, "满24 grants 后 1 DISARM→OPEN→1 ARM")

	var four := base_grants.duplicate()
	for _i in range(4):
		four.append("CHARACTER_ABILITY_DISARMED")
	four.append("REWARD_WINDOW_OPENED")
	for _j in range(4):
		four.append("CHARACTER_ABILITY_ARMED")
	_assert_order_legal(four, "满24 grants 后 4 DISARM→OPEN→4 ARM")

	var two_zero := base_grants.duplicate()
	two_zero.append_array([
		"CHARACTER_ABILITY_DISARMED",
		"CHARACTER_ABILITY_DISARMED",
		"REWARD_WINDOW_OPENED",
	])
	_assert_order_legal(two_zero, "满24 grants 后 2 DISARM→OPEN→0 ARM")

	_assert_order_legal([
		"REWARD_WINDOW_CLOSING",
		"REWARD_WINDOW_SETTLED",
		"ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED",
		"HAND_SETTLED",
		"REWARD_WINDOW_OPENED",
	], "非终场流局省略 DISARM/ARM")

	_assert_order_legal([
		"REWARD_WINDOW_CLOSING",
		"REWARD_WINDOW_SETTLED",
		"HAND_SETTLED",
		"MATCH_SETTLED",
	], "终场 DISPLAY_ONLY 省略 DISARM")


# ---- meta 正例穿过合法 path + 反例 ----

func test_meta_positive_passes_through_legal_paths() -> void:
	var full_claim := [
		"ACTION_APPLIED",
		"REWARD_WINDOW_CLOSING",
		"CLAIM_WINDOW",
		"ACTION_APPLIED",
		"REWARD_WINDOW_SETTLED",
		"ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED",
	]
	_assert_order_legal_with_meta(full_claim, {
		"settled_outcome": "FULL_GRANT",
		"grant_seats": [0, 1, 2, 3],
	}, "FULL_GRANT+grant_seats 穿过满24 CLAIM path")

	var non_terminal := [
		"REWARD_WINDOW_CLOSING",
		"REWARD_WINDOW_SETTLED",
		"ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED",
		"CHARACTER_ABILITY_DISARMED",
		"HAND_SETTLED",
		"REWARD_WINDOW_OPENED",
		"CHARACTER_ABILITY_ARMED",
	]
	_assert_order_legal_with_meta(non_terminal, {
		"settled_outcome": "FULL_GRANT",
		"grant_seats": [0, 1, 2, 3],
	}, "FULL_GRANT+grant_seats 穿过非终场流局 path")

	var display_only := [
		"REWARD_WINDOW_CLOSING",
		"REWARD_WINDOW_SETTLED",
		"CHARACTER_ABILITY_DISARMED",
		"HAND_SETTLED",
		"MATCH_SETTLED",
	]
	_assert_order_legal_with_meta(display_only, {
		"settled_outcome": "DISPLAY_ONLY",
	}, "DISPLAY_ONLY meta 穿过终场展示 path")


func test_meta_rejects_unknown_or_non_string_outcome_and_bad_grant_seats() -> void:
	var full_path := [
		"REWARD_WINDOW_CLOSING",
		"REWARD_WINDOW_SETTLED",
		"ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED",
		"CHARACTER_ABILITY_DISARMED",
		"HAND_SETTLED",
		"REWARD_WINDOW_OPENED",
		"CHARACTER_ABILITY_ARMED",
	]

	_assert_order_illegal_with_meta(full_path, {
		"settled_outcome": "CANCELLED_BY_WIN",
	}, "未知 settled_outcome 拒绝")
	_assert_order_illegal_with_meta(full_path, {
		"settled_outcome": "PARTIAL_GRANT",
	}, "未定义 outcome 拒绝")
	_assert_order_illegal_with_meta(full_path, {
		"settled_outcome": 1,
	}, "settled_outcome 非 String 拒绝")
	_assert_order_illegal_with_meta(full_path, {
		"settled_outcome": null,
	}, "settled_outcome=null 拒绝")
	_assert_order_illegal_with_meta(full_path, {
		"settled_outcome": true,
	}, "settled_outcome bool 拒绝")

	_assert_order_illegal_with_meta(full_path, {
		"settled_outcome": "FULL_GRANT",
		"grant_seats": "0,1,2,3",
	}, "grant_seats 非 Array 拒绝")
	_assert_order_illegal_with_meta(full_path, {
		"settled_outcome": "FULL_GRANT",
		"grant_seats": {"0": 0, "1": 1, "2": 2, "3": 3},
	}, "grant_seats Dictionary 拒绝")
	_assert_order_illegal_with_meta(full_path, {
		"settled_outcome": "FULL_GRANT",
		"grant_seats": [0, 1, 2, "3"],
	}, "grant_seats 元素非 int 拒绝")
	_assert_order_illegal_with_meta(full_path, {
		"settled_outcome": "FULL_GRANT",
		"grant_seats": [0.0, 1.0, 2.0, 3.0],
	}, "grant_seats float 拒绝（不得 int 强转）")
	_assert_order_illegal_with_meta(full_path, {
		"settled_outcome": "FULL_GRANT",
		"grant_seats": [1, 0, 2, 3],
	}, "grant_seats 错顺序拒绝")
	_assert_order_illegal_with_meta(full_path, {
		"settled_outcome": "FULL_GRANT",
		"grant_seats": [0, 1, 2],
	}, "grant_seats 长度不足拒绝")
	_assert_order_illegal_with_meta(full_path, {
		"settled_outcome": "FULL_GRANT",
		"grant_seats": [0, 1, 2, 3, 4],
	}, "grant_seats 长度过长拒绝")


func test_meta_outcome_must_match_path_cancel_rejects_settled_outcomes() -> void:
	var cancel_hand := ["REWARD_WINDOW_CANCELLED", "HAND_SETTLED"]
	var open_cancel := ["REWARD_WINDOW_OPENED", "REWARD_WINDOW_CANCELLED"]

	_assert_order_illegal_with_meta(cancel_hand, {
		"settled_outcome": "DISPLAY_ONLY",
	}, "cancel→HAND_SETTLED 不得挂 DISPLAY_ONLY")
	_assert_order_illegal_with_meta(open_cancel, {
		"settled_outcome": "DISPLAY_ONLY",
	}, "OPEN→CANCELLED 不得挂 DISPLAY_ONLY")

	_assert_order_illegal_with_meta(cancel_hand, {
		"settled_outcome": "FULL_GRANT",
	}, "cancel→HAND_SETTLED 不得挂 FULL_GRANT")
	_assert_order_illegal_with_meta(open_cancel, {
		"settled_outcome": "FULL_GRANT",
	}, "OPEN→CANCELLED 不得挂 FULL_GRANT")


func test_e5_envelope_rejects_missing_view_hash_and_state_hash() -> void:
	var base := _opened()
	assert_not_null(NetworkedEvent.from_dict(base))
	var no_hash := base.duplicate(true)
	no_hash.erase("view_hash")
	assert_null(NetworkedEvent.from_dict(no_hash), "E5 事件缺 view_hash 拒绝")
	var with_state := base.duplicate(true)
	with_state["state_hash"] = VIEW_HASH
	assert_null(NetworkedEvent.from_dict(with_state), "E5 事件 state_hash 拒绝")


# ---- #232 E5 boundary ≤ envelope.server_seq（生产缺口 Red）----

func test_e5_boundaries_must_be_le_envelope_server_seq() -> void:
	# CLOSING：closing_boundary > server_seq 必须拒绝
	var bad_closing := _closing(100)  # payload boundary 仍为 110
	assert_eq(int(bad_closing["server_seq"]), 100)
	assert_eq(int((bad_closing["payload"] as Dictionary)["closing_boundary_server_seq"]), 110)
	assert_null(
		NetworkedEvent.from_dict(bad_closing),
		"REWARD_WINDOW_CLOSING closing_boundary > envelope.server_seq 必须拒绝"
	)
	# 正例：boundary == server_seq
	assert_not_null(NetworkedEvent.from_dict(_closing(110)), "closing_boundary == server_seq 合法")

	# SETTLED：closing 或 context > server_seq 拒绝
	var bad_settled := _settled_full(100)
	assert_null(
		NetworkedEvent.from_dict(bad_settled),
		"REWARD_WINDOW_SETTLED boundary > server_seq 必须拒绝"
	)
	# context > server_seq 但 closing <= server_seq
	var context_gt := _settled_full(115)
	(context_gt["payload"] as Dictionary)["closing_boundary_server_seq"] = 110
	(context_gt["payload"] as Dictionary)["context_boundary_server_seq"] = 118
	assert_null(
		NetworkedEvent.from_dict(context_gt),
		"context_boundary > envelope.server_seq 必须拒绝"
	)
	# 正例：双边界均 <= server_seq 且 context>=closing
	assert_not_null(NetworkedEvent.from_dict(_settled_full(120)), "SETTLED 双边界 <= server_seq 合法")

	# CANCELLED：非 null closing_boundary > server_seq 拒绝
	var bad_cancel := _cancelled(100, 110)
	assert_null(
		NetworkedEvent.from_dict(bad_cancel),
		"REWARD_WINDOW_CANCELLED closing_boundary > server_seq 必须拒绝"
	)
	assert_not_null(
		NetworkedEvent.from_dict(_cancelled(110, 110)),
		"CANCELLED closing_boundary == server_seq 合法"
	)
	# null boundary 不参与比较（OPEN 直接取消）
	assert_not_null(
		NetworkedEvent.from_dict(_cancelled(50, null)),
		"CANCELLED closing_boundary=null 合法"
	)


func test_e5_action_applied_and_claim_require_hand_seq_namespace() -> void:
	# 正例 fixture 已迁移到 hand_seq=3 命名空间
	var aa := _action_applied(50, "DISCARD")
	assert_not_null(NetworkedEvent.from_dict(aa), "E5 ACTION_APPLIED 命名空间正例")
	# 反例：iid=10 自身 canonical（合法 identity），但落在 hand_seq=0 命名空间，
	# 与 payload.hand_seq=3 的 [408,543] 不匹配 → 仅测跨局 namespace 拒绝
	var bad := aa.duplicate(true)
	((bad["payload"] as Dictionary)["resolved_payload"] as Dictionary)["tile"] = (
		_canonical_tile_view_for_iid(10)
	)
	assert_null(
		NetworkedEvent.from_dict(bad),
		"E5 ACTION_APPLIED resolved 实体跨局命名空间必须拒绝"
	)
	var claim := _claim_window(111)
	assert_not_null(NetworkedEvent.from_dict(claim), "E5 CLAIM_WINDOW 命名空间正例")
	var bad_claim := claim.duplicate(true)
	(bad_claim["payload"] as Dictionary)["discarded_tile"] = _canonical_tile_view_for_iid(10)
	assert_null(
		NetworkedEvent.from_dict(bad_claim),
		"E5 CLAIM discarded_tile 跨局命名空间必须拒绝"
	)
