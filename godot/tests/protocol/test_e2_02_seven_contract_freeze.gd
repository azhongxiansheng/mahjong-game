extends GutTest

# E2-02（#232）TDD Red：冻结七点契约（仅测试；生产尚未满足 → 必须失败）。
# 禁止 snapshot_hash 等旧 hash、Action hand_seq 命名空间、ROOM_SNAPSHOT 副露全局约束、
# E5EventOrder 严格 String、CommandResult ACCEPTED.server_seq≥1、ProtocolConstants 单源、
# TURN_PROMPT 拒 ITEM_USE（命令侧仍接受）。

const ROOM := "room_x"
const CMD := "550e8400-e29b-41d4-a716-446655440000"
const DECISION := "550e8400-e29b-41d4-a716-4466554400aa"
const VIEW_HASH := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
const ORDER_SCRIPT := "res://protocol/e5_event_order.gd"
const CONSTANTS_PATH := "res://protocol/protocol_constants.gd"
const TILES_PER_HAND := 136
const FORBIDDEN_HASH_KEYS := ["snapshot_hash", "state_hash", "full_state_hash"]
const SEAT_WINDS := [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N]


func _ns(hand_seq: int, serial: int) -> int:
	return hand_seq * TILES_PER_HAND + serial


func _action_wire(
	kind: String,
	payload: Dictionary,
	hand_seq: int = 3,
	seat: int = 0,
	client_seq: int = 1
) -> Dictionary:
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


## Wall canonical：serial=iid%136 → tile=ALL[serial/4]、owner=serial%4、五牌 copy0 为赤
func _canonical_tile_for_iid(iid: int) -> Dictionary:
	var serial: int = iid % TILES_PER_HAND
	@warning_ignore("integer_division")
	var tile_index: int = serial / 4
	var tile_id: int = TileId.ALL[tile_index]
	var owner_seat: int = serial % 4
	var is_red: bool = (
		(tile_id == TileId.W5 or tile_id == TileId.T5 or tile_id == TileId.S5)
		and owner_seat == 0
	)
	return {
		"instance_id": iid,
		"tile_id": tile_id,
		"is_red_dora": is_red,
		"owner_seat": owner_seat,
	}


## iid = TileId.ALL.find(tile_id)*4 + copy + hand_seq*136
func _canonical_tile(tile_id: int, copy: int, hand_seq: int = 0) -> Dictionary:
	var idx: int = TileId.ALL.find(tile_id)
	var iid: int = idx * 4 + copy + hand_seq * TILES_PER_HAND
	return _canonical_tile_for_iid(iid)


## serial_base 选不冲突牌种组（tile_index=serial_base/4）；owner 仅由 iid 公式决定
func _meld_view(
	kind: String,
	meld_id: int,
	from_seat: int,
	hand_seq: int,
	_holder_seat: int,
	serial_base: int
) -> Dictionary:
	@warning_ignore("integer_division")
	var base_idx: int = serial_base / 4
	var tiles: Array = []
	var called: int = -1
	var added: int = -1
	var fs: int = from_seat
	if kind == "ANKAN":
		fs = -1
		var ankan_tid: int = TileId.ALL[base_idx]
		for copy in range(4):
			tiles.append(_canonical_tile(ankan_tid, copy, hand_seq))
	elif kind == "CHI":
		# 同花连续三张：serial_base 映射到数牌 suit 内 1-7 起点，避免跨花色
		var chi_idx: int = base_idx
		if chi_idx >= 27:
			chi_idx = 0
		@warning_ignore("integer_division")
		var suit_base: int = (chi_idx / 9) * 9
		var num0: int = chi_idx % 9
		if num0 > 6:
			num0 = 6
		var start_idx: int = suit_base + num0
		var hold_copy: int = 0 if fs != 0 else 1
		var t0: Dictionary = _canonical_tile(TileId.ALL[start_idx], hold_copy, hand_seq)
		var t1: Dictionary = _canonical_tile(TileId.ALL[start_idx + 1], hold_copy, hand_seq)
		var t_called: Dictionary = _canonical_tile(TileId.ALL[start_idx + 2], fs, hand_seq)
		called = int(t_called["instance_id"])
		tiles = [t0, t1, t_called]
	elif kind == "MINKAN":
		var minkan_tid: int = TileId.ALL[base_idx]
		var t_called_mk: Dictionary = _canonical_tile(minkan_tid, fs, hand_seq)
		called = int(t_called_mk["instance_id"])
		for o in range(4):
			if o == fs:
				continue
			tiles.append(_canonical_tile(minkan_tid, o, hand_seq))
		tiles.append(t_called_mk)
	elif kind == "ADDED_KAN":
		var added_tid: int = TileId.ALL[base_idx]
		var added_copy: int = 3 if fs != 3 else 1
		var t_called_ak: Dictionary = _canonical_tile(added_tid, fs, hand_seq)
		var t_added: Dictionary = _canonical_tile(added_tid, added_copy, hand_seq)
		called = int(t_called_ak["instance_id"])
		added = int(t_added["instance_id"])
		for o in range(4):
			if o == fs or o == added_copy:
				continue
			tiles.append(_canonical_tile(added_tid, o, hand_seq))
		tiles.append(t_called_ak)
		tiles.append(t_added)
	else:
		# PON：同 tile 不同 copies；called 引用 tiles 中对应 iid
		var pon_tid: int = TileId.ALL[base_idx]
		var t_called_pn: Dictionary = _canonical_tile(pon_tid, fs, hand_seq)
		called = int(t_called_pn["instance_id"])
		var picked := 0
		for o in range(4):
			if o == fs:
				continue
			tiles.append(_canonical_tile(pon_tid, o, hand_seq))
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


func _seat_view(
	seat: int,
	_hand_seq: int,
	melds: Array = [],
	concealed: Array = []
) -> Dictionary:
	var tiles: Array = concealed
	var count: int = tiles.size()
	if tiles.is_empty() and seat != 0:
		count = 13
	return {
		"seat": seat,
		"seat_wind": SEAT_WINDS[seat],
		"score": 25000,
		"concealed_tiles": tiles.duplicate(true),
		"concealed_count": count,
		"last_drawn_tile_instance_id": -1,
		"river": [],
		"melds": melds.duplicate(true),
		"riichi_declared": false,
		"riichi_double": false,
		"riichi_discard_index": -1,
	}


func _core_table(hand_seq: int, seats: Array) -> Dictionary:
	return {
		"recipient_seat": 0,
		"hand_seq": hand_seq,
		"dealer_seat": 0,
		"current_seat": 0,
		"phase": "DRAW",
		"round_wind": TileId.E,
		"hand_number": 1,
		"honba": 0,
		"riichi_sticks": 0,
		"live_wall_count": 70,
		"dora_indicators": [_canonical_tile_for_iid(_ns(hand_seq, 1))],
		"seats": seats.duplicate(true),
	}


func _room_snapshot_event(server_seq: int, modules: Array) -> Dictionary:
	var payload := {
		"snapshot_server_seq": server_seq,
		"next_server_seq": server_seq + 1,
		"seat_view": 0,
		"modules": modules.duplicate(true),
	}
	var vh: String = ProtocolViewCodec.compute_view_hash(payload)
	if vh.is_empty():
		vh = VIEW_HASH
	return {
		"protocol_version": 1,
		"server_seq": server_seq,
		"room_id": ROOM,
		"kind": "ROOM_SNAPSHOT",
		"payload": payload,
		"view_hash": vh,
	}


func _flat_event(kind: String, server_seq: int, payload: Dictionary) -> Dictionary:
	return {
		"protocol_version": 1,
		"server_seq": server_seq,
		"room_id": ROOM,
		"kind": kind,
		"payload": payload.duplicate(true),
		"view_hash": VIEW_HASH,
	}


func _hand_settled_payload() -> Dictionary:
	return {
		"hand_seq": 3,
		"outcome": "RON",
		"winner_seats": [0],
		"loser_seat": 1,
		"score_deltas": [8000, -8000, 0, 0],
		"scores": [33000, 17000, 25000, 25000],
		"dealer_seat": 0,
		"renchan": true,
		"honba": 1,
		"riichi_sticks": 0,
		"adjustments": [],
	}


func _turn_payload_with_item_use(hand_seq: int = 1) -> Dictionary:
	var iid: int = _ns(hand_seq, 10)
	return {
		"hand_seq": hand_seq,
		"decision_id": DECISION,
		"seat": 0,
		"hand": [_canonical_tile_for_iid(iid)],
		"last_drawn_tile_instance_id": -1,
		"allowed_actions": [
			{"kind": "DISCARD", "payload_options": [{"tile_instance_id": iid}]},
			{"kind": "ITEM_USE", "payload_options": [{"item_instance_id": "inst_abc"}]},
		],
	}


# =============================================================================
# (1) Action 实体字段 ∈ envelope.hand_seq 的 136 张命名空间；meld_id 除外
# =============================================================================

func test_action_tile_entities_must_belong_to_hand_seq_namespace() -> void:
	var hs := 3
	var in_ns: int = _ns(hs, 10) # 418
	var out_ns: int = 42 # hand_seq=0 域

	# 合法：DISCARD 实体落在命名空间
	assert_not_null(
		Action.from_dict(_action_wire("DISCARD", {"tile_instance_id": in_ns}, hs)),
		"DISCARD 命名空间内 instance_id 应接受"
	)
	# 非法：跨 hand_seq 命名空间
	assert_null(
		Action.from_dict(_action_wire("DISCARD", {"tile_instance_id": out_ns}, hs)),
		"DISCARD tile_instance_id 必须属于 envelope.hand_seq 命名空间"
	)
	assert_null(
		Action.from_dict(_action_wire("RIICHI", {"tile_instance_id": out_ns}, hs)),
		"RIICHI tile_instance_id 必须属于 hand_seq 命名空间"
	)
	assert_null(
		Action.from_dict(_action_wire("CHI", {
			"companion_tile_instance_ids": [out_ns, in_ns],
		}, hs)),
		"CHI companion 必须全部在 hand_seq 命名空间"
	)
	assert_null(
		Action.from_dict(_action_wire("PON", {
			"companion_tile_instance_ids": [in_ns, out_ns],
		}, hs)),
		"PON companion 必须全部在 hand_seq 命名空间"
	)
	assert_null(
		Action.from_dict(_action_wire("KAN", {
			"kan_kind": "MINKAN",
			"companion_tile_instance_ids": [in_ns, in_ns + 1, out_ns],
		}, hs)),
		"MINKAN companion 必须全部在 hand_seq 命名空间"
	)
	assert_null(
		Action.from_dict(_action_wire("KAN", {
			"kan_kind": "ANKAN",
			"tile_instance_ids": [in_ns, in_ns + 1, in_ns + 2, out_ns],
		}, hs)),
		"ANKAN tile_instance_ids 必须全部在 hand_seq 命名空间"
	)
	assert_null(
		Action.from_dict(_action_wire("KAN", {
			"kan_kind": "ADDED_KAN",
			"meld_id": 0,
			"added_tile_instance_id": out_ns,
		}, hs)),
		"ADDED_KAN added_tile_instance_id 必须属于 hand_seq 命名空间"
	)

	# meld_id 不参与 136 命名空间：可取命名空间外 safe int，只要 added 在域内
	assert_not_null(
		Action.from_dict(_action_wire("KAN", {
			"kan_kind": "ADDED_KAN",
			"meld_id": 999999, # 远超 136 域，仍是独立 meld 序号
			"added_tile_instance_id": in_ns,
		}, hs)),
		"meld_id 不属于 hand_seq 136 命名空间，应允许任意 safe 非负 int"
	)


# =============================================================================
# (2) 递归禁 snapshot_hash / state_hash / full_state_hash（含 unknown module / E5）
# =============================================================================

func test_forbidden_hash_keys_rejected_recursively_including_unknown_and_e5() -> void:
	# 业务事件 envelope / payload 递归禁三键（含 exact 多余键与深层嵌套）
	var base := _flat_event("HAND_SETTLED", 9, _hand_settled_payload())
	for forbidden in FORBIDDEN_HASH_KEYS:
		var env_bad := base.duplicate(true)
		env_bad[forbidden] = VIEW_HASH
		assert_null(
			NetworkedEvent.from_dict(env_bad),
			"envelope 含 %s 必须拒绝" % forbidden
		)
		var p_bad := base.duplicate(true)
		var p: Dictionary = (p_bad["payload"] as Dictionary).duplicate(true)
		p[forbidden] = VIEW_HASH
		p_bad["payload"] = p
		assert_null(
			NetworkedEvent.from_dict(p_bad),
			"payload 顶层 %s 必须拒绝" % forbidden
		)

	# E5 opaque：SETTLED.transcript_summary 为 JSON-safe opaque，嵌套禁键必须拒绝
	# （不得仅因 exact keys 失败；此路径否则可合法通过 validator）
	for forbidden in FORBIDDEN_HASH_KEYS:
		var e5 := _flat_event("REWARD_WINDOW_SETTLED", 120, {
			"window_id": "hand_3_window_1",
			"outcome": "DISPLAY_ONLY",
			"settle_reason": "MATCH_END_NO_WIN",
			"rule_version": "reward_v2",
			"assignment_version": "assign_v1",
			"prize_pool": ["item_a", "item_b", "item_c", "item_d"],
			"matrix_summary": {},
			"assignment": {"0": "item_a", "1": "item_b", "2": "item_c", "3": "item_d"},
			"closing_boundary_server_seq": 110,
			"context_boundary_server_seq": 118,
			"grace_deadline_at": "2026-07-22T12:00:01.500Z",
			"grant_count": 0,
			"hand_seq": 3,
			"transcript_summary": {forbidden: VIEW_HASH},
		})
		assert_null(
			NetworkedEvent.from_dict(e5),
			"E5 transcript_summary opaque 嵌套 %s 必须拒绝" % forbidden
		)

	# ROOM_SNAPSHOT unknown module payload 内嵌禁键
	var hs := 0
	var seats: Array = []
	for i in range(4):
		if i == 0:
			seats.append(_seat_view(0, hs, [], [
				_canonical_tile_for_iid(_ns(hs, 10)),
			]))
		else:
			seats.append(_seat_view(i, hs))
	for forbidden in FORBIDDEN_HASH_KEYS:
		var unknown_payload := {
			"n": 1,
			"nested": {forbidden: "deadbeef"},
		}
		var modules: Array = [
			{
				"module_key": "core_table",
				"schema_version": 1,
				"payload": _core_table(hs, seats),
			},
			{
				"module_key": "z_ext",
				"schema_version": 1,
				"payload": unknown_payload,
			},
		]
		assert_null(
			NetworkedEvent.from_dict(_room_snapshot_event(17, modules)),
			"unknown module 嵌套 %s 必须拒绝" % forbidden
		)


# =============================================================================
# (3) ROOM_SNAPSHOT：meld_id 四席全局唯一；鸣牌 from_seat 规则
# =============================================================================

func test_room_snapshot_meld_id_global_unique_and_from_seat_rules() -> void:
	var hs := 0
	var seq := 17

	# 跨席 meld_id 重复必须拒绝（仅同席唯一不够）
	# paired baseline：不同 physical tiles + 唯一 meld_id 应可通过
	var seats_unique: Array = []
	for i in range(4):
		if i == 0:
			seats_unique.append(_seat_view(0, hs, [
				_meld_view("PON", 7, 1, hs, 0, 30),
			], []))
		elif i == 1:
			seats_unique.append(_seat_view(1, hs, [
				_meld_view("PON", 8, 2, hs, 1, 50),
			], []))
		else:
			seats_unique.append(_seat_view(i, hs))
	assert_not_null(
		NetworkedEvent.from_dict(_room_snapshot_event(seq, [{
			"module_key": "core_table",
			"schema_version": 1,
			"payload": _core_table(hs, seats_unique),
		}])),
		"paired baseline：唯一 meld_id + 不同 physical tiles 应接受"
	)
	# 仅令 meld_id 重复，physical tiles 仍互不冲突
	var seats_dup: Array = []
	for i in range(4):
		if i == 0:
			seats_dup.append(_seat_view(0, hs, [
				_meld_view("PON", 7, 1, hs, 0, 30),
			], []))
		elif i == 1:
			seats_dup.append(_seat_view(1, hs, [
				_meld_view("PON", 7, 2, hs, 1, 50),
			], []))
		else:
			seats_dup.append(_seat_view(i, hs))
	assert_null(
		NetworkedEvent.from_dict(_room_snapshot_event(seq, [{
			"module_key": "core_table",
			"schema_version": 1,
			"payload": _core_table(hs, seats_dup),
		}])),
		"ROOM_SNAPSHOT meld_id 必须四席全局唯一"
	)

	# CHI/PON/MINKAN/ADDED_KAN：from_seat 不得等于持有席
	# 先构造该 kind 合法 from，再只 mutate from_seat
	for kind in ["CHI", "PON", "MINKAN", "ADDED_KAN"]:
		var legal_from: int = (0 + 3) % 4 if kind == "CHI" else 1
		var m_base: Dictionary = _meld_view(kind, 1, legal_from, hs, 0, 30)
		var seats_base: Array = []
		for i in range(4):
			if i == 0:
				seats_base.append(_seat_view(0, hs, [m_base.duplicate(true)], []))
			else:
				seats_base.append(_seat_view(i, hs))
		assert_not_null(
			NetworkedEvent.from_dict(_room_snapshot_event(seq, [{
				"module_key": "core_table",
				"schema_version": 1,
				"payload": _core_table(hs, seats_base),
			}])),
			"%s paired baseline：合法 from_seat 应接受" % kind
		)
		var m_bad: Dictionary = m_base.duplicate(true)
		m_bad["from_seat"] = 0 # 仅 mutate：holder=0
		var bad_from: Array = []
		for i in range(4):
			if i == 0:
				bad_from.append(_seat_view(0, hs, [m_bad], []))
			else:
				bad_from.append(_seat_view(i, hs))
		assert_null(
			NetworkedEvent.from_dict(_room_snapshot_event(seq, [{
				"module_key": "core_table",
				"schema_version": 1,
				"payload": _core_table(hs, bad_from),
			}])),
			"%s from_seat 不得等于持有席" % kind
		)

	# CHI 来源必须是持有席上家 (seat+3)%4
	var hold_seat := 2
	var kamicha: int = (hold_seat + 3) % 4
	var not_kamicha: int = (hold_seat + 1) % 4 # 下家，非上家
	var m_chi_ok: Dictionary = _meld_view("CHI", 3, kamicha, hs, hold_seat, 60)
	var seats_chi_ok: Array = []
	for i in range(4):
		if i == hold_seat:
			seats_chi_ok.append(_seat_view(hold_seat, hs, [m_chi_ok.duplicate(true)], []))
		else:
			seats_chi_ok.append(_seat_view(i, hs))
	assert_not_null(
		NetworkedEvent.from_dict(_room_snapshot_event(seq, [{
			"module_key": "core_table",
			"schema_version": 1,
			"payload": _core_table(hs, seats_chi_ok),
		}])),
		"CHI kamicha paired baseline 应接受"
	)
	var m_chi_bad: Dictionary = m_chi_ok.duplicate(true)
	m_chi_bad["from_seat"] = not_kamicha # 仅换 from
	var seats_chi_bad: Array = []
	for i in range(4):
		if i == hold_seat:
			seats_chi_bad.append(_seat_view(hold_seat, hs, [m_chi_bad], []))
		else:
			seats_chi_bad.append(_seat_view(i, hs))
	assert_null(
		NetworkedEvent.from_dict(_room_snapshot_event(seq, [{
			"module_key": "core_table",
			"schema_version": 1,
			"payload": _core_table(hs, seats_chi_bad),
		}])),
		"CHI from_seat 必须是持有席上家 (seat+3)%%4"
	)

	# 正例：CHI kamicha + 其它鸣牌 from≠owner + ANKAN=-1，meld_id 全局唯一
	# serial_base 选不冲突牌种：dora serial1 + CHI20 + PON40 + ANKAN70
	var seats_ok: Array = []
	for i in range(4):
		if i == 0:
			seats_ok.append(_seat_view(0, hs, [
				_meld_view("CHI", 10, (0 + 3) % 4, hs, 0, 20),
			], []))
		elif i == 1:
			seats_ok.append(_seat_view(1, hs, [
				_meld_view("PON", 11, 2, hs, 1, 40),
			], []))
		elif i == 2:
			seats_ok.append(_seat_view(2, hs, [
				_meld_view("ANKAN", 12, -1, hs, 2, 70),
			], []))
		else:
			seats_ok.append(_seat_view(i, hs))
	assert_not_null(
		NetworkedEvent.from_dict(_room_snapshot_event(seq, [{
			"module_key": "core_table",
			"schema_version": 1,
			"payload": _core_table(hs, seats_ok),
		}])),
		"合法 CHI 上家 / PON / ANKAN=-1 / 全局唯一 meld_id 应接受"
	)

	# ANKAN from_seat 必须 -1（先合法构造，再只 mutate from）
	var ankan_ok: Dictionary = _meld_view("ANKAN", 1, -1, hs, 0, 20)
	var seats_ankan_ok: Array = []
	for i in range(4):
		if i == 0:
			seats_ankan_ok.append(_seat_view(0, hs, [ankan_ok.duplicate(true)], []))
		else:
			seats_ankan_ok.append(_seat_view(i, hs))
	assert_not_null(
		NetworkedEvent.from_dict(_room_snapshot_event(seq, [{
			"module_key": "core_table",
			"schema_version": 1,
			"payload": _core_table(hs, seats_ankan_ok),
		}])),
		"ANKAN from=-1 paired baseline 应接受"
	)
	var ankan_bad: Dictionary = ankan_ok.duplicate(true)
	ankan_bad["from_seat"] = 1
	var seats_ankan_bad: Array = []
	for i in range(4):
		if i == 0:
			seats_ankan_bad.append(_seat_view(0, hs, [ankan_bad], []))
		else:
			seats_ankan_bad.append(_seat_view(i, hs))
	assert_null(
		NetworkedEvent.from_dict(_room_snapshot_event(seq, [{
			"module_key": "core_table",
			"schema_version": 1,
			"payload": _core_table(hs, seats_ankan_bad),
		}])),
		"ANKAN from_seat 必须为 -1"
	)


# =============================================================================
# (4) E5EventOrder：kinds 元素与 meta keys 必须 TYPE_STRING，拒 StringName/数字
# =============================================================================

func test_e5_event_order_kinds_and_meta_keys_require_type_string() -> void:
	assert_true(ResourceLoader.exists(ORDER_SCRIPT), "E5EventOrder 脚本必须存在")
	var script: GDScript = load(ORDER_SCRIPT) as GDScript
	assert_not_null(script)
	if script == null:
		return

	# 合法对照：纯 String kinds
	var legal_kinds: Array = ["REWARD_WINDOW_OPENED", "REWARD_WINDOW_CANCELLED"]
	assert_true(
		bool(script.call("is_legal_sequence", legal_kinds)),
		"纯 String kinds 合法路径应 true"
	)

	# kinds 含 StringName → 必须 false（禁止 str() 静默强转）
	var sn_kinds: Array = [
		StringName("REWARD_WINDOW_OPENED"),
		StringName("REWARD_WINDOW_CANCELLED"),
	]
	assert_false(
		bool(script.call("is_legal_sequence", sn_kinds)),
		"kinds 元素为 StringName 必须拒绝"
	)

	# kinds 含数字
	var num_kinds: Array = [1, 2]
	assert_false(
		bool(script.call("is_legal_sequence", num_kinds)),
		"kinds 元素为数字必须拒绝"
	)
	var mixed_kinds: Array = ["REWARD_WINDOW_OPENED", 2]
	assert_false(
		bool(script.call("is_legal_sequence", mixed_kinds)),
		"kinds 混入数字必须拒绝"
	)

	# meta keys 必须 TYPE_STRING：StringName key 拒绝
	var meta_sn := {}
	meta_sn[StringName("settled_outcome")] = "FULL_GRANT"
	assert_false(
		bool(script.call("is_legal_sequence", [
			"ACTION_APPLIED", "REWARD_WINDOW_CLOSING", "CLAIM_WINDOW", "ACTION_APPLIED",
			"REWARD_WINDOW_SETTLED",
			"ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED", "ITEM_GRANTED",
		], meta_sn)),
		"meta key 为 StringName 必须拒绝"
	)

	# meta keys 为数字
	var meta_num := {0: "FULL_GRANT"}
	assert_false(
		bool(script.call("is_legal_sequence", legal_kinds, meta_num)),
		"meta key 为数字必须拒绝"
	)


# =============================================================================
# (5) ACCEPTED.server_seq >= 1；REJECTED 可为 0
# =============================================================================

func test_command_result_accepted_server_seq_ge_1_rejected_allows_zero() -> void:
	var CommandResultScript = load("res://protocol/command_result.gd")
	assert_not_null(CommandResultScript)

	# ACCEPTED：server_seq=0 必须拒绝
	assert_null(
		CommandResultScript.from_dict({
			"protocol_version": 1,
			"command_id": CMD,
			"status": "ACCEPTED",
			"server_seq": 0,
			"error_code": "",
		}),
		"ACCEPTED.server_seq 必须 >= 1"
	)

	# ACCEPTED：server_seq=1 合法
	assert_not_null(
		CommandResultScript.from_dict({
			"protocol_version": 1,
			"command_id": CMD,
			"status": "ACCEPTED",
			"server_seq": 1,
			"error_code": "",
		}),
		"ACCEPTED.server_seq=1 合法"
	)

	# REJECTED：server_seq=0 合法（当前已见值）
	assert_not_null(
		CommandResultScript.from_dict({
			"protocol_version": 1,
			"command_id": CMD,
			"status": "REJECTED",
			"server_seq": 0,
			"error_code": "COMMAND_REJECTED",
		}),
		"REJECTED.server_seq=0 合法"
	)

	# REJECTED：server_seq>=1 也可
	assert_not_null(
		CommandResultScript.from_dict({
			"protocol_version": 1,
			"command_id": CMD,
			"status": "REJECTED",
			"server_seq": 3,
			"error_code": "ILLEGAL_ACTION",
		}),
		"REJECTED.server_seq>0 合法"
	)


# =============================================================================
# (6) ProtocolConstants 为唯一协议常量源，对齐 Tile/Wall
# =============================================================================

func test_protocol_constants_is_sole_source_aligned_with_tile_wall() -> void:
	if not ResourceLoader.exists(CONSTANTS_PATH):
		assert_true(false, "必须存在 %s" % CONSTANTS_PATH)
		return
	var script: GDScript = load(CONSTANTS_PATH) as GDScript
	assert_not_null(script, "protocol_constants.gd 必须可加载")
	if script == null:
		return

	# class_name ProtocolConstants（全局可解析）
	assert_true(
		ClassDB.class_exists("ProtocolConstants")
		or script.get("class_name") != null
		or str(script.resource_path).ends_with("protocol_constants.gd"),
		"应暴露 class_name ProtocolConstants"
	)
	# 优先用全局 class_name；若尚未注册则用脚本常量
	var pv: int = int(script.get_script_constant_map().get("PROTOCOL_VERSION", -1))
	var max_safe: int = int(script.get_script_constant_map().get("MAX_SAFE_INT", -1))
	var tiles: int = int(script.get_script_constant_map().get("TILES_PER_HAND", -1))
	var max_hs: int = int(script.get_script_constant_map().get("MAX_HAND_SEQ", -1))

	assert_eq(pv, 1, "PROTOCOL_VERSION")
	assert_eq(max_safe, Tile.MAX_SAFE_INSTANCE_ID, "MAX_SAFE_INT 必须等于 Tile.MAX_SAFE_INSTANCE_ID")
	assert_eq(tiles, Tile.TILES_PER_HAND, "TILES_PER_HAND 必须等于 Tile.TILES_PER_HAND")
	assert_eq(max_hs, Wall.MAX_HAND_SEQ, "MAX_HAND_SEQ 必须等于 Wall.MAX_HAND_SEQ")

	# 其它协议脚本不得再重复字面量 9007199254740991 / 66229406284859 / 独立 PROTOCOL_VERSION
	var protocol_scripts: Array = [
		"res://protocol/action.gd",
		"res://protocol/command_result.gd",
		"res://protocol/networked_event.gd",
		"res://protocol/protocol_view_codec.gd",
		"res://protocol/json_transport_decoder.gd",
		"res://protocol/e5_event_order.gd",
		"res://protocol/protocol_uuid.gd",
	]
	for path in protocol_scripts:
		if path == CONSTANTS_PATH:
			continue
		assert_true(ResourceLoader.exists(path), "协议脚本存在: %s" % path)
		var src: String = FileAccess.get_file_as_string(path)
		assert_false(
			src.contains("9007199254740991"),
			"%s 不得重复 MAX_SAFE 字面量，应引用 ProtocolConstants" % path
		)
		assert_false(
			src.contains("66229406284859"),
			"%s 不得重复 MAX_HAND_SEQ 字面量，应引用 ProtocolConstants" % path
		)
		# 禁止本地 const PROTOCOL_VERSION := 1 重复权威源
		assert_false(
			src.contains("const PROTOCOL_VERSION"),
			"%s 不得重复定义 PROTOCOL_VERSION" % path
		)
		assert_false(
			src.contains("const MAX_SAFE_INT"),
			"%s 不得重复定义 MAX_SAFE_INT" % path
		)
		assert_false(
			src.contains("const MAX_HAND_SEQ"),
			"%s 不得重复定义 MAX_HAND_SEQ" % path
		)
		assert_false(
			src.contains("const TILES_PER_HAND"),
			"%s 不得重复定义 TILES_PER_HAND" % path
		)
		assert_false(
			src.contains("const _MAX_SAFE_INT"),
			"%s 不得以 _MAX_SAFE_INT 重复字面量常量" % path
		)


# =============================================================================
# (7) TURN_PROMPT allowed_actions 拒 ITEM_USE；Action 仍接受 ITEM_USE 命令
# =============================================================================

func test_turn_prompt_rejects_item_use_but_action_accepts_item_use_command() -> void:
	# Action 命令侧仍接受 ITEM_USE
	var item_cmd: Action = Action.from_dict(_action_wire("ITEM_USE", {
		"item_instance_id": "inst_abc",
	}))
	assert_not_null(item_cmd, "Action 必须继续接受 ITEM_USE 命令")
	if item_cmd != null:
		assert_eq(str(item_cmd.kind), "ITEM_USE")

	# TURN_PROMPT 的 allowed_actions 不得出现 ITEM_USE
	var turn_wire := _flat_event("TURN_PROMPT", 8, _turn_payload_with_item_use(1))
	assert_null(
		NetworkedEvent.from_dict(turn_wire),
		"TURN_PROMPT.allowed_actions 必须拒绝 ITEM_USE（仅命令，不入 offer）"
	)

	# 对照：无 ITEM_USE 的 TURN 仍合法
	var ok_payload := _turn_payload_with_item_use(1)
	var actions: Array = ok_payload["allowed_actions"]
	actions = actions.filter(func(o): return str((o as Dictionary).get("kind", "")) != "ITEM_USE")
	ok_payload["allowed_actions"] = actions
	assert_not_null(
		NetworkedEvent.from_dict(_flat_event("TURN_PROMPT", 8, ok_payload)),
		"TURN_PROMPT 无 ITEM_USE 应合法"
	)
