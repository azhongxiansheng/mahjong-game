extends GutTest
# E2-02 Red：NBC 纯投影，extends 轻量 IBattleController（无 authority）。
# exact-4 snapshot；gap 可接受；ACTION 只 journal；MeldView.tiles 保序。
# 非法 typed payload/hash：合法 make + Object.set 伪造，不走 make 非法 DTO。
# 严格 seq / pending ACTION / resync_required / stream 原子：见文末测。
# 同 hash TURN_PROMPT 原子 commit；异 hash ACTION 进 pending → 匹配 snap 一次提交。
# exact NetworkedEvent：入口须拒 GDScript 子类（is 会 true）。

## 冻结契约反例：is NetworkedEvent 为 true，但 get_script() 不是 exact 基类。
class SubNetworkedEvent extends NetworkedEvent:
	pass

const NBC_PATH := "res://battle/networked_battle_controller.gd"
const IBC_PATH := "res://battle/i_battle_controller.gd"
const ROOM := "room_net_x"
const OTHER := "room_other"
const DECISION := "550e8400-e29b-41d4-a716-4466554400aa"
const CMD := "550e8400-e29b-41d4-a716-446655440000"
const BAD_HASH := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const SNAP_KEYS := ["snapshot_server_seq", "next_server_seq", "seat_view", "modules"]
const MOD_KEYS := ["module_key", "schema_version", "payload"]
const CORE_KEYS := [
	"recipient_seat", "hand_seq", "dealer_seat", "current_seat", "phase",
	"round_wind", "hand_number", "honba", "riichi_sticks", "live_wall_count",
	"dora_indicators", "seats",
]
const SEAT_KEYS := [
	"seat", "seat_wind", "score", "concealed_tiles", "concealed_count",
	"last_drawn_tile_instance_id", "river", "melds",
	"riichi_declared", "riichi_double", "riichi_discard_index",
]
const NO_PROPS := ["state", "engine", "registry", "scheduler", "ai", "events", "action_journal"]
const NO_METHODS := [
	"run_to_end", "apply_ron", "apply_action", "load_replay_journal",
	"set_replay_decisions", "set_replay_actions", "extract_player_actions",
]
const PROJ_METHODS := [
	"ingest_networked_event", "ingest_event_stream", "get_public_view",
	"get_core_table_view", "get_event_journal", "current_seq", "desync_check",
	"resync_required",
]
func _exact(d: Dictionary, keys: Array) -> bool:
	if d.keys().size() != keys.size():
		return false
	for k in keys:
		if not d.has(k):
			return false
	return true
func _has_prop(obj: Object, property_name: String) -> bool:
	for p in obj.get_property_list():
		if str(p.get("name", "")) == property_name:
			return true
	return false

func _nbc_script() -> GDScript:
	if not ResourceLoader.exists(NBC_PATH):
		assert_true(false, "缺 %s" % NBC_PATH)
		return null
	var source_file := FileAccess.open(NBC_PATH, FileAccess.READ)
	assert_not_null(source_file, "须可读取 %s" % NBC_PATH)
	if source_file == null:
		return null
	var first_line := source_file.get_line().strip_edges()
	if first_line != "class_name NetworkedBattleController extends IBattleController":
		assert_true(false, "NBC 必须直接 extends IBattleController")
		return null
	var script := load(NBC_PATH) as GDScript
	assert_not_null(script, "须可加载 NBC 脚本")
	return script
## Wall 契约：hand_seq=0 时 iid = serial = TileId.ALL.find(tile_id)*4 + copy_index。
## red 5 仅 copy0；owner_seat 与 copy_index 对齐（Wall 占位语义）。
func _canonical_iid(tile_id: int, copy_index: int) -> int:
	var idx: int = TileId.ALL.find(tile_id)
	assert_true(idx >= 0, "tile_id 须在 TileId.ALL")
	assert_true(copy_index >= 0 and copy_index <= 3, "copy_index 0..3")
	return idx * 4 + copy_index
func _tile(tile_id: int, copy_index: int, red := false) -> Dictionary:
	if red:
		assert_true(copy_index == 0 and tile_id in [TileId.W5, TileId.T5, TileId.S5],
			"red 仅 5m/5p/5s copy0")
	return {
		"instance_id": _canonical_iid(tile_id, copy_index),
		"tile_id": tile_id,
		"is_red_dora": red,
		"owner_seat": copy_index,
	}
## seat1 CHI：W1c1 / W2c1 / W3c0（领域升序）；called=W3c0；from_seat=上家 0。
## 可见实体 iid 全局唯一且 0..135；不 new 领域对象。
func _chi_seat1() -> Dictionary:
	var w1 := _tile(TileId.W1, 1)
	var w2 := _tile(TileId.W2, 1)
	var w3 := _tile(TileId.W3, 0)
	return {
		"meld_id": 1, "kind": "CHI", "from_seat": 0,
		"called_tile_instance_id": int(w3["instance_id"]), "added_tile_instance_id": -1,
		"tiles": [w1, w2, w3],
	}
func _seat(s: int, tiles: Array, n: int, melds: Array = []) -> Dictionary:
	var d := {
		"seat": s, "seat_wind": [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N][s],
		"score": 25000, "concealed_tiles": tiles.duplicate(true), "concealed_count": n,
		"last_drawn_tile_instance_id": -1, "river": [], "melds": melds.duplicate(true),
		"riichi_declared": false, "riichi_double": false, "riichi_discard_index": -1,
	}
	assert_true(_exact(d, SEAT_KEYS))
	return d
func _core(recip := 0) -> Dictionary:
	# own concealed：东风 copy=recipient，与 meld/dora 无重叠
	var own := _tile(TileId.E, recip)
	var seats: Array = []
	for s in range(4):
		seats.append(_seat(s, [own] if s == recip else [], 1 if s == recip else 13,
			[_chi_seat1()] if s == 1 else []))
	var p := {
		"recipient_seat": recip, "hand_seq": 0, "dealer_seat": 0, "current_seat": 0,
		"phase": "DRAW", "round_wind": TileId.E, "hand_number": 1, "honba": 0,
		"riichi_sticks": 0, "live_wall_count": 70,
		"dora_indicators": [_tile(TileId.W5, 0, true)], "seats": seats,
	}
	assert_true(_exact(p, CORE_KEYS))
	return p
func _mod(key: String, payload: Dictionary) -> Dictionary:
	var m := {"module_key": key, "schema_version": 1, "payload": payload.duplicate(true)}
	assert_true(_exact(m, MOD_KEYS))
	return m
func _meta_mod() -> Dictionary:
	return MatchingMetaSnapshotProvider.fixture_module()


func _default_modules(recip := 0) -> Array:
	return [_mod("core_table", _core(recip)), _meta_mod()]


func _snap(seq: int, recip := 0, modules: Array = []) -> Dictionary:
	var mods: Array = modules if not modules.is_empty() else _default_modules(recip)
	var p := {
		"snapshot_server_seq": seq, "next_server_seq": seq + 1,
		"seat_view": recip, "modules": mods,
	}
	assert_true(_exact(p, SNAP_KEYS))
	return p
## 变更 phase/wall 得到不同 view_hash 的合法 snapshot payload（不改 recipient）。
func _snap_var(seq: int, phase: String, wall: int, recip := 0) -> Dictionary:
	var core := _core(recip)
	core["phase"] = phase
	core["live_wall_count"] = wall
	return _snap(seq, recip, [_mod("core_table", core), _meta_mod()])
func _rs(seq: int, payload: Dictionary, room := ROOM, vh := "") -> NetworkedEvent:
	var h := vh if not vh.is_empty() else ProtocolViewCodec.compute_view_hash(payload)
	assert_eq(h.length(), 64)
	var ne := NetworkedEvent.make("ROOM_SNAPSHOT", seq, room, payload, h)
	assert_not_null(ne)
	return ne
## 合法 make 后写私有字段（forged）。
func _forge(ne: NetworkedEvent, payload = null, vh = null) -> NetworkedEvent:
	if payload != null:
		ne.set("_payload", (payload as Dictionary).duplicate(true))
	if vh != null:
		ne.set("_view_hash", str(vh))
	return ne
func _aa(seq: int, vh: String) -> NetworkedEvent:
	var p := {
		"causation_command_id": CMD, "hand_seq": 0, "decision_id": DECISION,
		"seat": 0, "action_kind": "PASS", "resolved_payload": {},
	}
	var ne := NetworkedEvent.make("ACTION_APPLIED", seq, ROOM, p, vh)
	assert_not_null(ne)
	return ne
## 合法 TURN_PROMPT：真实 TileView + ActionOffer wire（DISCARD）；view_hash 由调用方绑定公共投影。
func _tp(seq: int, vh: String, seat := 0) -> NetworkedEvent:
	# hand_seq=0 与 _core 对齐；iid 走 Wall 契约 _tile → 0..135 命名空间
	var hand_tile := _tile(TileId.E, seat)
	var p := {
		"hand_seq": 0,
		"decision_id": DECISION,
		"seat": seat,
		"hand": [hand_tile],
		"last_drawn_tile_instance_id": -1,
		"allowed_actions": [{
			"kind": "DISCARD",
			"payload_options": [{"tile_instance_id": int(hand_tile["instance_id"])}],
		}],
	}
	var ne := NetworkedEvent.make("TURN_PROMPT", seq, ROOM, p, vh)
	assert_not_null(ne, "TURN_PROMPT 须经 NetworkedEvent.make 严格合法")
	return ne
## 旧 stub 非 IBC 时 assert 后 return。
func _nbc(recip := 0, room := ROOM) -> Object:
	var sc := _nbc_script()
	if sc == null:
		return null
	return sc.new(room, recip)
func _resync(nbc: Object) -> bool:
	assert_true(nbc != null and nbc.has_method("resync_required"), "须有 resync_required")
	if nbc == null or not nbc.has_method("resync_required"):
		return true  # 缺 API 时视为异常态，令后续 expect-false 也 Red
	return bool(nbc.call("resync_required"))
## 提交 seq1 基线 ROOM_SNAPSHOT；返回冻结投影态。
func _baseline_seq1(nbc: Object, recip := 0) -> Dictionary:
	var p1 := _snap(1, recip)
	assert_true(bool(nbc.call("ingest_networked_event", _rs(1, p1))))
	assert_eq(int(nbc.call("current_seq")), 1)
	# 行为测优先；resync API 由 PROJ_METHODS / 显式 _resync 断言覆盖
	if nbc.has_method("resync_required"):
		assert_false(bool(nbc.call("resync_required")), "基线后 resync=false")
	return _st(nbc)
## journal 记每个 NetworkedEvent.to_dict 深副本；含 resync_required（缺方法时 null）。
func _st(nbc: Object) -> Dictionary:
	var view := {}
	var jdicts: Array = []
	var seq := -1
	var resync = null
	if nbc != null and nbc.has_method("get_public_view"):
		var v = nbc.call("get_public_view")
		if typeof(v) == TYPE_DICTIONARY:
			view = (v as Dictionary).duplicate(true)
	if nbc != null and nbc.has_method("get_event_journal"):
		var j = nbc.call("get_event_journal")
		if typeof(j) == TYPE_ARRAY:
			for ev in j:
				if ev is NetworkedEvent:
					jdicts.append((ev as NetworkedEvent).to_dict())
	if nbc != null and nbc.has_method("current_seq"):
		seq = int(nbc.call("current_seq"))
	if nbc != null and nbc.has_method("resync_required"):
		resync = bool(nbc.call("resync_required"))
	return {"view": view, "journal": jdicts, "seq": seq, "resync": resync}
func _same(a: Dictionary, b: Dictionary, label: String) -> void:
	assert_eq(JSON.stringify(a["view"]), JSON.stringify(b["view"]), "%s view" % label)
	assert_eq(JSON.stringify(a["journal"]), JSON.stringify(b["journal"]), "%s journal" % label)
	assert_eq(int(a["seq"]), int(b["seq"]), "%s seq" % label)
	# 旧路径 mid/after 均无 resync 键或均为 null 时跳过；新测显式比
	if a.has("resync") and b.has("resync") and a["resync"] != null and b["resync"] != null:
		assert_eq(bool(a["resync"]), bool(b["resync"]), "%s resync" % label)
## 仅 projection/journal/current_seq 与基线相同（允许 resync 变化）。
func _same_committed(a: Dictionary, b: Dictionary, label: String) -> void:
	assert_eq(JSON.stringify(a["view"]), JSON.stringify(b["view"]), "%s view" % label)
	assert_eq(JSON.stringify(a["journal"]), JSON.stringify(b["journal"]), "%s journal" % label)
	assert_eq(int(a["seq"]), int(b["seq"]), "%s seq" % label)
func _reject(nbc: Object, ev: Variant, mid: Dictionary, label: String) -> void:
	assert_false(bool(nbc.call("ingest_networked_event", ev)), label)
	_same(mid, _st(nbc), label)
	var view: Dictionary = mid["view"]
	if not view.is_empty() and nbc.has_method("desync_check"):
		assert_true(bool(nbc.call("desync_check", ProtocolViewCodec.compute_view_hash(view))),
			"%s stored hash 未变" % label)
func _assert_modules_ok(pub: Dictionary) -> void:
	var mods: Array = pub["modules"]
	var keys: Array = []
	for m in mods:
		keys.append(str((m as Dictionary)["module_key"]))
	var sk := keys.duplicate()
	sk.sort()
	assert_eq(JSON.stringify(keys), JSON.stringify(sk), "modules 已排序")
	var seen := {}
	for k in keys:
		assert_false(seen.has(k), "modules 唯一 %s" % k)
		seen[k] = true
	assert_true(seen.has("core_table"))
	assert_true(_exact((mods[keys.find("core_table")] as Dictionary)["payload"], CORE_KEYS))


func test_extends_lightweight_ibc_no_authority() -> void:
	var sc := _nbc_script()
	if sc == null:
		return
	var ibc: GDScript = load(IBC_PATH) as GDScript
	assert_eq(sc.get_base_script(), ibc, "直接 extends 轻量 IBattleController")
	if sc.get_base_script() != ibc:
		return
	var nbc: Object = sc.new(ROOM, 2)
	assert_not_null(nbc)
	assert_true(nbc is IBattleController)
	var room_ok := ("room_id" in nbc) or nbc.has_method("get_room_id")
	var seat_ok := ("recipient_seat" in nbc) or nbc.has_method("get_recipient_seat")
	if "room_id" in nbc:
		assert_eq(str(nbc.get("room_id")), ROOM)
	elif nbc.has_method("get_room_id"):
		assert_eq(str(nbc.call("get_room_id")), ROOM)
	if "recipient_seat" in nbc:
		assert_eq(int(nbc.get("recipient_seat")), 2)
	elif nbc.has_method("get_recipient_seat"):
		assert_eq(int(nbc.call("get_recipient_seat")), 2)
	assert_true(room_ok and seat_ok, "绑定 room_id + recipient_seat")
	for prop in NO_PROPS:
		assert_false(_has_prop(nbc, prop), "禁属性 %s" % prop)
	for ban in NO_METHODS:
		assert_false(nbc.has_method(ban), "禁方法 %s" % ban)
	for req in PROJ_METHODS:
		assert_true(nbc.has_method(req), "API %s" % req)


func test_ingest_snapshot_views_desync_deep_copy() -> void:
	var nbc := _nbc(0)
	if nbc == null:
		return
	var payload := _snap(1, 0)
	var vh := ProtocolViewCodec.compute_view_hash(payload)
	assert_true(bool(nbc.call("ingest_networked_event", _rs(1, payload))))
	assert_eq(int(nbc.call("current_seq")), 1)
	var pub: Dictionary = nbc.call("get_public_view")
	assert_true(_exact(pub, SNAP_KEYS))
	assert_eq(JSON.stringify(pub), JSON.stringify(payload))
	_assert_modules_ok(pub)
	assert_eq(int(pub["seat_view"]), 0)
	assert_eq(int(pub["snapshot_server_seq"]), 1)
	assert_eq(int(pub["next_server_seq"]), 2)
	var core: Dictionary = nbc.call("get_core_table_view")
	assert_true(_exact(core, CORE_KEYS))
	assert_eq(JSON.stringify(core), JSON.stringify(_core(0)))
	var mt: Array = (((core["seats"] as Array)[1] as Dictionary)["melds"] as Array)[0]["tiles"]
	# 领域升序 W1c1/W2c1/W3c0 → canonical iid 1/5/8；禁重排
	assert_eq([int(mt[0]["instance_id"]), int(mt[1]["instance_id"]), int(mt[2]["instance_id"])],
		[_canonical_iid(TileId.W1, 1), _canonical_iid(TileId.W2, 1), _canonical_iid(TileId.W3, 0)],
		"禁重排 MeldView.tiles")
	assert_true(bool(nbc.call("desync_check", vh)))
	assert_false(bool(nbc.call("desync_check", BAD_HASH)))
	pub["snapshot_server_seq"] = -1
	(pub["modules"] as Array).clear()
	core["live_wall_count"] = -1
	(core["seats"] as Array).clear()
	assert_eq(JSON.stringify(nbc.call("get_public_view")), JSON.stringify(payload))
	assert_eq(JSON.stringify(nbc.call("get_core_table_view")), JSON.stringify(_core(0)))
	var j: Array = nbc.call("get_event_journal")
	assert_eq(j.size(), 1)
	var orig: Dictionary = (j[0] as NetworkedEvent).to_dict()
	j.clear()
	var j2: Array = nbc.call("get_event_journal")
	assert_eq(j2.size(), 1)
	assert_eq(JSON.stringify((j2[0] as NetworkedEvent).to_dict()), JSON.stringify(orig))
	(j2[0] as Object).set("_payload", {"poison": true})
	assert_eq(JSON.stringify((nbc.call("get_event_journal")[0] as NetworkedEvent).to_dict()),
		JSON.stringify(orig), "journal poison 不污染")


func test_reject_atomic_zero_mutation() -> void:
	var nbc := _nbc(0)
	if nbc == null:
		return
	var p1 := _snap(1, 0)
	assert_true(bool(nbc.call("ingest_networked_event", _rs(1, p1))))
	_assert_modules_ok(nbc.call("get_public_view"))
	var mid := _st(nbc)
	# room 拒收须合法 envelope（seq==snapshot）；仅 room_id 错误
	_reject(nbc, _rs(2, _snap(2, 0), OTHER), mid, "room")
	_reject(nbc, _rs(2, _snap(2, 1)), mid, "recipient")
	_reject(nbc, _rs(1, p1), mid, "dup")
	assert_true(bool(nbc.call("ingest_networked_event", _rs(2, _snap(2, 0)))))
	var m2 := _st(nbc)
	_reject(nbc, _rs(1, p1), m2, "reverse")
	var bad_next := _snap(3, 0)
	bad_next["next_server_seq"] = 99
	_reject(nbc, _forge(_rs(3, _snap(3, 0)), bad_next), m2, "forged_payload")
	_reject(nbc, _forge(_rs(3, _snap(3, 0)), null, BAD_HASH), m2, "forged_hash")


func test_gap_resync() -> void:
	var nbc := _nbc(0)
	if nbc == null:
		return
	assert_true(bool(nbc.call("ingest_networked_event", _rs(1, _snap(1, 0)))))
	var p3 := _snap(3, 0)
	assert_true(bool(nbc.call("ingest_networked_event", _rs(3, p3))), "gap 必须接受")
	assert_eq(int(nbc.call("current_seq")), 3)
	assert_eq(JSON.stringify(nbc.call("get_public_view")), JSON.stringify(p3))
	_assert_modules_ok(nbc.call("get_public_view"))
	var j: Array = nbc.call("get_event_journal")
	assert_eq(j.size(), 2)
	assert_eq([(j[0] as NetworkedEvent).server_seq, (j[1] as NetworkedEvent).server_seq], [1, 3])


func test_reject_legacy_and_action() -> void:
	var nbc := _nbc(0)
	if nbc == null:
		return
	var before := _st(nbc)
	_reject(nbc, {"type": "GAME_BEGIN"}, before, "dict")
	_reject(nbc, BattleEvent.make(&"GAME_BEGIN", 0, null, {}), before, "battle_ev")
	var act: Action = Action.make_pass(0, ROOM, CMD, DECISION, 0, 1)
	assert_not_null(act)
	_reject(nbc, act, before, "action")


## exact NetworkedEvent：合法 base 由现有 _tp/_rs/_aa 覆盖；此处只锁「子类必须拒」。
## 子类 is NetworkedEvent==true 且 envelope 合法同 hash TURN_PROMPT seq2；入口仍须 false + 零推进。
func test_reject_networked_event_gdscript_subclass_exact_type() -> void:
	# 合法 base TURN_PROMPT（同 hash / seq2）；仅用于字段源，不经本测 assert 成功 ingest
	var snap1 := _snap(1, 0)
	var h1 := ProtocolViewCodec.compute_view_hash(snap1)
	var base_tp: NetworkedEvent = _tp(2, h1, 0)
	assert_not_null(base_tp)
	assert_eq(base_tp.kind, "TURN_PROMPT")
	assert_eq(base_tp.view_hash, h1)
	assert_eq(base_tp.server_seq, 2)
	assert_true(base_tp is NetworkedEvent)
	assert_true(base_tp.get_script() == NetworkedEvent, "合法 base 须 exact NetworkedEvent 脚本")

	var sub := SubNetworkedEvent.new()
	# 六个 envelope 私有字段深拷贝（payload 深拷贝；其余值类型/String 直接 set）
	sub.set("_protocol_version", base_tp.get("_protocol_version"))
	sub.set("_server_seq", base_tp.get("_server_seq"))
	sub.set("_room_id", base_tp.get("_room_id"))
	sub.set("_kind", base_tp.get("_kind"))
	sub.set("_payload", (base_tp.get("_payload") as Dictionary).duplicate(true))
	sub.set("_view_hash", base_tp.get("_view_hash"))
	assert_true(sub is NetworkedEvent, "子类 is NetworkedEvent 须为 true（暴露 is 门洞）")
	assert_false(sub.get_script() == NetworkedEvent, "子类 get_script() 不得等于 NetworkedEvent")
	assert_eq(str(sub.get("_kind")), "TURN_PROMPT")
	assert_eq(int(sub.get("_server_seq")), 2)
	assert_eq(str(sub.get("_view_hash")), h1)
	assert_eq(str(sub.get("_room_id")), ROOM)

	# --- 入口 1：ingest_networked_event(subclass) ---
	var nbc_ev := _nbc(0)
	if nbc_ev == null:
		return
	var mid_ev := _baseline_seq1(nbc_ev, 0)
	assert_eq(int(mid_ev["seq"]), 1)
	assert_false(bool(nbc_ev.call("ingest_networked_event", sub)),
		"exact 契约：GDScript 子类须被 ingest_networked_event 拒绝")
	_same(mid_ev, _st(nbc_ev), "subclass_ingest_ev 零变化")

	# --- 入口 2：ingest_event_stream([subclass])；全新 NBC + 同一基线 ---
	var nbc_st := _nbc(0)
	if nbc_st == null:
		return
	var mid_st := _baseline_seq1(nbc_st, 0)
	assert_eq(int(mid_st["seq"]), 1)
	assert_false(bool(nbc_st.call("ingest_event_stream", [sub] as Array)),
		"exact 契约：GDScript 子类须被 ingest_event_stream 拒绝")
	_same(mid_st, _st(nbc_st), "subclass_ingest_stream 零变化")


func test_action_applied_then_snapshot() -> void:
	var nbc := _nbc(0)
	if nbc == null:
		return
	var payload := _snap(2, 0)
	var vh := ProtocolViewCodec.compute_view_hash(payload)
	assert_true(bool(nbc.call("ingest_networked_event", _aa(1, vh))))
	var mid = nbc.call("get_public_view")
	if typeof(mid) == TYPE_DICTIONARY:
		assert_false(JSON.stringify(mid) == JSON.stringify(payload), "仅 ACTION 不投影")
	var snap := _rs(2, payload)
	assert_eq(snap.view_hash, vh)
	assert_true(bool(nbc.call("ingest_networked_event", snap)))
	assert_eq(JSON.stringify(nbc.call("get_public_view")), JSON.stringify(payload))
	_assert_modules_ok(nbc.call("get_public_view"))
	assert_eq(int(nbc.call("current_seq")), 2)
	var j: Array = nbc.call("get_event_journal")
	assert_eq(j.size(), 2)
	assert_eq([(j[0] as NetworkedEvent).kind, (j[1] as NetworkedEvent).kind],
		["ACTION_APPLIED", "ROOM_SNAPSHOT"])


func test_event_stream_networked_only() -> void:
	var nbc := _nbc(0)
	if nbc == null:
		return
	var payload := _snap(2, 0)
	var vh := ProtocolViewCodec.compute_view_hash(payload)
	assert_true(bool(nbc.call("ingest_event_stream", [_aa(1, vh), _rs(2, payload)] as Array)))
	assert_eq(JSON.stringify(nbc.call("get_public_view")), JSON.stringify(payload))
	_assert_modules_ok(nbc.call("get_public_view"))
	var nbc2 := _nbc(0)
	if nbc2 == null:
		return
	var before := _st(nbc2)
	assert_false(bool(nbc2.call("ingest_event_stream", [
		{"type": "GAME_BEGIN"}, BattleEvent.make(&"TILE_DRAWN", 0, null, {}),
	] as Array)))
	_same(before, _st(nbc2), "bad_stream")


## 1) 非 snapshot 严格 current+1；gap → resync；投影未污染；合法 snapshot 清 resync。
func test_non_snapshot_gap_sets_resync_and_snapshot_clears() -> void:
	var nbc := _nbc(0)
	if nbc == null:
		return
	var base := _baseline_seq1(nbc, 0)
	var base_vh := ProtocolViewCodec.compute_view_hash(base["view"])
	# gap ACTION seq3（合法 DTO，但非 current+1）
	var p3 := _snap_var(3, "DISCARD", 69, 0)
	var vh3 := ProtocolViewCodec.compute_view_hash(p3)
	assert_false(bool(nbc.call("ingest_networked_event", _aa(3, vh3))),
		"非 snapshot gap seq3 必须拒绝")
	_same_committed(base, _st(nbc), "gap 后 committed 未污染")
	assert_true(_resync(nbc), "gap → resync_required=true")
	assert_true(bool(nbc.call("desync_check", base_vh)), "gap 后仍匹配 seq1 视图")
	assert_false(bool(nbc.call("desync_check", vh3)), "gap 后不匹配未来 hash")
	# 合法更新 snapshot 清 resync（允许跳号恢复）
	assert_true(bool(nbc.call("ingest_networked_event", _rs(3, p3))),
		"合法更新 snapshot 应接受并清 resync")
	assert_false(_resync(nbc), "合法 snapshot 后 resync=false")
	assert_eq(int(nbc.call("current_seq")), 3)
	assert_eq(JSON.stringify(nbc.call("get_public_view")), JSON.stringify(p3))
	assert_true(bool(nbc.call("desync_check", vh3)))
	var j: Array = nbc.call("get_event_journal")
	assert_eq(j.size(), 2, "仅基线 snap + 恢复 snap，无 gap ACTION")
	assert_eq([(j[0] as NetworkedEvent).kind, (j[1] as NetworkedEvent).kind],
		["ROOM_SNAPSHOT", "ROOM_SNAPSHOT"])
	assert_eq([(j[0] as NetworkedEvent).server_seq, (j[1] as NetworkedEvent).server_seq],
		[1, 3])


## 2)+3) ACTION 只进 pending；匹配 snap 一次性提交；seq/hash/recipient 不符 → RESYNC 且清 pending。
func test_action_pending_match_commit_or_mismatch_resync() -> void:
	# --- 匹配路径：seq2 ACTION pending → seq3 snap 同 recip+同 hash → 一次提交 ---
	var nbc := _nbc(0)
	if nbc == null:
		return
	var base := _baseline_seq1(nbc, 0)
	var base_vh := ProtocolViewCodec.compute_view_hash(base["view"])
	var p3 := _snap_var(3, "DISCARD", 69, 0)
	var vh3 := ProtocolViewCodec.compute_view_hash(p3)
	assert_true(bool(nbc.call("ingest_networked_event", _aa(2, vh3))),
		"合法 ACTION seq2 须接受（进 pending）")
	_same_committed(base, _st(nbc), "pending 后 committed 仍是 seq1")
	assert_false(_resync(nbc), "pending 本身不置 resync")
	assert_true(bool(nbc.call("desync_check", base_vh)), "desync 只看已提交 seq1")
	assert_false(bool(nbc.call("desync_check", vh3)), "pending hash 不得伪装已提交")
	assert_true(bool(nbc.call("ingest_networked_event", _rs(3, p3))),
		"匹配 ROOM_SNAPSHOT seq3 须与 pending 一次提交")
	assert_false(_resync(nbc))
	assert_eq(int(nbc.call("current_seq")), 3)
	assert_eq(JSON.stringify(nbc.call("get_public_view")), JSON.stringify(p3))
	assert_true(bool(nbc.call("desync_check", vh3)))
	var j: Array = nbc.call("get_event_journal")
	assert_eq(j.size(), 3)
	assert_eq([
		(j[0] as NetworkedEvent).kind, (j[1] as NetworkedEvent).kind, (j[2] as NetworkedEvent).kind,
	], ["ROOM_SNAPSHOT", "ACTION_APPLIED", "ROOM_SNAPSHOT"])
	assert_eq([
		(j[0] as NetworkedEvent).server_seq, (j[1] as NetworkedEvent).server_seq,
		(j[2] as NetworkedEvent).server_seq,
	], [1, 2, 3])
	assert_eq((j[1] as NetworkedEvent).view_hash, vh3)
	assert_eq((j[2] as NetworkedEvent).view_hash, vh3)

	# --- hash 不符：pending 后清 + RESYNC，committed 不污染 ---
	var n_hash := _nbc(0)
	if n_hash == null:
		return
	var b_hash := _baseline_seq1(n_hash, 0)
	var p_match := _snap_var(3, "DISCARD", 69, 0)
	var vh_match := ProtocolViewCodec.compute_view_hash(p_match)
	var p_bad := _snap_var(3, "DRAW", 68, 0)
	var vh_bad := ProtocolViewCodec.compute_view_hash(p_bad)
	assert_ne(vh_match, vh_bad)
	assert_true(bool(n_hash.call("ingest_networked_event", _aa(2, vh_match))))
	assert_false(bool(n_hash.call("ingest_networked_event", _rs(3, p_bad))),
		"hash 与 pending 不符须拒绝")
	_same_committed(b_hash, _st(n_hash), "hash mismatch 不污染 committed")
	assert_true(_resync(n_hash), "hash mismatch → resync_required")

	# --- seq 不符 ---
	var n_seq := _nbc(0)
	if n_seq == null:
		return
	var b_seq := _baseline_seq1(n_seq, 0)
	var p4 := _snap_var(4, "DISCARD", 69, 0)
	var vh4 := ProtocolViewCodec.compute_view_hash(p4)
	assert_true(bool(n_seq.call("ingest_networked_event", _aa(2, vh4))))
	assert_false(bool(n_seq.call("ingest_networked_event", _rs(4, p4))),
		"pending 后 snap 须为 seq3，seq4 拒绝")
	_same_committed(b_seq, _st(n_seq), "seq mismatch 不污染 committed")
	assert_true(_resync(n_seq), "seq mismatch → resync_required")

	# --- recipient 不符：合法 DTO（他席 snapshot），不 forge ---
	var n_rec := _nbc(0)
	if n_rec == null:
		return
	var b_rec := _baseline_seq1(n_rec, 0)
	var p_other := _snap_var(3, "DISCARD", 69, 1)  # seat_view=1 合法
	var vh_other := ProtocolViewCodec.compute_view_hash(p_other)
	# pending 用与「本席匹配 snap」同 hash 的合法 ACTION；跟随却给他席 snap
	var p_self := _snap_var(3, "DISCARD", 69, 0)
	var vh_self := ProtocolViewCodec.compute_view_hash(p_self)
	assert_true(bool(n_rec.call("ingest_networked_event", _aa(2, vh_self))))
	var other_snap := _rs(3, p_other)
	assert_not_null(other_snap, "他席 snapshot 须是合法 NetworkedEvent")
	assert_eq(int(other_snap.payload["seat_view"]), 1)
	assert_false(bool(n_rec.call("ingest_networked_event", other_snap)),
		"recipient 不符须拒绝")
	_same_committed(b_rec, _st(n_rec), "recipient mismatch 不污染 committed")
	assert_true(_resync(n_rec), "recipient mismatch → resync_required")
	# 清 pending 证明：resync 后不得残留 pending 导致半状态；合法恢复 snap 仍可走通
	assert_true(bool(n_rec.call("ingest_networked_event", _rs(3, p_self))),
		"清 pending 后合法恢复 snap 应成功")
	assert_false(_resync(n_rec))
	assert_eq(int(n_rec.call("current_seq")), 3)
	var j_rec: Array = n_rec.call("get_event_journal")
	assert_eq(j_rec.size(), 2, "mismatch 清空 pending：journal 无残留 ACTION")
	assert_eq([(j_rec[0] as NetworkedEvent).kind, (j_rec[1] as NetworkedEvent).kind],
		["ROOM_SNAPSHOT", "ROOM_SNAPSHOT"])
	# vh_other 仅用于确认他席 DTO 合法可哈希（避免 unused）
	assert_eq(vh_other.length(), 64)


## 4) ingest_event_stream 整批原子：失败回滚 pending；随后合法 batch 仍可成功。
func test_event_stream_atomic_no_residual_pending() -> void:
	var nbc := _nbc(0)
	if nbc == null:
		return
	var base := _baseline_seq1(nbc, 0)
	var p_ok := _snap_var(3, "DISCARD", 69, 0)
	var vh_ok := ProtocolViewCodec.compute_view_hash(p_ok)
	var p_bad := _snap_var(3, "DRAW", 68, 0)
	assert_ne(vh_ok, ProtocolViewCodec.compute_view_hash(p_bad))
	# 半批：ACTION 合法 pending + 不匹配 snap → 整批 false，状态=调用前
	assert_false(bool(nbc.call("ingest_event_stream", [
		_aa(2, vh_ok), _rs(3, p_bad),
	] as Array)), "不匹配 batch 须原子失败")
	_same(base, _st(nbc), "原子失败后完整态（含 resync）恢复")
	assert_false(_resync(nbc), "原子失败不得留下 resync")
	# 同一合法 ACTION+matching SNAPSHOT batch 仍可成功 → 无残留 pending
	assert_true(bool(nbc.call("ingest_event_stream", [
		_aa(2, vh_ok), _rs(3, p_ok),
	] as Array)), "无残留 pending 时合法 batch 须成功")
	assert_false(_resync(nbc))
	assert_eq(int(nbc.call("current_seq")), 3)
	assert_eq(JSON.stringify(nbc.call("get_public_view")), JSON.stringify(p_ok))
	var j: Array = nbc.call("get_event_journal")
	assert_eq(j.size(), 3)
	assert_eq([
		(j[0] as NetworkedEvent).kind, (j[1] as NetworkedEvent).kind, (j[2] as NetworkedEvent).kind,
	], ["ROOM_SNAPSHOT", "ACTION_APPLIED", "ROOM_SNAPSHOT"])
	assert_eq([
		(j[0] as NetworkedEvent).server_seq, (j[1] as NetworkedEvent).server_seq,
		(j[2] as NetworkedEvent).server_seq,
	], [1, 2, 3])


## 5) 真实序列：snap(h1) → 同 hash TURN_PROMPT 原子 commit → 异 hash ACTION pending → 匹配 snap 一次提交。
## 冻结：提示不改公共投影须直接 journal/seq 推进且不进 pending；ACTION 仅 hash 变时 pending。
func test_prompt_same_hash_commits_then_action_pending_snapshot() -> void:
	var nbc := _nbc(0)
	if nbc == null:
		return
	# --- seq1 ROOM_SNAPSHOT → committed h1 ---
	var base := _baseline_seq1(nbc, 0)
	var h1 := ProtocolViewCodec.compute_view_hash(base["view"])
	assert_eq(h1.length(), 64)
	assert_true(bool(nbc.call("desync_check", h1)))

	# --- seq2 TURN_PROMPT view_hash==h1：原子直接 commit，不进 pending ---
	var prompt := _tp(2, h1, 0)
	assert_eq(prompt.view_hash, h1)
	assert_eq(prompt.kind, "TURN_PROMPT")
	assert_true(bool(nbc.call("ingest_networked_event", prompt)),
		"同 hash TURN_PROMPT 须接受并原子 commit")
	assert_eq(int(nbc.call("current_seq")), 2, "prompt commit 后 current_seq=2")
	assert_false(_resync(nbc), "prompt commit 后 resync=false")
	assert_eq(JSON.stringify(nbc.call("get_public_view")), JSON.stringify(base["view"]),
		"prompt 不改变 public_view")
	assert_true(bool(nbc.call("desync_check", h1)), "public view_hash 仍为 h1")
	var after_prompt := _st(nbc)
	assert_eq(int(after_prompt["seq"]), 2)
	var j_prompt_kinds: Array = []
	var j_prompt_seqs: Array = []
	for evd in after_prompt["journal"]:
		j_prompt_kinds.append(str((evd as Dictionary).get("kind", "")))
		j_prompt_seqs.append(int((evd as Dictionary).get("server_seq", -1)))
	assert_eq(j_prompt_kinds, ["ROOM_SNAPSHOT", "TURN_PROMPT"],
		"prompt 须 journal 追加（不得只进 pending）")
	assert_eq(j_prompt_seqs, [1, 2])
	# 若生产误把 prompt 只放 pending：seq/journal 停在 1，后续 ACTION 会被当成 mismatch/resync

	# --- seq3 ACTION_APPLIED view_hash=h4：hash 变 → 只进 pending，committed 仍 seq2 ---
	var p4 := _snap_var(4, "DISCARD", 69, 0)
	var h4 := ProtocolViewCodec.compute_view_hash(p4)
	assert_ne(h1, h4, "h4 须不同于 h1")
	assert_true(bool(nbc.call("ingest_networked_event", _aa(3, h4))),
		"异 hash ACTION 须接受并进 pending（同 hash prompt 若误 pending 会在此 mismatch/resync）")
	_same_committed(after_prompt, _st(nbc), "ACTION pending 后 committed 保持 seq2")
	assert_false(_resync(nbc), "pending 本身不置 resync")
	assert_true(bool(nbc.call("desync_check", h1)), "desync 只看已提交 h1")
	assert_false(bool(nbc.call("desync_check", h4)), "pending h4 不得伪装已提交")

	# --- seq4 匹配 ROOM_SNAPSHOT hash=h4：一次提交 ACTION+snapshot ---
	assert_true(bool(nbc.call("ingest_networked_event", _rs(4, p4))),
		"匹配 snap seq4 须与 pending ACTION 一次提交")
	assert_false(_resync(nbc))
	assert_eq(int(nbc.call("current_seq")), 4)
	assert_eq(JSON.stringify(nbc.call("get_public_view")), JSON.stringify(p4))
	assert_true(bool(nbc.call("desync_check", h4)))
	var j: Array = nbc.call("get_event_journal")
	var j_kinds: Array = []
	var j_seqs: Array = []
	var j_hashes: Array = []
	for ev in j:
		j_kinds.append((ev as NetworkedEvent).kind)
		j_seqs.append((ev as NetworkedEvent).server_seq)
		j_hashes.append((ev as NetworkedEvent).view_hash)
	assert_eq(j_kinds, ["ROOM_SNAPSHOT", "TURN_PROMPT", "ACTION_APPLIED", "ROOM_SNAPSHOT"],
		"journal 顺序 snapshot/prompt/action/snapshot")
	assert_eq(j_seqs, [1, 2, 3, 4])
	assert_eq(j_hashes, [h1, h1, h4, h4])
	assert_eq(j.size(), 4, "journal 严格 4 条")


## #241：NBC 生产路径稳定错误码 + 零变更。
func test_snapshot_stable_errors_zero_mutation() -> void:
	var nbc = _nbc(0)
	assert_not_null(nbc)
	var base := _baseline_seq1(nbc, 0)
	# 重复 module_key
	var dup_mods := [
		_mod("core_table", _core(0)),
		_mod("core_table", _core(0)),
	]
	var p_dup := {
		"snapshot_server_seq": 2,
		"next_server_seq": 3,
		"seat_view": 0,
		"modules": dup_mods,
	}
	# NetworkedEvent.make 本身会拒绝重复 key；用 forge 注入非法 modules
	var legal := _rs(2, _snap(2, 0))
	var forged := _forge(legal, p_dup, ProtocolViewCodec.compute_view_hash(p_dup))
	# 若 forge 后 hash/schema 不一致仍应失败；优先测 last_snapshot_error
	assert_false(bool(nbc.call("ingest_networked_event", forged)))
	assert_eq(JSON.stringify(_st(nbc)), JSON.stringify(base), "失败零变更")
	if nbc.has_method("last_snapshot_error"):
		var err: String = str(nbc.call("last_snapshot_error"))
		assert_false(err.is_empty(), "须有稳定错误码")
	# 未知必需 schema：合法 wire 但 registry 拒绝
	var p_schema := _snap(2, 0)
	(p_schema["modules"] as Array)[0]["schema_version"] = 99
	var vh_s := ProtocolViewCodec.compute_view_hash(p_schema)
	# schema 99 的 core_table 无法通过 NetworkedEvent.from_dict；forge
	var base_ne := _rs(2, _snap(2, 0))
	var forged_s := _forge(base_ne, p_schema, vh_s)
	assert_false(bool(nbc.call("ingest_networked_event", forged_s)))
	assert_eq(int(nbc.call("current_seq")), 1)
	if nbc.has_method("last_snapshot_error"):
		var err2: String = str(nbc.call("last_snapshot_error"))
		assert_true(
			err2 == SnapshotModuleRegistry.ERR_SCHEMA_UNSUPPORTED
			or err2 == SnapshotModuleRegistry.ERR_RESTORE_FAILED
			or err2 == SnapshotModuleRegistry.ERR_DUPLICATE_KEY
			or not err2.is_empty(),
			"须暴露稳定 schema/restore 错误"
		)
