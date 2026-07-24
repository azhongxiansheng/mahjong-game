extends GutTest

# E2-02（#232）Red：Action v1 实体命令契约（冻结，无双协议兼容）。
# exact envelope：protocol_version / command_id / room_id / seat / hand_seq /
# decision_id / kind / payload / client_seq。
# 业务 kind 仅 DISCARD..DECLARE_ABORTIVE_DRAW；JOIN/READY/RESYNC_REQUEST 拒绝。

const CMD := "550e8400-e29b-41d4-a716-446655440000"
const DECISION := "550e8400-e29b-41d4-a716-4466554400aa"
const ROOM := "room_x"
const ACTION_SCRIPT := "res://protocol/action.gd"
# 冻结上限：hand_seq 对齐 Wall.MAX_HAND_SEQ；client_seq / instance_id / meld_id 对齐 JS safe int
const MAX_HAND_SEQ := 66229406284859
const MAX_SAFE_INT := 9007199254740991
const TILES_PER_HAND := 136

const BUSINESS_KINDS := [
	"DISCARD", "RIICHI", "CHI", "PON", "KAN", "RON", "TSUMO", "PASS",
	"ITEM_USE", "DECLARE_ABORTIVE_DRAW",
]
const ENVELOPE_KEYS := [
	"protocol_version", "command_id", "room_id", "seat", "hand_seq",
	"decision_id", "kind", "payload", "client_seq",
]
const SESSION_KINDS := ["JOIN", "READY", "RESYNC_REQUEST"]


func _base_wire(
	kind: String,
	payload: Dictionary = {},
	seat: int = 0,
	client_seq: int = 1,
	hand_seq: int = 0,
	decision_id: String = DECISION
) -> Dictionary:
	return {
		"protocol_version": 1,
		"command_id": CMD,
		"room_id": ROOM,
		"seat": seat,
		"hand_seq": hand_seq,
		"decision_id": decision_id,
		"kind": kind,
		"payload": payload.duplicate(true),
		"client_seq": client_seq,
	}


func _exact_keys(d: Dictionary, expected: Array) -> bool:
	if d.keys().size() != expected.size():
		return false
	for k in expected:
		if not d.has(k):
			return false
	return true


func _assert_wire_envelope(d: Dictionary, kind: String) -> void:
	assert_true(_exact_keys(d, ENVELOPE_KEYS), "envelope exact 九键")
	assert_eq(typeof(d.get("protocol_version")), TYPE_INT)
	assert_eq(int(d.get("protocol_version", -1)), 1)
	assert_eq(typeof(d.get("command_id")), TYPE_STRING)
	assert_eq(str(d.get("command_id")), CMD)
	assert_eq(typeof(d.get("room_id")), TYPE_STRING)
	assert_true(str(d.get("room_id", "")).length() > 0)
	assert_eq(typeof(d.get("seat")), TYPE_INT)
	assert_true(int(d["seat"]) >= 0 and int(d["seat"]) <= 3)
	assert_eq(typeof(d.get("hand_seq")), TYPE_INT)
	assert_true(int(d["hand_seq"]) >= 0 and int(d["hand_seq"]) <= MAX_HAND_SEQ)
	assert_eq(typeof(d.get("decision_id")), TYPE_STRING)
	assert_eq(str(d.get("decision_id")), DECISION)
	assert_eq(typeof(d.get("kind")), TYPE_STRING)
	assert_eq(str(d.get("kind")), kind)
	assert_eq(typeof(d.get("payload")), TYPE_DICTIONARY)
	assert_eq(typeof(d.get("client_seq")), TYPE_INT)
	assert_true(int(d["client_seq"]) >= 0 and int(d["client_seq"]) <= MAX_SAFE_INT)


func _ns(hand_seq: int, serial: int) -> int:
	return hand_seq * TILES_PER_HAND + serial


func _payload_for(kind: String, hand_seq: int = 0) -> Dictionary:
	match kind:
		"DISCARD", "RIICHI":
			return {"tile_instance_id": _ns(hand_seq, 42)}
		"CHI", "PON":
			return {"companion_tile_instance_ids": [_ns(hand_seq, 3), _ns(hand_seq, 7)]}
		"KAN":
			return {
				"kan_kind": "MINKAN",
				"companion_tile_instance_ids": [
					_ns(hand_seq, 1), _ns(hand_seq, 2), _ns(hand_seq, 3),
				],
			}
		"RON", "TSUMO", "PASS":
			return {}
		"ITEM_USE":
			return {"item_instance_id": "inst_abc"}
		"DECLARE_ABORTIVE_DRAW":
			return {"reason": "KYUUSYU_KYUUHAI"}
		_:
			return {}


# ---- 合法业务 kind ----

func test_v1_business_kinds_parse_with_entity_envelope() -> void:
	for kind in BUSINESS_KINDS:
		var a: Action = Action.from_dict(_base_wire(kind, _payload_for(kind, 3), 2, 7, 3))
		assert_not_null(a, "合法 kind %s 应解析成功" % kind)
		if a == null:
			continue
		var out: Dictionary = a.to_dict()
		_assert_wire_envelope(out, kind)
		assert_eq(a.seat, 2)
		assert_eq(a.client_seq, 7)
		assert_eq(a.hand_seq, 3)
		assert_eq(a.decision_id, DECISION)
		assert_eq(typeof(a.kind), TYPE_STRING)
		assert_eq(str(a.kind), kind)


func test_session_kinds_join_ready_resync_must_be_rejected() -> void:
	for kind in SESSION_KINDS:
		assert_null(
			Action.from_dict(_base_wire(kind, {})),
			"会话 kind %s 必须拒绝（非业务 Action）" % kind
		)


# ---- payload 字段精确契约 ----

func test_discard_payload_exact_tile_instance_id() -> void:
	var a: Action = Action.from_dict(_base_wire("DISCARD", {"tile_instance_id": 99}))
	assert_not_null(a)
	if a == null:
		return
	assert_true(_exact_keys(a.payload, ["tile_instance_id"]))
	assert_eq(typeof(a.payload["tile_instance_id"]), TYPE_INT)
	assert_eq(int(a.payload["tile_instance_id"]), 99)

	assert_null(Action.from_dict(_base_wire("DISCARD", {})), "缺 tile_instance_id")
	assert_null(Action.from_dict(_base_wire("DISCARD", {
		"tile_instance_id": 1, "is_red_dora": false,
	})), "旧 tile_id/is_red_dora 多字段拒绝")
	assert_null(Action.from_dict(_base_wire("DISCARD", {
		"tile_id": 4, "is_red_dora": false,
	})), "旧 DISCARD schema 拒绝")
	assert_null(Action.from_dict(_base_wire("DISCARD", {
		"tile_instance_id": -1,
	})), "负数 instance_id 拒绝")
	# 末局 136 命名空间上界用 _ns(MAX_HAND_SEQ,135)；MAX_SAFE 不保证落在该域
	assert_not_null(Action.from_dict(_base_wire("DISCARD", {
		"tile_instance_id": _ns(MAX_HAND_SEQ, 135),
	}, 0, 1, MAX_HAND_SEQ)), "tile_instance_id 末局命名空间上界合法")
	assert_null(Action.from_dict(_base_wire("DISCARD", {
		"tile_instance_id": MAX_SAFE_INT,
	})), "tile_instance_id=MAX_SAFE 不在 hand_seq=0 命名空间须拒")
	assert_null(Action.from_dict(_base_wire("DISCARD", {
		"tile_instance_id": MAX_SAFE_INT + 1,
	})), "tile_instance_id=MAX_SAFE+1 拒绝")
	assert_null(Action.from_dict(_base_wire("DISCARD", {
		"tile_instance_id": 1.0,
	})), "float 拒绝")
	assert_null(Action.from_dict(_base_wire("DISCARD", {
		"tile_instance_id": "1",
	})), "string 拒绝")
	assert_null(Action.from_dict(_base_wire("DISCARD", {
		"tile_instance_id": true,
	})), "bool 拒绝")


func test_riichi_payload_exact_tile_instance_id() -> void:
	var a: Action = Action.from_dict(_base_wire("RIICHI", {"tile_instance_id": 12}))
	assert_not_null(a, "RIICHI 仅实体 tile_instance_id")
	if a == null:
		return
	assert_true(_exact_keys(a.payload, ["tile_instance_id"]))
	assert_eq(int(a.payload["tile_instance_id"]), 12)

	assert_null(Action.from_dict(_base_wire("RIICHI", {
		"tile_id": TileId.W5, "is_red_dora": true,
	})), "旧 RIICHI tile_id schema 拒绝")
	assert_null(Action.from_dict(_base_wire("RIICHI", {
		"tile_instance_id": 12, "extra": 1,
	})), "RIICHI 多字段")


func test_chi_pon_companion_instance_ids_exact_sort_unique() -> void:
	for kind in ["CHI", "PON"]:
		var a: Action = Action.from_dict(_base_wire(kind, {
			"companion_tile_instance_ids": [9, 2],
		}))
		assert_not_null(a, "%s 合法 companion 两元素" % kind)
		if a == null:
			continue
		assert_true(_exact_keys(a.payload, ["companion_tile_instance_ids"]))
		var companions: Array = a.payload["companion_tile_instance_ids"]
		assert_eq(companions.size(), 2)
		assert_eq(typeof(companions[0]), TYPE_INT)
		assert_eq(typeof(companions[1]), TYPE_INT)
		assert_eq(int(companions[0]), 2, "%s 解析后升序规范化" % kind)
		assert_eq(int(companions[1]), 9)

		assert_null(Action.from_dict(_base_wire(kind, {
			"discarder_seat": 0,
			"companion_tile_instance_ids": [2, 9],
		})), "%s 旧 discarder 字段拒绝" % kind)
		assert_null(Action.from_dict(_base_wire(kind, {
			"companion_tile_instance_ids": [2],
		})), "%s companion 必须长度 2" % kind)
		assert_null(Action.from_dict(_base_wire(kind, {
			"companion_tile_instance_ids": [2, 2],
		})), "%s companion 不得重复" % kind)
		assert_null(Action.from_dict(_base_wire(kind, {
			"companion_tile_instance_ids": [2, -1],
		})), "%s companion 负数拒绝" % kind)
		# 同命名空间内两合法 id；跨域 MAX_SAFE 与 1 同框须拒
		assert_not_null(Action.from_dict(_base_wire(kind, {
			"companion_tile_instance_ids": [
				_ns(MAX_HAND_SEQ, 133), _ns(MAX_HAND_SEQ, 135),
			],
		}, 0, 1, MAX_HAND_SEQ)), "%s companion 末局命名空间合法" % kind)
		assert_null(Action.from_dict(_base_wire(kind, {
			"companion_tile_instance_ids": [1, MAX_SAFE_INT],
		})), "%s companion 跨 hand_seq 命名空间拒绝" % kind)
		assert_null(Action.from_dict(_base_wire(kind, {
			"companion_tile_instance_ids": [1, MAX_SAFE_INT + 1],
		})), "%s companion=MAX_SAFE+1 拒绝" % kind)
		assert_null(Action.from_dict(_base_wire(kind, {
			"companion_tile_instance_ids": [2, 1.5],
		})), "%s companion float 拒绝" % kind)
		assert_null(Action.from_dict(_base_wire(kind, {
			"companion_tile_instance_ids": [2, "9"],
		})), "%s companion string 拒绝" % kind)


func test_kan_three_kinds_entity_payload_exact() -> void:
	var minkan: Action = Action.from_dict(_base_wire("KAN", {
		"kan_kind": "MINKAN",
		"companion_tile_instance_ids": [5, 1, 3],
	}))
	assert_not_null(minkan, "MINKAN 合法")
	if minkan != null:
		assert_true(_exact_keys(minkan.payload, ["kan_kind", "companion_tile_instance_ids"]))
		assert_eq(str(minkan.payload["kan_kind"]), "MINKAN")
		var mc: Array = minkan.payload["companion_tile_instance_ids"]
		assert_eq(mc.size(), 3)
		assert_eq(int(mc[0]), 1)
		assert_eq(int(mc[1]), 3)
		assert_eq(int(mc[2]), 5)

	assert_null(Action.from_dict(_base_wire("KAN", {
		"kan_kind": "MINKAN",
		"companion_tile_instance_ids": [1, 2],
	})), "MINKAN companion 必须长度 3")
	assert_null(Action.from_dict(_base_wire("KAN", {
		"kan_kind": "MINKAN",
		"companion_tile_instance_ids": [1, 1, 2],
	})), "MINKAN companion 不得重复")
	assert_null(Action.from_dict(_base_wire("KAN", {
		"kan_kind": "MINKAN",
		"tile_id": 4,
		"discarder_seat": 1,
	})), "旧 MINKAN tile_id schema 拒绝")

	var ankan: Action = Action.from_dict(_base_wire("KAN", {
		"kan_kind": "ANKAN",
		"tile_instance_ids": [8, 4, 6, 2],
	}))
	assert_not_null(ankan, "ANKAN 合法")
	if ankan != null:
		assert_true(_exact_keys(ankan.payload, ["kan_kind", "tile_instance_ids"]))
		var ids: Array = ankan.payload["tile_instance_ids"]
		assert_eq(ids.size(), 4)
		assert_eq(int(ids[0]), 2)
		assert_eq(int(ids[1]), 4)
		assert_eq(int(ids[2]), 6)
		assert_eq(int(ids[3]), 8)

	assert_null(Action.from_dict(_base_wire("KAN", {
		"kan_kind": "ANKAN",
		"tile_instance_ids": [1, 2, 3],
	})), "ANKAN 必须长度 4")
	assert_null(Action.from_dict(_base_wire("KAN", {
		"kan_kind": "ANKAN",
		"tile_instance_ids": [1, 2, 3, 1],
	})), "ANKAN 不得重复")
	assert_null(Action.from_dict(_base_wire("KAN", {
		"kan_kind": "ANKAN",
		"tile_id": 4,
	})), "旧 ANKAN tile_id schema 拒绝")

	var added: Action = Action.from_dict(_base_wire("KAN", {
		"kan_kind": "ADDED_KAN",
		"meld_id": 2,
		"added_tile_instance_id": 77,
	}))
	assert_not_null(added, "ADDED_KAN 合法")
	if added != null:
		assert_true(_exact_keys(added.payload, [
			"kan_kind", "meld_id", "added_tile_instance_id",
		]))
		assert_eq(int(added.payload["meld_id"]), 2)
		assert_eq(int(added.payload["added_tile_instance_id"]), 77)

	assert_null(Action.from_dict(_base_wire("KAN", {
		"kan_kind": "ADDED_KAN",
		"meld_id": -1,
		"added_tile_instance_id": 77,
	})), "ADDED_KAN meld_id 负数拒绝")
	# meld_id 不受 136 命名空间限制；added 须在 hand_seq 域
	assert_not_null(Action.from_dict(_base_wire("KAN", {
		"kan_kind": "ADDED_KAN",
		"meld_id": MAX_SAFE_INT,
		"added_tile_instance_id": _ns(MAX_HAND_SEQ, 135),
	}, 0, 1, MAX_HAND_SEQ)), "ADDED_KAN meld_id=MAX_SAFE 且 added 末局上界合法")
	assert_null(Action.from_dict(_base_wire("KAN", {
		"kan_kind": "ADDED_KAN",
		"meld_id": MAX_SAFE_INT,
		"added_tile_instance_id": MAX_SAFE_INT,
	})), "ADDED_KAN added=MAX_SAFE 不在 hand_seq=0 域须拒")
	assert_null(Action.from_dict(_base_wire("KAN", {
		"kan_kind": "ADDED_KAN",
		"meld_id": MAX_SAFE_INT + 1,
		"added_tile_instance_id": 77,
	})), "ADDED_KAN meld_id=MAX_SAFE+1 拒绝")
	assert_null(Action.from_dict(_base_wire("KAN", {
		"kan_kind": "ADDED_KAN",
		"meld_id": 2,
		"added_tile_instance_id": MAX_SAFE_INT + 1,
	})), "ADDED_KAN added=MAX_SAFE+1 拒绝")
	assert_null(Action.from_dict(_base_wire("KAN", {
		"kan_kind": "ADDED_KAN",
		"meld_id": 2,
		"added_tile_instance_id": 1.0,
	})), "ADDED_KAN added float 拒绝")
	assert_null(Action.from_dict(_base_wire("KAN", {
		"kan_kind": "ADDED_KAN",
		"tile_id": 4,
	})), "旧 ADDED_KAN schema 拒绝")
	assert_null(Action.from_dict(_base_wire("KAN", {
		"kan_kind": "FOO",
		"companion_tile_instance_ids": [1, 2, 3],
	})), "未知 kan_kind")
	assert_null(Action.from_dict(_base_wire("KAN", {
		"kan_kind": "MINKAN",
		"companion_tile_instance_ids": [1, 2, 3],
		"extra": 1,
	})), "KAN 多字段")


func test_ron_tsumo_pass_payload_exactly_empty() -> void:
	for kind in ["RON", "TSUMO", "PASS"]:
		var a: Action = Action.from_dict(_base_wire(kind, {}))
		assert_not_null(a, "%s 空 payload 合法" % kind)
		if a != null:
			assert_eq(a.payload.keys().size(), 0)
			assert_eq((a.to_dict()["payload"] as Dictionary).keys().size(), 0)
		assert_null(Action.from_dict(_base_wire(kind, {"x": 1})), "%s 多字段拒绝" % kind)
		assert_null(Action.from_dict(_base_wire(kind, {
			"discarder_seat": 1, "tile_id": 5,
		})), "%s 旧 schema 拒绝" % kind)


func test_item_use_payload_only_nonempty_item_instance_id() -> void:
	var ok: Action = Action.from_dict(_base_wire("ITEM_USE", {"item_instance_id": "inst_abc"}))
	assert_not_null(ok)
	if ok != null:
		assert_true(_exact_keys(ok.payload, ["item_instance_id"]))
		assert_eq(str(ok.payload.get("item_instance_id")), "inst_abc")

	assert_null(Action.from_dict(_base_wire("ITEM_USE", {})), "缺 item_instance_id")
	assert_null(Action.from_dict(_base_wire("ITEM_USE", {"item_instance_id": ""})), "空串")
	assert_null(Action.from_dict(_base_wire("ITEM_USE", {
		"item_instance_id": "   ",
	})), "纯空白 item_instance_id")
	assert_null(Action.from_dict(_base_wire("ITEM_USE", {
		"item_instance_id": " inst_abc",
	})), "item_instance_id 前导空白")
	assert_null(Action.from_dict(_base_wire("ITEM_USE", {
		"item_instance_id": "inst_abc ",
	})), "item_instance_id 尾随空白")
	assert_null(Action.from_dict(_base_wire("ITEM_USE", {
		"item_instance_id": "inst_abc", "item_id": "extra",
	})), "多余字段")
	assert_null(Action.from_dict(_base_wire("ITEM_USE", {"item_instance_id": 123})), "错类型")


func test_declare_abortive_draw_kyuusyu_kyuuhai() -> void:
	var a: Action = Action.from_dict(_base_wire("DECLARE_ABORTIVE_DRAW", {
		"reason": "KYUUSYU_KYUUHAI",
	}))
	assert_not_null(a)
	if a == null:
		return
	assert_true(_exact_keys(a.payload, ["reason"]))
	assert_eq(str(a.payload["reason"]), "KYUUSYU_KYUUHAI")

	assert_null(Action.from_dict(_base_wire("DECLARE_ABORTIVE_DRAW", {})), "缺 reason")
	assert_null(Action.from_dict(_base_wire("DECLARE_ABORTIVE_DRAW", {
		"reason": "SUUFON_RENDA",
	})), "Alpha 仅冻结 KYUUSYU_KYUUHAI")
	assert_null(Action.from_dict(_base_wire("DECLARE_ABORTIVE_DRAW", {
		"reason": "KYUUSYU_KYUUHAI", "extra": 1,
	})), "多字段")


# ---- 拒绝面：旧 kind / 缺字段 / 静默强转 / UUID ----

func test_rejects_old_int_kind_draw_pass_claim_and_unknown() -> void:
	var with_env := _base_wire("DISCARD", {"tile_instance_id": 1})
	with_env["kind"] = 2
	assert_null(Action.from_dict(with_env), "拒绝 int kind")

	assert_null(Action.from_dict(_base_wire("DRAW", {})), "client 不得发 DRAW")
	assert_null(Action.from_dict(_base_wire("PASS_CLAIM", {})), "PASS_CLAIM 已废除")
	assert_null(Action.from_dict(_base_wire("UNKNOWN_KIND", {})), "未知 kind")


func test_rejects_missing_or_extra_envelope_fields() -> void:
	var full := _base_wire("PASS", {})
	for key in ENVELOPE_KEYS:
		var bad := full.duplicate(true)
		bad.erase(key)
		assert_null(Action.from_dict(bad), "缺 %s 应拒绝" % key)

	var extra := full.duplicate(true)
	extra["state_hash"] = "x"
	assert_null(Action.from_dict(extra), "envelope 多余键拒绝")

	assert_null(Action.from_dict({}), "空 dict")
	var empty_cmd := full.duplicate(true)
	empty_cmd["command_id"] = ""
	assert_null(Action.from_dict(empty_cmd), "空 command_id")
	var empty_room := full.duplicate(true)
	empty_room["room_id"] = ""
	assert_null(Action.from_dict(empty_room), "空 room_id")
	for bad_room_id in ["   ", " room_x", "room_x "]:
		var noncanonical_room := full.duplicate(true)
		noncanonical_room["room_id"] = bad_room_id
		assert_null(
			Action.from_dict(noncanonical_room),
			"room_id 必须非空且已去除首尾空白: %s" % JSON.stringify(bad_room_id)
		)


func test_rejects_invalid_uuid_command_and_decision_id() -> void:
	var full := _base_wire("PASS", {})
	# 形状非法 + version/variant 负例；大写单独覆盖
	for bad_id in [
		"not-a-uuid",
		"550e8400e29b41d4a716446655440000", # 无连字符
		"550e8400-e29b-41d4-a716", # 过短
		"gggggggg-e29b-41d4-a716-446655440000", # 非 hex
		"550e8400-e29b-41d4-a716-4466554400000", # 37 字符
		"550e8400-e29b-41d4-a716-44665544000", # 35 字符
		"550e8400-e29b-41d4-a716-44665544000g", # 尾非 hex
		"{550e8400-e29b-41d4-a716-446655440000}", # 花括号
		"550e8400-e29b-41d4-a716-446655440000 ", # 尾空白
		"550e8400-e29b-11d4-a716-446655440000", # version≠4（1xxx）
		"550e8400-e29b-41d4-7716-446655440000", # variant 非 RFC（7xxx）
		"550e8400-e29b-41d4-c716-446655440000", # variant 非 RFC（cxxx）
	]:
		var bad_cmd := full.duplicate(true)
		bad_cmd["command_id"] = bad_id
		assert_null(Action.from_dict(bad_cmd), "非法 command_id UUID: %s" % bad_id)
		var bad_dec := full.duplicate(true)
		bad_dec["decision_id"] = bad_id
		assert_null(Action.from_dict(bad_dec), "非法 decision_id UUID: %s" % bad_id)

	# 正例：canonical lowercase v4+variant 合法
	assert_not_null(Action.from_dict(full), "lowercase command_id/decision_id 合法")
	var ok: Action = Action.from_dict(full)
	if ok != null:
		assert_eq(str(ok.command_id), CMD)
		assert_eq(str(ok.decision_id), DECISION)
		assert_eq(str(ok.command_id), str(ok.command_id).to_lower())
		assert_eq(str(ok.decision_id), str(ok.decision_id).to_lower())


func test_uuid_uppercase_command_and_decision_id_rejected() -> void:
	# canonical lowercase only：同一 UUID 大小写不得绕过幂等键
	var upper_cmd := "550E8400-E29B-41D4-A716-446655440000"
	var upper_dec := "550E8400-E29B-41D4-A716-4466554400AA"
	var mixed := "550e8400-E29b-41d4-a716-446655440000"

	var wire_cmd := _base_wire("PASS", {})
	wire_cmd["command_id"] = upper_cmd
	assert_null(Action.from_dict(wire_cmd), "大写 command_id 必须拒绝")

	var wire_dec := _base_wire("PASS", {})
	wire_dec["decision_id"] = upper_dec
	assert_null(Action.from_dict(wire_dec), "大写 decision_id 必须拒绝")

	var wire_both := _base_wire("PASS", {})
	wire_both["command_id"] = upper_cmd
	wire_both["decision_id"] = upper_dec
	assert_null(Action.from_dict(wire_both), "command_id+decision_id 均大写必须拒绝")

	var wire_mixed := _base_wire("PASS", {})
	wire_mixed["command_id"] = mixed
	assert_null(Action.from_dict(wire_mixed), "混大小写 command_id 必须拒绝")

	# version / variant 负例（command_id 与 decision_id 对称）
	var non_v4 := _base_wire("PASS", {})
	non_v4["command_id"] = "550e8400-e29b-11d4-a716-446655440000"
	assert_null(Action.from_dict(non_v4), "command_id version≠4 拒绝")
	non_v4 = _base_wire("PASS", {})
	non_v4["decision_id"] = "550e8400-e29b-11d4-a716-4466554400aa"
	assert_null(Action.from_dict(non_v4), "decision_id version≠4 拒绝")

	var bad_var := _base_wire("PASS", {})
	bad_var["command_id"] = "550e8400-e29b-41d4-7716-446655440000"
	assert_null(Action.from_dict(bad_var), "command_id variant 7xxx 拒绝")
	bad_var = _base_wire("PASS", {})
	bad_var["decision_id"] = "550e8400-e29b-41d4-c716-4466554400aa"
	assert_null(Action.from_dict(bad_var), "decision_id variant cxxx 拒绝")

	# 正例对照：合法 lowercase v4+variant 仍通过
	assert_not_null(Action.from_dict(_base_wire("PASS", {})), "lowercase UUID 正例")


func test_rejects_invalid_ranges_and_silent_coercion() -> void:
	assert_null(Action.from_dict(_base_wire("PASS", {}, -1)), "seat < 0")
	assert_null(Action.from_dict(_base_wire("PASS", {}, 4)), "seat > 3")
	assert_null(Action.from_dict(_base_wire("PASS", {}, 0, -1)), "client_seq 负")
	assert_null(Action.from_dict(_base_wire("PASS", {}, 0, 1, -1)), "hand_seq 负")

	# hand_seq exact int 0..MAX_HAND_SEQ
	assert_not_null(Action.from_dict(_base_wire("PASS", {}, 0, 1, 0)), "hand_seq=0 合法")
	assert_not_null(
		Action.from_dict(_base_wire("PASS", {}, 0, 1, MAX_HAND_SEQ)),
		"hand_seq=MAX_HAND_SEQ 合法"
	)
	assert_null(
		Action.from_dict(_base_wire("PASS", {}, 0, 1, MAX_HAND_SEQ + 1)),
		"hand_seq=MAX_HAND_SEQ+1 拒绝"
	)

	# client_seq exact int 0..MAX_SAFE_INT
	assert_not_null(Action.from_dict(_base_wire("PASS", {}, 0, 0, 0)), "client_seq=0 合法")
	assert_not_null(
		Action.from_dict(_base_wire("PASS", {}, 0, MAX_SAFE_INT, 0)),
		"client_seq=MAX_SAFE 合法"
	)
	assert_null(
		Action.from_dict(_base_wire("PASS", {}, 0, MAX_SAFE_INT + 1, 0)),
		"client_seq=MAX_SAFE+1 拒绝"
	)

	var bad_pv := _base_wire("PASS", {})
	bad_pv["protocol_version"] = "1"
	assert_null(Action.from_dict(bad_pv), "protocol_version 不得 str 静默强转")

	var bad_seat := _base_wire("PASS", {})
	bad_seat["seat"] = "0"
	assert_null(Action.from_dict(bad_seat), "seat 不得 str 静默强转")

	var bad_hand := _base_wire("PASS", {})
	bad_hand["hand_seq"] = 1.5
	assert_null(Action.from_dict(bad_hand), "hand_seq float 拒绝")

	var bad_hand_str := _base_wire("PASS", {})
	bad_hand_str["hand_seq"] = "0"
	assert_null(Action.from_dict(bad_hand_str), "hand_seq 不得 str 强转")

	var bad_seq := _base_wire("PASS", {})
	bad_seq["client_seq"] = "1"
	assert_null(Action.from_dict(bad_seq), "client_seq 不得 str 静默强转")

	var bad_kind := _base_wire("PASS", {})
	bad_kind["kind"] = &"PASS"
	assert_null(Action.from_dict(bad_kind), "kind 必须是 String 而非 StringName")

	var bad_decision := _base_wire("PASS", {})
	bad_decision["decision_id"] = 42
	assert_null(Action.from_dict(bad_decision), "decision_id 不得 int 强转")


func test_to_dict_emits_entity_v1_wire() -> void:
	var a: Action = Action.from_dict(_base_wire("DISCARD", {
		"tile_instance_id": _ns(2, 5),
	}, 0, 3, 2))
	assert_not_null(a, "DISCARD from_dict 必须支持实体 v1")
	if a == null:
		return
	var d: Dictionary = a.to_dict()
	_assert_wire_envelope(d, "DISCARD")
	assert_eq(int(d["hand_seq"]), 2)
	assert_eq(int((d["payload"] as Dictionary)["tile_instance_id"]), _ns(2, 5))
	assert_false((d["payload"] as Dictionary).has("tile_id"), "不得回落旧 tile_id")


func test_payload_and_envelope_deep_copy() -> void:
	var src := {"tile_instance_id": _ns(5, 42)}
	var wire := _base_wire("DISCARD", src, 0, 1, 5)
	var a: Action = Action.from_dict(wire)
	assert_not_null(a)
	if a == null:
		return
	src["tile_instance_id"] = 999
	wire["hand_seq"] = 99
	assert_eq(int(a.payload["tile_instance_id"]), _ns(5, 42), "from_dict 后改输入不得污染")
	assert_eq(int(a.hand_seq), 5)

	var d: Dictionary = a.to_dict()
	(d["payload"] as Dictionary)["tile_instance_id"] = 111
	d["hand_seq"] = 0
	assert_eq(int(a.payload["tile_instance_id"]), _ns(5, 42), "to_dict 复制防别名")
	assert_eq(int(a.hand_seq), 5)

	var exposed: Dictionary = a.payload
	exposed["tile_instance_id"] = 222
	assert_eq(int(a.payload["tile_instance_id"]), _ns(5, 42), "getter deep copy")

	var chi: Action = Action.from_dict(_base_wire("CHI", {
		"companion_tile_instance_ids": [4, 2],
	}))
	assert_not_null(chi)
	if chi == null:
		return
	var chi_exposed: Dictionary = chi.payload
	var companions: Array = chi_exposed["companion_tile_instance_ids"]
	companions[0] = 999
	assert_eq(int(chi.payload["companion_tile_instance_ids"][0]), 2,
		"嵌套数组 deep copy")
	assert_eq(int((chi.to_dict()["payload"] as Dictionary)["companion_tile_instance_ids"][0]), 2)


func test_action_script_path_still_expected() -> void:
	assert_true(ResourceLoader.exists(ACTION_SCRIPT), "生产 Action 路径 %s" % ACTION_SCRIPT)


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


func test_action_envelope_fields_reject_mutation() -> void:
	# 只读：反射冻结 @字段_getter 存在且 @字段_setter 不存在（Godot 4.6 命名）
	# 禁止 Object.set / 直接赋值攻击（生产缺 setter 时会 runtime error）
	var a: Action = Action.from_dict(_base_wire("DISCARD", {
		"tile_instance_id": _ns(3, 42),
	}, 1, 5, 3))
	assert_not_null(a, "合法 DISCARD 应解析")
	if a == null:
		return
	var before: Dictionary = a.to_dict().duplicate(true)

	var script: GDScript = load(ACTION_SCRIPT) as GDScript
	assert_not_null(script, "Action 脚本必须可加载")
	var method_names: Dictionary = {}
	for m in script.get_script_method_list():
		method_names[str(m.get("name", ""))] = true

	var fields: Array = [
		"protocol_version", "command_id", "room_id", "seat", "hand_seq",
		"decision_id", "kind", "client_seq", "payload",
	]
	for field in fields:
		var gname: String = "@%s_getter" % field
		var sname: String = "@%s_setter" % field
		assert_true(method_names.has(gname), "必须存在只读 getter %s" % gname)
		assert_false(method_names.has(sname), "不得存在 setter %s" % sname)

	var after: Dictionary = a.to_dict()
	assert_eq(int(after["protocol_version"]), int(before["protocol_version"]))
	assert_eq(str(after["command_id"]), str(before["command_id"]))
	assert_eq(str(after["room_id"]), str(before["room_id"]))
	assert_eq(int(after["seat"]), int(before["seat"]))
	assert_eq(int(after["hand_seq"]), int(before["hand_seq"]))
	assert_eq(str(after["decision_id"]), str(before["decision_id"]))
	assert_eq(str(after["kind"]), str(before["kind"]))
	assert_eq(int(after["client_seq"]), int(before["client_seq"]))
	assert_eq(int((after["payload"] as Dictionary)["tile_instance_id"]), _ns(3, 42),
		"to_dict payload 保持原值")

	var exposed: Dictionary = a.payload
	exposed["tile_instance_id"] = 777
	assert_eq(int(a.payload["tile_instance_id"]), _ns(3, 42), "payload getter deep-copy 未变")


func test_action_from_dict_arg_is_variant() -> void:
	# Godot 反射：Variant 参数 type == TYPE_NIL
	var arg_type: int = _from_dict_first_arg_type(ACTION_SCRIPT)
	assert_eq(
		arg_type, TYPE_NIL,
		"Action.from_dict 公开参数必须是 Variant（反射 type=TYPE_NIL）；当前=%d" % arg_type
	)


func test_action_from_dict_rejects_non_dictionary_matrix() -> void:
	# 仅在签名已是 Variant 后动态调用，避免 typed Dictionary 触发不可控中断
	var arg_type: int = _from_dict_first_arg_type(ACTION_SCRIPT)
	assert_eq(
		arg_type, TYPE_NIL,
		"签名未切到 Variant 前不动态调用非 Dictionary（Red：先修签名）"
	)
	if arg_type != TYPE_NIL:
		return
	var script: GDScript = load(ACTION_SCRIPT) as GDScript
	assert_not_null(script)
	var samples: Array = [null, false, true, 0, 1.0, [], "not_dict", RefCounted.new()]
	for sample in samples:
		var ret: Variant = script.call("from_dict", sample)
		assert_null(ret, "非 Dictionary 必须返回 null 且不抛: typeof=%d" % typeof(sample))
