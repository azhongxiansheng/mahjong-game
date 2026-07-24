extends GutTest
## E2-02 DecisionContext / DecisionWindow 冻结行为契约（紧凑版）。
## Action 九键 envelope 与 protocol/action.gd 同源；register_intent 只接 Action。
## 生产缺严格校验时 Red 为预期；须可收集，不得无关 parse/runtime 连锁。
const _CONTEXT_SCRIPT := "res://battle/decision_context.gd"
const _WINDOW_SCRIPT := "res://battle/decision_window.gd"
const _ENVELOPE_KEYS := [
	"protocol_version", "command_id", "room_id", "seat", "hand_seq",
	"decision_id", "kind", "payload", "client_seq",
]
const _WINDOW_PUBLIC_KEYS := [
	"kind", "hand_seq", "decision_id", "subject_seat",
	"subject_tile_instance_id", "discarder_seat", "seats", "responded_seats",
]
const _CONTEXT_PUBLIC_KEYS := [
	"window_kind", "hand_seq", "decision_id", "seat",
	"claimed_tile_instance_id", "discarder_seat", "allowed_actions", "allowed_kinds",
]
const _CONTEXT_SCALARS := [
	"window_kind", "hand_seq", "decision_id", "seat",
	"claimed_tile_instance_id", "discarder_seat",
]
const _WINDOW_SCALARS := [
	"kind", "hand_seq", "decision_id", "subject_seat",
	"subject_tile_instance_id", "discarder_seat",
]
## 合法 lowercase UUID v4 + RFC variant（第 13=4，第 17∈8|9|a|b）
const _UUID := "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
const _UUID2 := "11111111-2222-4333-8444-555555555555"
const _UUID3 := "66666666-7777-4888-8999-aaaaaaaaaaaa"
const _CMD := "cccccccc-dddd-4eee-8fff-000000000001"

const TILES_PER_HAND := 136
func _ns(hs: int, serial: int) -> int:
	return hs * TILES_PER_HAND + serial
func _serial_max() -> int:
	return TILES_PER_HAND - 1
func _wire(kind: String, seat: int, hs: int, did: String, payload: Dictionary,
		client_seq: int = 1) -> Dictionary:
	return {
		"protocol_version": 1, "command_id": _CMD, "room_id": "local",
		"seat": seat, "hand_seq": hs, "decision_id": did,
		"kind": kind, "payload": payload.duplicate(true), "client_seq": client_seq,
	}
func _act(kind: String, seat: int, hs: int, did: String, payload: Dictionary,
		client_seq: int = 1) -> Action:
	return Action.from_dict(_wire(kind, seat, hs, did, payload, client_seq))
func _opt(kind: String, payload: Dictionary) -> Dictionary:
	return {"kind": kind, "payload_options": [payload.duplicate(true)]}
func _turn_actions(hs: int = 1) -> Array:
	return [
		_opt("DISCARD", {"tile_instance_id": _ns(hs, 10)}),
		_opt("RIICHI", {"tile_instance_id": _ns(hs, 11)}),
		{"kind": "KAN", "payload_options": [
			{"kan_kind": "ANKAN", "tile_instance_ids": [_ns(hs, 1), _ns(hs, 2), _ns(hs, 3), _ns(hs, 4)]},
			{"kan_kind": "ADDED_KAN", "meld_id": 7, "added_tile_instance_id": _ns(hs, 5)},
		]},
		_opt("TSUMO", {}),
		_opt("DECLARE_ABORTIVE_DRAW", {"reason": "KYUUSYU_KYUUHAI"}),
	]
func _claim_actions(hs: int = 1) -> Array:
	return [
		_opt("CHI", {"companion_tile_instance_ids": [_ns(hs, 20), _ns(hs, 21)]}),
		_opt("PON", {"companion_tile_instance_ids": [_ns(hs, 30), _ns(hs, 31)]}),
		_opt("KAN", {"kan_kind": "MINKAN", "companion_tile_instance_ids": [_ns(hs, 40), _ns(hs, 41), _ns(hs, 42)]}),
		_opt("RON", {}), _opt("PASS", {}),
	]
func _rob_actions() -> Array:
	return [_opt("RON", {}), _opt("PASS", {})]
func _null(v: Variant, label: String) -> void:
	assert_eq(v, null, "应拒绝: %s" % label)
func _envelope(action: Action) -> void:
	assert_not_null(action, "envelope 需要 Action")
	if action == null:
		return
	var env: Dictionary = action.to_dict()
	var keys := env.keys()
	keys.sort()
	var expected := _ENVELOPE_KEYS.duplicate()
	expected.sort()
	assert_eq(keys, expected, "Action envelope exact 九键")
	assert_eq(env["protocol_version"], 1)
	assert_eq(env["room_id"], "local")
func _offer_exact(offer: Variant, label: String) -> void:
	assert_true(offer is Dictionary, "%s offer Dictionary" % label)
	if not (offer is Dictionary):
		return
	var d: Dictionary = offer
	assert_eq(d.keys().size(), 2, "%s offer exact 两键" % label)
	assert_true(d.has("kind") and d.has("payload_options"), "%s 须 kind/payload_options" % label)
	assert_true(d["kind"] is String and d["payload_options"] is Array,
		"%s kind String / options Array" % label)
	assert_gt((d["payload_options"] as Array).size(), 0, "%s options 非空" % label)
	for opt in d["payload_options"]:
		assert_true(opt is Dictionary, "%s option Dictionary" % label)
func _kinds_eq(ctx: DecisionContext, expected: Array) -> void:
	var got: Array = ctx.allowed_kinds.duplicate()
	got.sort()
	var want := expected.duplicate()
	want.sort()
	assert_eq(got, want, "allowed_kinds")
## Godot 4.6：只读标量有 @field_getter、无 @field_setter；不用 Object.set / property-list。
func _readonly(obj: Object, fields: Array, label: String) -> void:
	var script: GDScript = obj.get_script() as GDScript
	assert_not_null(script, "%s 应有脚本" % label)
	var methods: Dictionary = {}
	for m in script.get_script_method_list():
		methods[str(m.get("name", ""))] = true
	for field in fields:
		assert_true(methods.has("@%s_getter" % field),
			"%s.%s 应有 @%s_getter" % [label, field, field])
		assert_false(methods.has("@%s_setter" % field),
			"%s.%s 不得有 @%s_setter" % [label, field, field])
		var before: Variant = obj.get(field)
		assert_eq(obj.get(field), before, "%s.%s 再读不变" % [label, field])
## 返回 method 第 arg_index 参的 PropertyInfo Dictionary（含 type / class_name）；找不到则空 dict。
func _arg_type(path: String, method_name: String, arg_index: int) -> Dictionary:
	var script: GDScript = load(path) as GDScript
	assert_not_null(script, "加载 %s" % path)
	if script == null:
		return {}
	for m in script.get_script_method_list():
		if str(m.get("name", "")) != method_name:
			continue
		var args: Array = m.get("args", [])
		if arg_index < 0 or arg_index >= args.size():
			return {}
		return (args[arg_index] as Dictionary).duplicate(true)
	return {}
func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys
func _sorted_list(arr: Array) -> Array:
	var out := arr.duplicate()
	out.sort()
	return out

# ── 1) kind 白名单 / PASS / 跨 kind / ITEM_USE ────────────────────────────

func test_legal_kinds_pass_and_cross_kind_rejects() -> void:
	var legal := [
		{"kind": "TURN", "seat": 0, "cl": -1, "di": -1, "actions": _turn_actions(),
			"kinds": ["DISCARD", "RIICHI", "KAN", "TSUMO", "DECLARE_ABORTIVE_DRAW"],
			"need_pass": false},
		{"kind": "CLAIM", "seat": 1, "cl": _ns(1, 100), "di": 0, "actions": _claim_actions(),
			"kinds": ["CHI", "PON", "KAN", "RON", "PASS"], "need_pass": true},
		{"kind": "ROB_KAN", "seat": 2, "cl": _ns(1, 100), "di": 0, "actions": _rob_actions(),
			"kinds": ["RON", "PASS"], "need_pass": true},
	]
	for c in legal:
		var ctx: DecisionContext = DecisionContext.make(
			c["kind"], 1, _UUID, c["seat"], c["actions"], c["cl"], c["di"])
		assert_not_null(ctx, "合法 %s Context" % c["kind"])
		if ctx == null:
			continue
		assert_eq(ctx.window_kind, c["kind"])
		assert_eq(ctx.hand_seq, 1)
		assert_eq(ctx.decision_id, _UUID)
		assert_eq(ctx.seat, c["seat"])
		assert_eq(ctx.claimed_tile_instance_id, c["cl"])
		assert_eq(ctx.discarder_seat, c["di"])
		_kinds_eq(ctx, c["kinds"])
		var seen: Dictionary = {}
		var has_pass := false
		for offer in ctx.allowed_actions:
			_offer_exact(offer, c["kind"])
			var k: String = str((offer as Dictionary).get("kind", ""))
			assert_false(seen.has(k), "%s kind 唯一 %s" % [c["kind"], k])
			seen[k] = true
			if k == "PASS":
				has_pass = true
		if c["need_pass"]:
			assert_true(has_pass, "%s 必含 PASS" % c["kind"])
	for kind in ["TURN", "CLAIM", "ROB_KAN"]:
		var tile := -1 if kind == "TURN" else _ns(1, 10)
		var disc := -1 if kind == "TURN" else 0
		assert_not_null(DecisionWindow.make(kind, 1, _UUID, 0, tile, disc),
			"合法 Window %s" % kind)
	_null(DecisionWindow.make("ITEM_USE", 1, _UUID, 0, 5, 0), "Window 未知 kind")
	_null(DecisionContext.make("FOO", 1, _UUID, 0, _turn_actions()), "Context 未知 kind")
	var rejects := [
		{"l": "TURN 禁止 ITEM_USE", "k": "TURN", "s": 0, "cl": -1, "di": -1, "a": [
			_opt("DISCARD", {"tile_instance_id": 10}),
			_opt("ITEM_USE", {"item_instance_id": "inst_1"}),
		]},
		{"l": "CLAIM 缺 PASS", "k": "CLAIM", "s": 1, "cl": 50, "di": 0, "a": [
			_opt("CHI", {"companion_tile_instance_ids": [1, 2]}), _opt("RON", {}),
		]},
		{"l": "ROB_KAN 缺 PASS", "k": "ROB_KAN", "s": 2, "cl": 50, "di": 0,
			"a": [_opt("RON", {})]},
		{"l": "TURN 不得 CHI", "k": "TURN", "s": 0, "cl": -1, "di": -1, "a": [
			_opt("CHI", {"companion_tile_instance_ids": [1, 2]}),
			_opt("DISCARD", {"tile_instance_id": 3}),
		]},
		{"l": "CLAIM 不得 DISCARD", "k": "CLAIM", "s": 1, "cl": 10, "di": 0, "a": [
			_opt("DISCARD", {"tile_instance_id": 3}), _opt("PASS", {}),
		]},
		{"l": "ROB_KAN 仅 RON/PASS", "k": "ROB_KAN", "s": 1, "cl": 10, "di": 0, "a": [
			_opt("PON", {"companion_tile_instance_ids": [1, 2]}), _opt("PASS", {}),
		]},
		{"l": "TURN 拒 MINKAN", "k": "TURN", "s": 0, "cl": -1, "di": -1, "a": [
			_opt("KAN", {"kan_kind": "MINKAN", "companion_tile_instance_ids": [1, 2, 3]}),
			_opt("DISCARD", {"tile_instance_id": 9}),
		]},
		{"l": "CLAIM 拒 ANKAN", "k": "CLAIM", "s": 1, "cl": 10, "di": 0, "a": [
			_opt("KAN", {"kan_kind": "ANKAN", "tile_instance_ids": [1, 2, 3, 4]}),
			_opt("PASS", {}),
		]},
		{"l": "CLAIM 拒 ADDED_KAN", "k": "CLAIM", "s": 1, "cl": 10, "di": 0, "a": [
			_opt("KAN", {"kan_kind": "ADDED_KAN", "meld_id": 1, "added_tile_instance_id": 2}),
			_opt("PASS", {}),
		]},
		{"l": "ROB_KAN 拒 KAN", "k": "ROB_KAN", "s": 1, "cl": 10, "di": 0, "a": [
			_opt("KAN", {"kan_kind": "MINKAN", "companion_tile_instance_ids": [1, 2, 3]}),
			_opt("PASS", {}),
		]},
	]
	for c in rejects:
		_null(DecisionContext.make(c["k"], 1, _UUID, c["s"], c["a"], c["cl"], c["di"]), c["l"])

# ── 2) offer 结构 + payload（DECLARE_ABORTIVE_DRAW / ADDED_KAN int meld_id）─

func test_offer_structure_and_payload_contract() -> void:
	var bad := [
		{"l": "空 actions", "a": [], "w": "TURN", "s": 0, "cl": -1, "di": -1},
		{"l": "元素非 Dict", "a": ["x"], "w": "TURN", "s": 0, "cl": -1, "di": -1},
		{"l": "kind 非 String", "a": [{"kind": 1, "payload_options": [{"tile_instance_id": 1}]}],
			"w": "TURN", "s": 0, "cl": -1, "di": -1},
		{"l": "缺 kind", "a": [{"payload_options": [{"tile_instance_id": 1}]}],
			"w": "TURN", "s": 0, "cl": -1, "di": -1},
		{"l": "缺 payload_options", "a": [{"kind": "DISCARD"}],
			"w": "TURN", "s": 0, "cl": -1, "di": -1},
		{"l": "多余 offer 键", "a": [{
			"kind": "DISCARD", "payload_options": [{"tile_instance_id": 1}], "extra": 1,
		}], "w": "TURN", "s": 0, "cl": -1, "di": -1},
		{"l": "空 options", "a": [{"kind": "DISCARD", "payload_options": []}],
			"w": "TURN", "s": 0, "cl": -1, "di": -1},
		{"l": "option 非 Dict", "a": [{"kind": "DISCARD", "payload_options": ["x"]}],
			"w": "TURN", "s": 0, "cl": -1, "di": -1},
		{"l": "重复 kind", "a": [
			_opt("DISCARD", {"tile_instance_id": 1}), _opt("DISCARD", {"tile_instance_id": 2}),
		], "w": "TURN", "s": 0, "cl": -1, "di": -1},
		{"l": "重复规范化 option", "a": [{"kind": "KAN", "payload_options": [
			{"kan_kind": "ANKAN", "tile_instance_ids": [1, 2, 3, 4]},
			{"kan_kind": "ANKAN", "tile_instance_ids": [4, 3, 2, 1]},
		]}], "w": "TURN", "s": 0, "cl": -1, "di": -1},
		{"l": "旧 tile 键", "a": [{"kind": "DISCARD", "payload_options": [{"tile": 1}]}],
			"w": "TURN", "s": 0, "cl": -1, "di": -1},
		{"l": "ADDED_KAN 字符串 meld_id", "a": [{"kind": "KAN", "payload_options": [{
			"kan_kind": "ADDED_KAN", "meld_id": "m1", "added_tile_instance_id": 5,
		}]}], "w": "TURN", "s": 0, "cl": -1, "di": -1},
		{"l": "旧 ADDED 伪 kind", "a": [{"kind": "KAN", "payload_options": [{
			"kan_kind": "ADDED", "meld_id": 1, "added_tile_instance_id": 5,
		}]}], "w": "TURN", "s": 0, "cl": -1, "di": -1},
		{"l": "RON 非空 payload", "a": [
			{"kind": "RON", "payload_options": [{"tile_instance_id": 1}]}, _opt("PASS", {}),
		], "w": "CLAIM", "s": 0, "cl": _ns(1, 9), "di": 1},
		{"l": "payload 额外 claimed", "a": [
			_opt("DISCARD", {"tile_instance_id": 1, "claimed": 1}),
		], "w": "TURN", "s": 0, "cl": -1, "di": -1},
		{"l": "payload 额外 discarder", "a": [
			_opt("CHI", {"companion_tile_instance_ids": [1, 2], "discarder": 0}),
			_opt("PASS", {}),
		], "w": "CLAIM", "s": 1, "cl": _ns(1, 10), "di": 0},
	]
	for c in bad:
		_null(DecisionContext.make(c["w"], 1, _UUID, c["s"], c["a"], c["cl"], c["di"]),
			"offer: %s" % c["l"])
	var legal := [
		{"k": "DISCARD", "p": {"tile_instance_id": _ns(1, 1)}, "w": "TURN"},
		{"k": "RIICHI", "p": {"tile_instance_id": _ns(1, 2)}, "w": "TURN"},
		{"k": "KAN", "p": {"kan_kind": "ANKAN", "tile_instance_ids": [_ns(1, 1), _ns(1, 2), _ns(1, 3), _ns(1, 4)]}, "w": "TURN"},
		{"k": "KAN", "p": {"kan_kind": "ADDED_KAN", "meld_id": 0, "added_tile_instance_id": _ns(1, 9)},
			"w": "TURN"},
		{"k": "TSUMO", "p": {}, "w": "TURN"},
		{"k": "DECLARE_ABORTIVE_DRAW", "p": {"reason": "KYUUSYU_KYUUHAI"}, "w": "TURN"},
		{"k": "CHI", "p": {"companion_tile_instance_ids": [_ns(1, 1), _ns(1, 2)]}, "w": "CLAIM"},
		{"k": "PON", "p": {"companion_tile_instance_ids": [_ns(1, 1), _ns(1, 2)]}, "w": "CLAIM"},
		{"k": "KAN", "p": {"kan_kind": "MINKAN", "companion_tile_instance_ids": [_ns(1, 1), _ns(1, 2), _ns(1, 3)]},
			"w": "CLAIM"},
		{"k": "RON", "p": {}, "w": "CLAIM"},
		{"k": "PASS", "p": {}, "w": "CLAIM"},
		{"k": "RON", "p": {}, "w": "ROB_KAN"},
		{"k": "PASS", "p": {}, "w": "ROB_KAN"},
	]
	for row in legal:
		var actions: Array = [_opt(row["k"], row["p"])]
		if row["w"] != "TURN" and row["k"] != "PASS":
			actions.append(_opt("PASS", {}))
		var cl := _ns(1, 100) if row["w"] != "TURN" else -1
		var di := 0 if row["w"] != "TURN" else -1
		var seat := 1 if row["w"] != "TURN" else 0
		var ctx: DecisionContext = DecisionContext.make(
			row["w"], 1, _UUID, seat, actions, cl, di)
		assert_not_null(ctx, "合法 payload %s/%s" % [row["w"], row["k"]])
		var action: Action = _act(row["k"], seat, 1, _UUID, row["p"])
		assert_not_null(action, "Action 接受 %s" % row["k"])
		if action != null and row["k"] == "DECLARE_ABORTIVE_DRAW":
			_envelope(action)
			assert_eq(action.kind, "DECLARE_ABORTIVE_DRAW")
		if action != null and row["k"] == "KAN" and row["p"].get("kan_kind") == "ADDED_KAN":
			assert_true(action.payload["meld_id"] is int, "ADDED_KAN meld_id 必须 int")
			assert_eq(action.payload["kan_kind"], "ADDED_KAN")

# ── 3) hand_seq / instance id / seat / UUID + Variant 参数 ────────────────

func test_bounds_uuid_and_allowed_actions_variant() -> void:
	var turn := _turn_actions()
	var claim := _claim_actions()
	var max_hs: int = ProtocolConstants.MAX_HAND_SEQ
	var max_id: int = ProtocolConstants.MAX_SAFE_INT
	assert_not_null(DecisionContext.make("TURN", 0, _UUID, 0, _turn_actions(0)), "Context hs=0")
	assert_not_null(DecisionContext.make("TURN", max_hs, _UUID, 0, _turn_actions(max_hs)), "Context hs=MAX")
	assert_not_null(DecisionWindow.make("TURN", 0, _UUID, 0, -1, -1), "Window hs=0")
	assert_not_null(DecisionWindow.make("TURN", max_hs, _UUID, 0, -1, -1), "Window hs=MAX")
	_null(DecisionContext.make("TURN", -1, _UUID, 0, turn), "Context hs=-1")
	_null(DecisionContext.make("TURN", max_hs + 1, _UUID, 0, turn), "Context hs=MAX+1")
	_null(DecisionWindow.make("TURN", -1, _UUID, 0, -1, -1), "Window hs=-1")
	_null(DecisionWindow.make("TURN", max_hs + 1, _UUID, 0, -1, -1), "Window hs=MAX+1")
	assert_not_null(DecisionContext.make("TURN", 1, _UUID, 0, turn, -1, -1), "TURN claimed=-1")
	_null(DecisionContext.make("TURN", 1, _UUID, 0, turn, 0, -1), "TURN claimed 不得 0")
	assert_not_null(DecisionContext.make("CLAIM", 1, _UUID, 1, claim, _ns(1, 0), 0), "CLAIM claimed=0")
	assert_not_null(DecisionContext.make("CLAIM", 1, _UUID, 1, claim, _ns(1, _serial_max()), 0), "CLAIM claimed=MAX")
	_null(DecisionContext.make("CLAIM", 1, _UUID, 1, claim, max_id, 0), "CLAIM claimed=MAX_SAFE stale")
	_null(DecisionContext.make("CLAIM", 1, _UUID, 1, claim, _ns(0, 0), 0), "CLAIM claimed prev hand stale")
	_null(DecisionContext.make("CLAIM", 1, _UUID, 1, claim, _ns(2, 0), 0), "CLAIM claimed next hand stale")
	_null(DecisionContext.make("CLAIM", 1, _UUID, 1, claim, max_id + 1, 0), "CLAIM claimed=MAX+1")
	_null(DecisionContext.make("CLAIM", 1, _UUID, 1, claim, -1, 0), "CLAIM claimed=-1")
	assert_not_null(DecisionWindow.make("TURN", 1, _UUID, 0, -1, -1), "TURN tile=-1")
	assert_not_null(DecisionWindow.make("TURN", 1, _UUID, 0, _ns(1, 0), -1), "TURN tile=0")
	assert_not_null(DecisionWindow.make("TURN", 1, _UUID, 0, _ns(1, _serial_max()), -1), "TURN tile=MAX")
	_null(DecisionWindow.make("TURN", 1, _UUID, 0, max_id, -1), "TURN tile=MAX_SAFE stale")
	_null(DecisionWindow.make("TURN", 1, _UUID, 0, _ns(0, 5), -1), "TURN tile prev hand stale")
	_null(DecisionWindow.make("TURN", 1, _UUID, 0, max_id + 1, -1), "TURN tile=MAX+1")
	assert_not_null(DecisionWindow.make("CLAIM", 1, _UUID, 0, _ns(1, 0), 0), "CLAIM tile=0")
	_null(DecisionWindow.make("CLAIM", 1, _UUID, 0, -1, 0), "CLAIM tile=-1")
	_null(DecisionWindow.make("CLAIM", 1, _UUID, 0, max_id + 1, 0), "CLAIM tile=MAX+1")
	assert_not_null(DecisionWindow.make("ROB_KAN", 1, _UUID, 2, _ns(1, 0), 2), "ROB tile=0")
	_null(DecisionWindow.make("ROB_KAN", 1, _UUID, 2, -1, 2), "ROB tile=-1")
	_null(DecisionContext.make("TURN", 1, _UUID, -1, turn), "Context seat=-1")
	_null(DecisionContext.make("TURN", 1, _UUID, 4, turn), "Context seat=4")
	assert_not_null(DecisionContext.make("TURN", 1, _UUID, 0, turn), "Context 合法 UUID")
	assert_not_null(DecisionWindow.make("TURN", 1, _UUID, 0, -1, -1), "Window 合法 UUID")
	for row in [
		{"id": "", "l": "空"}, {"id": "not-a-uuid", "l": "非 UUID"},
		{"id": "aaaaaaaa-bbbb-1ccc-8ddd-eeeeeeeeeeee", "l": "错误 version"},
		{"id": "aaaaaaaa-bbbb-4ccc-cddd-eeeeeeeeeeee", "l": "错误 variant"},
		{"id": "aaaaaaaa-bbbb-4ccc-0ddd-eeeeeeeeeeee", "l": "variant=0"},
		{"id": "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE", "l": "uppercase"},
	]:
		_null(DecisionContext.make("TURN", 1, row["id"], 0, turn), "Context id %s" % row["l"])
		_null(DecisionWindow.make("TURN", 1, row["id"], 0, -1, -1), "Window id %s" % row["l"])
	## 第 5 参必须 Variant（PropertyInfo.type == TYPE_NIL）。契约失败后不继续 call，避免 typed Array 运行时炸机（非软通过）。
	var make_arg5: Dictionary = _arg_type(_CONTEXT_SCRIPT, "make", 4)
	var make_arg5_type: int = int(make_arg5.get("type", -1))
	assert_eq(make_arg5_type, TYPE_NIL,
		"DecisionContext.make 第 5 参 allowed_actions 必须 Variant（TYPE_NIL）；当前=%d" % make_arg5_type)
	if make_arg5_type != TYPE_NIL:
		return
	var script: GDScript = load(_CONTEXT_SCRIPT) as GDScript
	assert_not_null(script)
	for sample in [null, {}, "x", 1, true, RefCounted.new()]:
		var ret: Variant = script.call("make", "TURN", 1, _UUID, 0, sample, -1, -1)
		assert_null(ret, "非 Array allowed_actions → null typeof=%d" % typeof(sample))

# ── 4) 标量只读 + deep copy ───────────────────────────────────────────────

func test_scalars_readonly_and_deep_copies() -> void:
	## copy-on-write：make 后篡改 source 不得污染 ctx（含 nested payload_options）。
	var source: Array = _claim_actions()
	var orig_kind: String = str((source[0] as Dictionary).get("kind", ""))
	var orig_payload: Dictionary = (
		(source[0] as Dictionary)["payload_options"] as Array)[0].duplicate(true)
	var ctx: DecisionContext = DecisionContext.make(
		"CLAIM", 1, _UUID, 1, source, _ns(1, 42), 0)
	assert_not_null(ctx)
	if ctx == null:
		return
	source[0]["kind"] = "HACKED"
	((source[0] as Dictionary)["payload_options"] as Array)[0]["x"] = 1
	assert_eq(str(ctx.allowed_actions[0]["kind"]), orig_kind,
		"篡改 source.kind 不得污染 allowed_actions")
	assert_false(
		((ctx.allowed_actions[0] as Dictionary)["payload_options"] as Array)[0].has("x"),
		"篡改 source nested payload 不得污染 allowed_actions")
	assert_true(ctx.allowed_kinds.has(orig_kind), "allowed_kinds 仍含原始 kind")
	assert_false(ctx.allowed_kinds.has("HACKED"), "allowed_kinds 不得含篡改 kind")
	var dict_after_src: Dictionary = ctx.to_dict()
	assert_eq(str((dict_after_src["allowed_actions"] as Array)[0]["kind"]), orig_kind,
		"to_dict.allowed_actions 仍为原始 kind")
	assert_false(
		(((dict_after_src["allowed_actions"] as Array)[0] as Dictionary)["payload_options"] as Array)[0].has("x"),
		"to_dict nested payload 不得被 source 污染")
	assert_eq(
		((dict_after_src["allowed_actions"] as Array)[0] as Dictionary)["payload_options"][0],
		orig_payload, "to_dict nested payload 保持 make 时合法值")
	_readonly(ctx, _CONTEXT_SCALARS, "DecisionContext")
	var aa1: Array = ctx.allowed_actions
	var aa2: Array = ctx.allowed_actions
	assert_false(is_same(aa1, aa2), "allowed_actions 每次 deep copy")
	aa1[0]["kind"] = "HACKED"
	if aa1[0].has("payload_options") and (aa1[0]["payload_options"] as Array).size() > 0:
		(aa1[0]["payload_options"] as Array)[0]["x"] = 1
	assert_ne(str(ctx.allowed_actions[0]["kind"]), "HACKED", "篡改不得污染 allowed_actions")
	var ak1: Array = ctx.allowed_kinds
	ak1.append("HACK")
	assert_false(ctx.allowed_kinds.has("HACK"), "篡改 allowed_kinds 不得污染")
	var d1: Dictionary = ctx.to_dict()
	assert_eq(_sorted_keys(d1), _sorted_list(_CONTEXT_PUBLIC_KEYS), "Context.to_dict exact 八键")
	d1["window_kind"] = "HACK"
	d1["seat"] = 99
	(d1["allowed_actions"] as Array).clear()
	var d2: Dictionary = ctx.to_dict()
	assert_eq(d2["window_kind"], "CLAIM")
	assert_eq(d2["seat"], 1)
	assert_eq(ctx.window_kind, "CLAIM")
	assert_eq(ctx.seat, 1)
	var win: DecisionWindow = DecisionWindow.make("CLAIM", 3, _UUID2, 1, _ns(3, 50), 1)
	assert_not_null(win)
	if win == null:
		return
	_readonly(win, _WINDOW_SCALARS, "DecisionWindow")

# ── 5) subject/discarder 不变量 ───────────────────────────────────────────

func test_subject_discarder_invariants() -> void:
	assert_not_null(DecisionWindow.make("TURN", 1, _UUID, 0, -1, -1), "TURN tile=-1")
	assert_not_null(DecisionWindow.make("TURN", 1, _UUID, 2, _ns(1, 15), -1), "TURN tile 合法")
	assert_not_null(DecisionWindow.make("CLAIM", 1, _UUID, 0, _ns(1, 50), 0), "CLAIM sub==disc")
	assert_not_null(DecisionWindow.make("ROB_KAN", 1, _UUID, 3, _ns(1, 99), 3), "ROB sub==disc")
	for c in [
		{"l": "TURN discarder!=-1", "k": "TURN", "s": 0, "t": -1, "d": 1},
		{"l": "TURN subject 越界", "k": "TURN", "s": 4, "t": -1, "d": -1},
		{"l": "TURN subject 负", "k": "TURN", "s": -1, "t": -1, "d": -1},
		{"l": "CLAIM tile -1", "k": "CLAIM", "s": 0, "t": -1, "d": 0},
		{"l": "CLAIM disc!=sub", "k": "CLAIM", "s": 0, "t": _ns(1, 5), "d": 1},
		{"l": "CLAIM subject 越界", "k": "CLAIM", "s": 4, "t": _ns(1, 5), "d": 4},
		{"l": "ROB tile -1", "k": "ROB_KAN", "s": 1, "t": -1, "d": 1},
		{"l": "ROB disc!=sub", "k": "ROB_KAN", "s": 1, "t": _ns(1, 5), "d": 2},
	]:
		_null(DecisionWindow.make(c["k"], 1, _UUID, c["s"], c["t"], c["d"]), c["l"])
	var turn := _turn_actions()
	for c in [{"cl": _ns(1, 1), "di": -1}, {"cl": -1, "di": 0}, {"cl": _ns(1, 5), "di": 2}]:
		_null(DecisionContext.make("TURN", 1, _UUID, 0, turn, c["cl"], c["di"]),
			"TURN claimed/disc=%s/%s" % [c["cl"], c["di"]])
	var claim := _claim_actions()
	var rob := _rob_actions()
	for c in [
		{"k": "CLAIM", "a": claim, "s": 1, "cl": _ns(1, 10), "di": 4, "l": "CLAIM disc=4"},
		{"k": "CLAIM", "a": claim, "s": 2, "cl": _ns(1, 10), "di": 2, "l": "CLAIM seat==disc"},
		{"k": "ROB_KAN", "a": rob, "s": 3, "cl": _ns(1, 10), "di": 3, "l": "ROB seat==disc"},
		{"k": "CLAIM", "a": claim, "s": 1, "cl": _ns(1, 10), "di": -1, "l": "CLAIM disc=-1"},
	]:
		_null(DecisionContext.make(c["k"], 1, _UUID, c["s"], c["a"], c["cl"], c["di"]), c["l"])

# ── 6) add_context / context_for_seat / to_dict ───────────────────────────

func test_add_context_projection_and_to_dict() -> void:
	var turn_win: DecisionWindow = DecisionWindow.make("TURN", 1, _UUID, 0, -1, -1)
	assert_not_null(turn_win)
	if turn_win == null:
		return
	var ctx0: DecisionContext = DecisionContext.make("TURN", 1, _UUID, 0, _turn_actions())
	assert_not_null(ctx0)
	assert_true(turn_win.add_context(ctx0), "TURN subject context")
	assert_false(turn_win.add_context(
		DecisionContext.make("TURN", 1, _UUID, 0, _turn_actions())), "TURN 最多一个")
	assert_false(turn_win.add_context(
		DecisionContext.make("TURN", 1, _UUID, 1, _turn_actions())), "TURN 仅 subject")
	var claim_win: DecisionWindow = DecisionWindow.make("CLAIM", 1, _UUID, 0, _ns(1, 77), 0)
	assert_not_null(claim_win)
	if claim_win == null:
		return
	_null(DecisionContext.make("CLAIM", 1, _UUID, 0, _claim_actions(), _ns(1, 77), 0),
		"CLAIM subject seat 不可建 Context")
	var good: DecisionContext = DecisionContext.make(
		"CLAIM", 1, _UUID, 1, _claim_actions(), _ns(1, 77), 0)
	assert_not_null(good)
	assert_true(claim_win.add_context(good), "匹配非 subject CLAIM")
	for row in [
		{"l": "hand_seq", "ctx": DecisionContext.make(
			"CLAIM", 2, _UUID, 2, _claim_actions(2), _ns(2, 77), 0)},
		{"l": "decision_id", "ctx": DecisionContext.make(
			"CLAIM", 1, _UUID3, 2, _claim_actions(), _ns(1, 77), 0)},
		{"l": "claimed", "ctx": DecisionContext.make(
			"CLAIM", 1, _UUID, 2, _claim_actions(), _ns(1, 88), 0)},
		{"l": "discarder", "ctx": DecisionContext.make(
			"CLAIM", 1, _UUID, 2, _claim_actions(), _ns(1, 77), 1)},
		{"l": "window_kind", "ctx": DecisionContext.make(
			"ROB_KAN", 1, _UUID, 2, _rob_actions(), _ns(1, 77), 0)},
	]:
		assert_not_null(row["ctx"], "可建但 add 应拒: %s" % row["l"])
		assert_false(claim_win.add_context(row["ctx"]), "add 拒绝 %s" % row["l"])
	var win: DecisionWindow = DecisionWindow.make("CLAIM", 1, _UUID, 0, _ns(1, 55), 0)
	assert_not_null(win)
	if win == null:
		return
	var ctx1: DecisionContext = DecisionContext.make("CLAIM", 1, _UUID, 1, [
		_opt("CHI", {"companion_tile_instance_ids": [_ns(1, 1), _ns(1, 2)]}), _opt("PASS", {}),
	], _ns(1, 55), 0)
	var ctx2: DecisionContext = DecisionContext.make(
		"CLAIM", 1, _UUID, 2, [_opt("RON", {}), _opt("PASS", {})], _ns(1, 55), 0)
	assert_true(win.add_context(ctx1) and win.add_context(ctx2))
	var p1a: DecisionContext = win.context_for_seat(1)
	var p1b: DecisionContext = win.context_for_seat(1)
	assert_not_null(p1a)
	assert_not_null(p1b)
	if p1a == null or p1b == null:
		return
	assert_false(is_same(p1a, p1b), "context_for_seat 非同一引用")
	assert_false(is_same(p1a, ctx1), "投影非内部引用")
	assert_true(p1a.allowed_kinds.has("CHI") and not p1a.allowed_kinds.has("RON"),
		"seat1 不泄漏 seat2 RON")
	var p2: DecisionContext = win.context_for_seat(2)
	assert_not_null(p2)
	if p2 == null:
		return
	assert_true(p2.allowed_kinds.has("RON") and not p2.allowed_kinds.has("CHI"),
		"seat2 不泄漏 seat1 CHI")
	(p1a.allowed_actions as Array).clear()
	p1a.to_dict().clear()
	var p1c: DecisionContext = win.context_for_seat(1)
	assert_not_null(p1c)
	if p1c == null:
		return
	assert_eq(p1c.seat, 1)
	assert_gt(p1c.allowed_actions.size(), 0, "再读不得被污染")
	var tw: DecisionWindow = DecisionWindow.make("TURN", 1, _UUID, 0, -1, -1)
	assert_not_null(tw)
	if tw == null:
		return
	assert_true(tw.add_context(DecisionContext.make("TURN", 1, _UUID, 0, _turn_actions())))
	var d: Dictionary = tw.to_dict()
	assert_eq(_sorted_keys(d), _sorted_list(_WINDOW_PUBLIC_KEYS), "Window.to_dict exact keys")
	for banned in ["contexts", "offers", "intents", "payload", "allowed_actions"]:
		assert_false(d.has(banned), "to_dict 不得含 %s" % banned)
	var seats_mut: Array = d["seats"] as Array
	var resp_mut: Array = d["responded_seats"] as Array
	var seats_n: int = seats_mut.size()
	var resp_n: int = resp_mut.size()
	seats_mut.append(99)
	resp_mut.append(88)
	var d_again: Dictionary = tw.to_dict()
	assert_eq((d_again["seats"] as Array).size(), seats_n, "seats 深拷贝")
	assert_eq((d_again["responded_seats"] as Array).size(), resp_n, "responded_seats 深拷贝")
	assert_false((d_again["seats"] as Array).has(99))
	assert_false((d_again["responded_seats"] as Array).has(88))

# ── 7) register_intent / complete / 排序 / 深拷贝 ─────────────────────────

func test_register_intent_once_complete_order_copy() -> void:
	## register_intent 第 1 参必须 typed Action（PropertyInfo，非源码扫描、非 Dictionary 触发 runtime）。
	var intent_arg: Dictionary = _arg_type(_WINDOW_SCRIPT, "register_intent", 0)
	assert_eq(int(intent_arg.get("type", -1)), TYPE_OBJECT,
		"register_intent 第 1 参 type 必须 TYPE_OBJECT；当前=%d" % int(intent_arg.get("type", -1)))
	assert_eq(str(intent_arg.get("class_name", "")), "Action",
		"register_intent 第 1 参 class_name 必须精确为 Action；当前=%s" % str(intent_arg.get("class_name", "")))
	var win: DecisionWindow = DecisionWindow.make("TURN", 1, _UUID, 0, _ns(1, 10), -1)
	assert_not_null(win)
	if win == null:
		return
	var actions := [_opt("DISCARD", {"tile_instance_id": _ns(1, 10)}), _opt("TSUMO", {})]
	assert_true(win.add_context(DecisionContext.make("TURN", 1, _UUID, 0, actions)))
	var good: Action = _act("DISCARD", 0, 1, _UUID, {"tile_instance_id": _ns(1, 10)})
	assert_not_null(good)
	_envelope(good)
	assert_true(win.register_intent(good), "exact offered option")
	var win2: DecisionWindow = DecisionWindow.make("TURN", 1, _UUID2, 0, _ns(1, 10), -1)
	assert_true(win2.add_context(DecisionContext.make("TURN", 1, _UUID2, 0, actions)))
	assert_false(win2.register_intent(
		_act("DISCARD", 0, 1, _UUID2, {"tile_instance_id": _ns(1, 99)})), "非 offered payload")
	assert_false(win2.register_intent(
		_act("RIICHI", 0, 1, _UUID2, {"tile_instance_id": _ns(1, 10)})), "非 offered kind")
	assert_false(win2.register_intent(
		_act("DISCARD", 0, 2, _UUID2, {"tile_instance_id": _ns(1, 10)})), "错误 hand_seq")
	assert_false(win2.register_intent(
		_act("DISCARD", 0, 1, _UUID3, {"tile_instance_id": _ns(1, 10)})), "错误 decision_id")
	assert_false(win2.register_intent(
		_act("DISCARD", 1, 1, _UUID2, {"tile_instance_id": _ns(1, 10)})), "错误 seat")
	var incomplete_wire := _wire("DISCARD", 0, 1, _UUID2, {"tile_instance_id": _ns(1, 10)})
	incomplete_wire.erase("client_seq")
	var incomplete: Action = Action.from_dict(incomplete_wire)
	assert_null(incomplete, "缺 client_seq → null")
	assert_false(win2.register_intent(incomplete), "null intent 拒绝")
	var extra_wire := _wire("DISCARD", 0, 1, _UUID2, {"tile_instance_id": _ns(1, 10)})
	extra_wire["source"] = "x"
	assert_null(Action.from_dict(extra_wire), "多余键 wire → null")
	assert_false(win2.register_intent(Action.from_dict(extra_wire)), "null（多余键）拒绝")
	var claim: DecisionWindow = DecisionWindow.make("CLAIM", 1, _UUID, 0, _ns(1, 33), 0)
	assert_not_null(claim)
	if claim == null:
		return
	assert_true(claim.add_context(
		DecisionContext.make("CLAIM", 1, _UUID, 3, _rob_actions(), _ns(1, 33), 0)))
	assert_true(claim.add_context(
		DecisionContext.make("CLAIM", 1, _UUID, 1, _claim_actions(), _ns(1, 33), 0)))
	assert_true(claim.add_context(
		DecisionContext.make("CLAIM", 1, _UUID, 2, _claim_actions(), _ns(1, 33), 0)))
	assert_false(claim.is_complete(), "无 intent 未 complete")
	var env1: Action = _act("PASS", 1, 1, _UUID, {})
	assert_true(claim.register_intent(env1))
	assert_false(claim.register_intent(_act("RON", 1, 1, _UUID, {}, 2)), "每座仅一次")
	var poisoned: Dictionary = env1.payload
	poisoned["x"] = 1
	var mid: Action = claim.intent_for_seat(1)
	var mid2: Action = claim.intent_for_seat(1)
	assert_not_null(mid)
	assert_not_null(mid2)
	assert_false(is_same(mid, mid2), "intent_for_seat 非同一 Action")
	assert_eq(mid.kind, "PASS")
	assert_false(mid.payload.has("x"), "intent payload 深拷贝")
	assert_false(claim.is_complete(), "1/3 未 complete")
	assert_true(claim.register_intent(_act("PASS", 3, 1, _UUID, {})))
	assert_false(claim.is_complete(), "2/3 未 complete")
	assert_true(claim.register_intent(_act("RON", 2, 1, _UUID, {})))
	assert_true(claim.is_complete(), "全部应答才 complete")
	var seats: Array = claim.seats()
	assert_eq(seats, _sorted_list(seats), "seats() 升序稳定方法")
	var intents_a: Array = claim.intents()
	var intents_b: Array = claim.intents()
	assert_false(is_same(intents_a, intents_b), "intents() 非同一数组")
	assert_eq(intents_a.size(), 3)
	var prev := -1
	for intent_v in intents_a:
		var intent: Action = intent_v as Action
		assert_not_null(intent, "intents() 元素必须 Action")
		assert_gt(intent.seat, prev, "intents() 按 seat 升序")
		prev = intent.seat
		_envelope(intent)
	var first: Action = intents_a[0] as Action
	first.payload["hack"] = true
	intents_a.clear()
	var again: Array = claim.intents()
	assert_eq(again.size(), 3)
	assert_false((again[0] as Action).payload.has("hack"), "intents 元素深拷贝")
	assert_false(is_same(again[0], first), "再次 intents 非同一 Action")
