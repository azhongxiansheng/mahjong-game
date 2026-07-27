extends GutTest

# E2-02 Red：RecipientViewProjector.static project_core_table → core_table exact-13。
# 无 server_seq/snapshot 包络；真实 BattleState。领域数组保序，禁 MeldView.tiles iid 重排。

const PATH := "res://server/recipient_view_projector.gd"
const SEED := 4242
const HAND_SEQ := 3
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
const FORBIDDEN := [
	"wall", "dead_wall", "hidden_uradora", "ura", "uradora",
	"decision", "intents", "state_hash", "full_state_hash",
	"visible_dora", "last_drawn", "opponent_hands",
]


func _project(state: Variant, seat: int) -> Variant:
	if not ResourceLoader.exists(PATH):
		assert_true(false, "缺 %s" % PATH)
		return null
	var s: GDScript = load(PATH) as GDScript
	assert_not_null(s)
	if s == null or not s.has_method("project_core_table"):
		assert_true(false, "须 static project_core_table")
		return null
	return s.call("project_core_table", state, seat)


func _exact(d: Dictionary, keys: Array) -> bool:
	if d.keys().size() != keys.size():
		return false
	for k in keys:
		if not d.has(k):
			return false
	return true


func _dict(v: Variant) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _forbidden(node: Variant) -> String:
	if typeof(node) == TYPE_DICTIONARY:
		for k in (node as Dictionary).keys():
			if str(k) in FORBIDDEN:
				return str(k)
			var h := _forbidden(node[k])
			if not h.is_empty():
				return h
	elif typeof(node) == TYPE_ARRAY:
		for item in node:
			var h2 := _forbidden(item)
			if not h2.is_empty():
				return h2
	return ""


func _tvs(tiles: Array) -> Array:
	var out: Array = []
	for t in tiles:
		out.append(ProtocolViewCodec.tile_view_from_tile(t))
	return out


func _iids(tiles: Array) -> Array:
	var out: Array = []
	for t in tiles:
		out.append(int(t.instance_id) if t is Tile else int((t as Dictionary)["instance_id"]))
	return out


## PON：本局 wall 真实实体；三张按 iid 降序入 meld（≠ iid 升序），证明 projector 不重排。
func _build_state() -> BattleState:
	var st: BattleState = BattleState.for_east_round(SEED, 0, 1, 0, 0, TileId.E, HAND_SEQ)
	assert_not_null(st)
	if st == null:
		return null
	# 故意 scores[i] ≠ seats[i].points：SeatView.score 以 state.scores 为准（#232 不统一两来源）
	st.scores = [30000, 24000, 22000, 24000] as Array[int]
	for i in range(4):
		st.seats[i].points = int(st.scores[i]) + 1111 * (i + 1)
		assert_ne(int(st.scores[i]), int(st.seats[i].points), "fixture scores≠points seat=%d" % i)
	var d0: Tile = st.seats[0].hand.tiles()[0]
	assert_true(st.seats[0].hand.take_by_instance_id(d0.instance_id) != null)
	st.seats[0].river.append_discard(d0)
	# 占用集合：当前 dora/ura + 已有 river，禁止拿进副露（可见实体全局唯一）
	var reserved: Dictionary = {}
	for t in st.dora_indicators.visible_tiles():
		reserved[int(t.instance_id)] = true
	for t in st.dora_indicators.uradora_tiles():
		reserved[int(t.instance_id)] = true
	for state_seat in st.seats:
		for rt in state_seat.river.tiles():
			reserved[int(rt.instance_id)] = true
	# 从 st.wall.authority_tiles() 按同 tile_id 取 3 张真实本局实体（禁 new Tile / 伪造 iid）
	var by_tid: Dictionary = {}
	for wt in st.wall.authority_tiles():
		if wt == null or not (wt is Tile):
			continue
		var cand: Tile = wt as Tile
		var iid: int = int(cand.instance_id)
		if reserved.has(iid):
			continue
		assert_true(Tile.is_instance_id_in_hand_seq(iid, HAND_SEQ), "wall 实体须落在 hand_seq 命名空间")
		var tid: int = int(cand.id)
		if not by_tid.has(tid):
			by_tid[tid] = []
		(by_tid[tid] as Array).append(cand)
	var picked: Array = []
	for tid_key in by_tid.keys():
		var pool: Array = by_tid[tid_key]
		if pool.size() >= 3:
			picked = [pool[0], pool[1], pool[2]]
			break
	assert_eq(picked.size(), 3, "须找到同 tile_id 的 3 张本局实体构造 PON")
	if picked.size() != 3:
		return null
	# 若实体在任意手牌中，按 instance_id 移除后再入 seat1 meld
	for pt in picked:
		var tile: Tile = pt as Tile
		for si in range(4):
			if st.seats[si].hand.find_by_instance_id(tile.instance_id) != null:
				var taken: Tile = st.seats[si].hand.take_by_instance_id(tile.instance_id)
				assert_not_null(taken)
				assert_eq(int(taken.instance_id), int(tile.instance_id))
				break
	# 三张按 instance_id 降序 → 领域序 ≠ iid 升序
	picked.sort_custom(func(a: Tile, b: Tile) -> bool:
		return int(a.instance_id) > int(b.instance_id)
	)
	var domain: Array[Tile] = [picked[0] as Tile, picked[1] as Tile, picked[2] as Tile]
	var domain_iids: Array = _iids(domain)
	var iid_asc: Array = domain_iids.duplicate()
	iid_asc.sort()
	assert_ne(JSON.stringify(domain_iids), JSON.stringify(iid_asc), "fixture 领域序≠iid 升序")
	assert_eq(int(domain[0].id), int(domain[1].id))
	assert_eq(int(domain[1].id), int(domain[2].id))
	# called 属于三张；from_seat 合法（≠ holder seat1）；集合分配 meld_id
	var called: Tile = domain[0]
	var from_seat: int = 0
	assert_ne(from_seat, 1, "PON from_seat 不得等于 holder")
	var pon: Meld = st.seats[1].melds.add_pon(domain, from_seat, called)
	assert_not_null(pon)
	assert_eq(pon.kind, Meld.Kind.PON)
	assert_eq(_iids(pon.tiles), domain_iids)
	assert_eq(int(pon.called_tile_instance_id), int(called.instance_id))
	assert_eq(int(pon.from_seat), from_seat)
	assert_true(Meld.is_valid_meld_id(pon.meld_id))
	if st.seats[0].hand.size() > 0:
		st.seats[0].last_drawn_instance_id = st.seats[0].hand.tiles()[0].instance_id
	if st.seats[2].hand.size() > 0:
		st.seats[2].last_drawn_instance_id = st.seats[2].hand.tiles()[0].instance_id
	var r3: Tile = st.seats[3].hand.tiles()[0]
	assert_true(st.seats[3].hand.take_by_instance_id(r3.instance_id) != null)
	st.seats[3].river.append_discard(r3)
	st.seats[3].riichi.declare(1, true)
	assert_true(st.seats[3].river.restore(st.seats[3].river.tiles(), 0))
	assert_true(st.wall.live_wall_size() > 0)
	assert_true(st.dora_indicators.visible_tiles().size() > 0)
	assert_true(st.dora_indicators.uradora_tiles().size() > 0)
	return st


func test_exists_and_api() -> void:
	assert_true(ResourceLoader.exists(PATH), "必须存在 %s" % PATH)
	if not ResourceLoader.exists(PATH):
		return
	var s: GDScript = load(PATH) as GDScript
	assert_not_null(s)
	assert_true(s.has_method("project_core_table"), "冻结 project_core_table")
	assert_false(s.has_method("project_room_snapshot"), "不再提供 project_room_snapshot")


func test_exact_schema_privacy_last_drawn() -> void:
	if not ResourceLoader.exists(PATH):
		assert_true(false, "缺 projector")
		return
	var st := _build_state()
	if st == null:
		return
	for recip in range(4):
		var v := _dict(_project(st, recip))
		assert_false(v.is_empty(), "recip=%d" % recip)
		if v.is_empty():
			return
		assert_true(_exact(v, CORE_KEYS), "core exact 13 recip=%d" % recip)
		assert_eq(int(v["recipient_seat"]), recip)
		assert_eq(int(v["hand_seq"]), HAND_SEQ)
		assert_eq(int(v["dealer_seat"]), st.dealer_seat)
		assert_eq(int(v["current_seat"]), st.current_seat)
		assert_eq(str(v["phase"]), BattlePhase.phase_name(st.phase))
		assert_eq(int(v["round_wind"]), st.round_wind)
		assert_eq(int(v["hand_number"]), st.hand_number)
		assert_eq(int(v["honba"]), st.honba)
		assert_eq(int(v["riichi_sticks"]), st.riichi_sticks)
		assert_eq(int(v["live_wall_count"]), st.wall.live_wall_size())
		var seats: Array = v["seats"]
		assert_eq(seats.size(), 4)
		for i in range(4):
			var sv: Dictionary = seats[i]
			assert_true(_exact(sv, SEAT_KEYS), "seat%d exact 11" % i)
			assert_eq(int(sv["seat"]), i)
			assert_eq(int(sv["score"]), int(st.scores[i]), "SeatView.score=state.scores[%d]" % i)
			assert_ne(int(st.scores[i]), int(st.seats[i].points), "两来源不同 seat=%d" % i)
			assert_eq(int(sv["seat_wind"]), int(st.seats[i].seat_wind))
			var n: int = st.seats[i].hand.size()
			assert_eq(int(sv["concealed_count"]), n)
			var ri = st.seats[i].riichi
			var dec: bool = ri.declared if ri else false
			var dbl: bool = ri.double_riichi if ri else false
			var ridx: int = st.seats[i].river.riichi_discard_index() if ri else -1
			assert_eq(bool(sv["riichi_declared"]), dec)
			assert_eq(bool(sv["riichi_double"]), dbl)
			assert_eq(int(sv["riichi_discard_index"]), ridx)
			if dbl:
				assert_true(bool(sv["riichi_declared"]))
			if not dec:
				assert_eq(int(sv["riichi_discard_index"]), -1)
			else:
				assert_true(ridx >= 0 and ridx < (sv["river"] as Array).size())
			if i == recip:
				var tiles: Array = sv["concealed_tiles"]
				assert_eq(tiles.size(), n)
				assert_eq(JSON.stringify(tiles), JSON.stringify(_tvs(st.seats[i].hand.tiles())))
				var ld: int = st.seats[i].last_drawn_instance_id
				var vld: int = int(sv["last_drawn_tile_instance_id"])
				if Tile.is_valid_instance_id(ld):
					assert_eq(vld, ld)
					assert_true(ld in _iids(tiles))
				else:
					assert_eq(vld, -1)
			else:
				assert_eq((sv["concealed_tiles"] as Array).size(), 0)
				assert_eq(int(sv["last_drawn_tile_instance_id"]), -1)


func test_public_order_codec_riichi_no_leak() -> void:
	if not ResourceLoader.exists(PATH):
		assert_true(false, "缺 projector")
		return
	var st := _build_state()
	if st == null:
		return
	var v := _dict(_project(st, 0))
	assert_false(v.is_empty())
	if v.is_empty():
		return
	assert_eq(JSON.stringify(v["dora_indicators"]),
		JSON.stringify(_tvs(st.dora_indicators.visible_tiles())), "dora 保序")
	for d in v["dora_indicators"]:
		assert_not_null(ProtocolViewCodec.tile_view_from_dict(d))
	var s0: Dictionary = (v["seats"] as Array)[0]
	assert_eq(JSON.stringify((s0["river"] as Array)[0]),
		JSON.stringify(ProtocolViewCodec.tile_view_from_tile(st.seats[0].river.tiles()[0])))
	# MeldView.tiles 严格保持领域 meld.tiles 顺序；不得按 iid 排序
	var dm: Meld = st.seats[1].melds.all()[0]
	var domain_iids := _iids(dm.tiles)
	var iid_asc := domain_iids.duplicate()
	iid_asc.sort()
	assert_ne(JSON.stringify(domain_iids), JSON.stringify(iid_asc), "fixture 领域序≠iid 序")
	var mv: Dictionary = (((v["seats"] as Array)[1] as Dictionary)["melds"] as Array)[0]
	assert_eq(_iids(mv["tiles"]), domain_iids, "MeldView.tiles 保持领域顺序，禁 iid 排序")
	# 不用 meld_view_from_meld（其当前会错误重排）
	assert_eq(JSON.stringify(mv["tiles"]), JSON.stringify(_tvs(dm.tiles)))
	assert_eq(int(mv["called_tile_instance_id"]), dm.called_tile_instance_id)
	assert_eq(str(mv["kind"]), "PON")
	var s3: Dictionary = (v["seats"] as Array)[3]
	assert_true(bool(s3["riichi_declared"]) and bool(s3["riichi_double"]))
	assert_eq(int(s3["riichi_discard_index"]), 0)
	assert_eq((s3["river"] as Array).size(), 1)
	assert_eq(_forbidden(v), "", "无私有泄露")
	var own: Array = s0["concealed_tiles"]
	var other := _dict(_project(st, 1))
	for s in range(4):
		for ct in ((other["seats"] as Array)[s] as Dictionary)["concealed_tiles"]:
			for ot in own:
				assert_ne(int((ct as Dictionary).get("instance_id", -3)),
					int((ot as Dictionary).get("instance_id", -2)))


func test_authorized_reveal_uses_existing_concealed_tiles_without_cross_seat_leak() -> void:
	var st := _build_state()
	if st == null:
		return
	var target_tile: Tile = st.seats[1].hand.first()
	var instance := TileSkillAnchor.make(target_tile, 1)
	instance.holder_seat = 1
	st.revealed_tiles = [{"tile": instance, "visible_to": [0]}]
	var owner_view := _dict(_project(st, 0))
	var revealed: Array = ((owner_view.seats as Array)[1] as Dictionary).concealed_tiles
	assert_eq(revealed.size(), 1)
	assert_eq(int((revealed[0] as Dictionary).instance_id), target_tile.instance_id)
	var other_view := _dict(_project(st, 2))
	assert_true((((other_view.seats as Array)[1] as Dictionary).concealed_tiles as Array).is_empty(),
		"无权限 recipient 不得收到林夜彻私有牌")
	var payload := {
		"snapshot_server_seq": 1,
		"next_server_seq": 2,
		"seat_view": 0,
		"modules": [{
			"module_key": "core_table",
			"schema_version": 1,
			"payload": owner_view,
		}],
	}
	var wire := {
		"protocol_version": 1,
		"server_seq": 1,
		"room_id": "room_reveal",
		"kind": "ROOM_SNAPSHOT",
		"payload": payload,
		"view_hash": ProtocolViewCodec.compute_view_hash(payload),
	}
	assert_not_null(NetworkedEvent.from_dict(wire),
		"授权 reveal 投影必须能通过真实 ROOM_SNAPSHOT wire validator")


func test_bai_touli_real_hook_projects_two_per_opponent_only_to_owner() -> void:
	var st := BattleState.for_east_round(341, 0, 1, 0, 0)
	var registry := SkillRegistry.new()
	var scheduler := SkillScheduler.new(registry, st)
	assert_true(BossAbilityFactory.inject(
		registry, &"char_washizu_passive_v1", 0))
	var ctx := scheduler.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	assert_eq(ctx.triggered_skills.size(), 1)
	var owner_view := _dict(_project(st, 0))
	for holder in [1, 2, 3]:
		assert_eq((((owner_view.seats as Array)[holder] as Dictionary).concealed_tiles as Array).size(), 2)
	var unauthorized_view := _dict(_project(st, 2))
	for holder in [0, 1, 3]:
		assert_true(((((unauthorized_view.seats as Array)[holder] as Dictionary).concealed_tiles) as Array).is_empty(),
			"未授权 recipient 不得看到 seat %d 的白透璃揭示" % holder)


func test_an_cheng_next_draw_projects_only_to_owner_and_expires_after_draw() -> void:
	var st := BattleState.for_east_round(344, 0, 1, 0, 0)
	var registry := SkillRegistry.new()
	var scheduler := SkillScheduler.new(registry, st)
	assert_true(BossAbilityFactory.inject(registry, &"char_awai_passive_v1", 0))
	var expected: Tile = st.wall.peek_next_draw()
	var ctx := scheduler.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	assert_eq(ctx.triggered_skills.size(), 1)
	var owner_view := _dict(_project(st, 0))
	assert_true(owner_view.has("viewer_next_draw"))
	assert_eq(int((owner_view.viewer_next_draw as Dictionary).instance_id), expected.instance_id)
	var other_view := _dict(_project(st, 1))
	assert_true((other_view.viewer_next_draw as Dictionary).is_empty(),
		"未授权 recipient 不得收到墙顶牌身份")
	assert_eq(st.wall.draw().instance_id, expected.instance_id)
	var expired_view := _dict(_project(st, 0))
	assert_true((expired_view.viewer_next_draw as Dictionary).is_empty(),
		"目标牌被摸走后预知必须失效")


func test_deep_copy_and_invalid() -> void:
	if not ResourceLoader.exists(PATH):
		assert_true(false, "缺 projector")
		return
	var st := _build_state()
	if st == null:
		return
	var wall_n: int = st.wall.live_wall_size()
	var hand_n: int = st.seats[0].hand.size()
	var ura_n: int = st.dora_indicators.uradora_tiles().size()
	var v1 := _dict(_project(st, 0))
	assert_false(v1.is_empty())
	if v1.is_empty():
		return
	var snap := JSON.stringify(v1)
	v1["live_wall_count"] = -99
	((v1["seats"] as Array)[0] as Dictionary)["concealed_count"] = 0
	((v1["seats"] as Array)[0] as Dictionary)["concealed_tiles"].clear()
	(v1["dora_indicators"] as Array).clear()
	assert_eq(st.wall.live_wall_size(), wall_n)
	assert_eq(st.seats[0].hand.size(), hand_n)
	assert_eq(st.dora_indicators.uradora_tiles().size(), ura_n)
	assert_eq(JSON.stringify(_dict(_project(st, 0))), snap)
	assert_null(_project(null, 0))
	assert_null(_project(st, -1))
	assert_null(_project(st, 4))
	assert_null(_project(RefCounted.new(), 0))


## 合法投影：PON fixture 使用本局 wall 实体（hand_seq 命名空间）；组装 ROOM_SNAPSHOT 后
## NetworkedEvent.from_dict 必须接受（原 out-of-namespace 伪造 iid 已移除）。
func test_projection_room_snapshot_rejects_out_of_namespace_fixture_red() -> void:
	var st := _build_state()
	if st == null:
		return
	var core: Variant = _project(st, 0)
	var payload := {
		"snapshot_server_seq": 1,
		"next_server_seq": 2,
		"seat_view": 0,
		"modules": [{
			"module_key": "core_table",
			"schema_version": 1,
			"payload": core,
		}],
	}
	var vh: String = ProtocolViewCodec.compute_view_hash(payload)
	var wire := {
		"protocol_version": 1,
		"server_seq": 1,
		"room_id": "room_x",
		"kind": "ROOM_SNAPSHOT",
		"payload": payload,
		"view_hash": vh,
	}
	assert_not_null(NetworkedEvent.from_dict(wire), "projector 输出必须是合法 ROOM_SNAPSHOT")
