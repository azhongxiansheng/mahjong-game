extends GutTest

# #244 round-4：跨通道 authority_seq — 真实 ACTION_APPLIED N + matching ROOM_SNAPSHOT N+1 + future side。
# 辅助构造对齐 test_networked_battle_controller 冻结 schema。

const ROOM := "room_bridge_r4"
const CMD := "550e8400-e29b-41d4-a716-446655440000"
const DECISION := "550e8400-e29b-41d4-a716-4466554400aa"
const SNAP_KEYS := ["snapshot_server_seq", "next_server_seq", "seat_view", "modules"]
const MOD_KEYS := ["module_key", "schema_version", "payload"]
const CORE_KEYS := [
	"recipient_seat", "hand_seq", "dealer_seat", "current_seat", "phase",
	"round_wind", "hand_number", "honba", "riichi_sticks", "live_wall_count",
	"dora_indicators", "viewer_next_draw", "seats",
]
const SEAT_KEYS := [
	"seat", "seat_wind", "score", "concealed_tiles", "concealed_count",
	"last_drawn_tile_instance_id", "river", "melds",
	"riichi_declared", "riichi_double", "riichi_discard_index",
]


func _exact(d: Dictionary, keys: Array) -> bool:
	if d.keys().size() != keys.size():
		return false
	for k in keys:
		if not d.has(k):
			return false
	return true


func _canonical_iid(tile_id: int, copy_index: int) -> int:
	var idx: int = TileId.ALL.find(tile_id)
	return idx * 4 + copy_index


func _tile(tile_id: int, copy_index: int, red := false) -> Dictionary:
	return {
		"instance_id": _canonical_iid(tile_id, copy_index),
		"tile_id": tile_id,
		"is_red_dora": red,
		"owner_seat": copy_index,
	}


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
		"seat": s,
		"seat_wind": [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N][s],
		"score": 25000,
		"concealed_tiles": tiles.duplicate(true),
		"concealed_count": n,
		"last_drawn_tile_instance_id": -1,
		"river": [],
		"melds": melds.duplicate(true),
		"riichi_declared": false,
		"riichi_double": false,
		"riichi_discard_index": -1,
	}
	assert_true(_exact(d, SEAT_KEYS))
	return d


func _core(recip := 0, phase: String = "DRAW", wall: int = 70) -> Dictionary:
	var own := _tile(TileId.E, recip)
	var seats: Array = []
	for s in range(4):
		seats.append(_seat(s, [own] if s == recip else [], 1 if s == recip else 13,
			[_chi_seat1()] if s == 1 else []))
	var p := {
		"recipient_seat": recip, "hand_seq": 0, "dealer_seat": 0, "current_seat": 0,
		"phase": phase, "round_wind": TileId.E, "hand_number": 1, "honba": 0,
		"riichi_sticks": 0, "live_wall_count": wall,
		"dora_indicators": [_tile(TileId.W5, 0, true)],
		"viewer_next_draw": {}, "seats": seats,
	}
	assert_true(_exact(p, CORE_KEYS))
	return p


func _mod(payload: Dictionary) -> Dictionary:
	var m := {"module_key": "core_table", "schema_version": 1, "payload": payload.duplicate(true)}
	assert_true(_exact(m, MOD_KEYS))
	return m


func _snap(seq: int, phase: String = "DRAW", wall: int = 70) -> Dictionary:
	var p := {
		"snapshot_server_seq": seq, "next_server_seq": seq + 1,
		"seat_view": 0, "modules": [_mod(_core(0, phase, wall))],
	}
	assert_true(_exact(p, SNAP_KEYS))
	return p


func _rs(seq: int, phase: String = "DRAW", wall: int = 70) -> NetworkedEvent:
	var p := _snap(seq, phase, wall)
	var h := ProtocolViewCodec.compute_view_hash(p)
	var ne := NetworkedEvent.make("ROOM_SNAPSHOT", seq, ROOM, p, h)
	assert_not_null(ne)
	return ne


func _aa(seq: int, vh: String) -> NetworkedEvent:
	var p := {
		"causation_command_id": CMD, "hand_seq": 0, "decision_id": DECISION,
		"seat": 0, "action_kind": "PASS", "resolved_payload": {},
	}
	var ne := NetworkedEvent.make("ACTION_APPLIED", seq, ROOM, p, vh)
	assert_not_null(ne)
	return ne


func _baseline() -> Dictionary:
	var nbc := NetworkedBattleController.new(ROOM, 0)
	var b := AuthoritySeqBridge.new()
	b.bind_networked_controller(nbc)
	var snap1 := _rs(1, "DRAW", 70)
	assert_true(bool(b.on_game_networked_event(snap1).get("ok", false)))
	assert_eq(nbc.current_seq(), 1)
	return {"nbc": nbc, "bridge": b, "vh1": snap1.view_hash}


func test_side_n2_before_game_n_and_matching_snapshot() -> void:
	var ctx: Dictionary = _baseline()
	var nbc: NetworkedBattleController = ctx["nbc"]
	var b: AuthoritySeqBridge = ctx["bridge"]
	var p3 := _snap(3, "DISCARD", 69)
	var vh3 := ProtocolViewCodec.compute_view_hash(p3)
	assert_ne(vh3, str(ctx["vh1"]))
	var aa2 := _aa(2, vh3)
	var snap3 := NetworkedEvent.make("ROOM_SNAPSHOT", 3, ROOM, p3, vh3)
	assert_not_null(snap3)
	# side 4 先到
	assert_eq(str(b.on_side_channel_authority_seq(4).get("reason", "")), "HELD_SIDE")
	assert_eq(b.held_side_count(), 1)
	# game N=2 → pending
	assert_true(bool(b.on_game_networked_event(aa2).get("ok", false)))
	assert_eq(nbc.current_seq(), 1)
	# matching snapshot N+1=3
	assert_true(bool(b.on_game_networked_event(snap3).get("ok", false)))
	# 提交 3 后 drain side 4
	assert_eq(nbc.current_seq(), 4, "须保留并 drain future side N+2")
	assert_eq(b.held_side_count(), 0)
	assert_false(nbc.resync_required())
	# game N+3=5 同 hash 直接 commit
	var aa5 := _aa(5, vh3)
	assert_true(bool(b.on_game_networked_event(aa5).get("ok", false)))
	assert_eq(nbc.current_seq(), 5)
	assert_false(nbc.resync_required())


func test_game_n_snapshot_then_side_n2() -> void:
	var ctx: Dictionary = _baseline()
	var nbc: NetworkedBattleController = ctx["nbc"]
	var b: AuthoritySeqBridge = ctx["bridge"]
	var p3 := _snap(3, "DISCARD", 68)
	var vh3 := ProtocolViewCodec.compute_view_hash(p3)
	assert_true(bool(b.on_game_networked_event(_aa(2, vh3)).get("ok", false)))
	assert_true(bool(b.on_game_networked_event(
		NetworkedEvent.make("ROOM_SNAPSHOT", 3, ROOM, p3, vh3)).get("ok", false)))
	assert_eq(nbc.current_seq(), 3)
	assert_true(bool(b.on_side_channel_authority_seq(4).get("ok", false)))
	assert_eq(nbc.current_seq(), 4)
	assert_false(nbc.resync_required())


func test_invalid_snapshot_preserves_future_side() -> void:
	var ctx: Dictionary = _baseline()
	var nbc: NetworkedBattleController = ctx["nbc"]
	var b: AuthoritySeqBridge = ctx["bridge"]
	assert_eq(str(b.on_side_channel_authority_seq(5).get("reason", "")), "HELD_SIDE")
	# 合法 make 后污染 seat_view，使 NBC 拒绝
	var bad := _rs(2, "DRAW", 70)
	var payload: Dictionary = bad.payload.duplicate(true)
	payload["seat_view"] = 9
	bad.set("_payload", payload)
	var r: Dictionary = b.on_game_networked_event(bad)
	assert_false(bool(r.get("ok", false)))
	assert_eq(str(r.get("reason", "")), "SNAPSHOT_REJECTED")
	assert_eq(b.held_side_count(), 1)
	assert_eq(nbc.current_seq(), 1)


func test_timeout_missing_game_still_resync() -> void:
	var ctx: Dictionary = _baseline()
	var nbc: NetworkedBattleController = ctx["nbc"]
	var b: AuthoritySeqBridge = ctx["bridge"]
	b.set_hold_window_ms(40)
	b.set_clock_ms_for_test(1000)
	var vh := ProtocolViewCodec.compute_view_hash(_snap(5, "DRAW", 60))
	var hold: Dictionary = b.on_game_networked_event(_aa(5, vh))
	assert_eq(str(hold.get("reason", "")), "HELD_FOR_SIDE_CHANNEL")
	assert_eq(str(b.tick(1020).get("reason", "")), "WAITING")
	var done: Dictionary = b.tick(1100)
	assert_true(bool(done.get("resync", false)) or nbc.resync_required())
	assert_eq(b.held_game_count(), 0)


func test_explicit_clear_on_rebind() -> void:
	var ctx: Dictionary = _baseline()
	var b: AuthoritySeqBridge = ctx["bridge"]
	b.on_side_channel_authority_seq(9)
	assert_eq(b.held_side_count(), 1)
	b.bind_networked_controller(NetworkedBattleController.new(ROOM, 0))
	assert_eq(b.held_side_count(), 0)
	assert_eq(b.hold_deadline_ms(), -1)
