extends GutTest

# 麻将王 — M10 net foundation: BattleEvent / TileSkillAnchor 序列化 + 决定性 smoke test
#
# spec §4.3 Phase 2 联机：所有对局副作用走 event bus → 事件能序列化 + 回放
# 是 "server 权威 + client 重放" 架构的硬前提。本测试锁住三件事：
# 1. BattleEvent / TileSkillAnchor roundtrip 不丢字段
# 2. 同 seed 跑两次 BattleController.run_to_end() 产生 byte-identical 事件序列
# 3. 序列化后的 dict 是 JSON 友好的（无 GDScript 专属对象）

# ---- TileSkillAnchor roundtrip ----

func test_tile_instance_roundtrip_preserves_all_fields():
	var t := Tile.new(TileId.W5, true, 2)
	var ti := TileSkillAnchor.make(t, 3)
	ti.holder_seat = 1
	var d: Dictionary = ti.to_dict()
	var ti2: TileSkillAnchor = TileSkillAnchor.from_dict(d)
	assert_eq(ti2.tile.id, TileId.W5)
	assert_true(ti2.tile.is_red_dora)
	assert_eq(ti2.tile.owner_seat, 2)
	assert_eq(ti2.owner_seat, 3)
	assert_eq(ti2.holder_seat, 1)

func test_tile_instance_to_dict_does_not_serialize_skill():
	var t := Tile.new(TileId.HAKU)
	var sk := SkillResource.new()
	sk.id = &"test_skill"
	var ti := TileSkillAnchor.make(t, 0, sk)
	var d: Dictionary = ti.to_dict()
	assert_false(d.has("skill"), "skill 不进 dict（server 权威下 client 反查）")

func test_tile_instance_from_dict_empty_returns_null():
	assert_null(TileSkillAnchor.from_dict({}))

# ---- BattleEvent roundtrip ----

func test_event_roundtrip_simple():
	var ev := BattleEvent.make(&"TILE_DRAWN", 2)
	var d: Dictionary = ev.to_dict()
	var ev2: BattleEvent = BattleEvent.from_dict(d)
	assert_eq(String(ev2.type), "TILE_DRAWN")
	assert_eq(ev2.actor_seat, 2)
	assert_null(ev2.tile_anchor, "无 tile 时 from_dict 不重建 TileSkillAnchor")

func test_event_roundtrip_with_tile():
	# 赤宝仅 5m/5p/5s 合法；S7 用非赤 + 合法 instance_id
	var ti := TileSkillAnchor.make(Tile.new(TileId.S7, false, 1, 7), 1)
	var ev := BattleEvent.make(&"TILE_DISCARDED", 1, ti, {})
	var d: Dictionary = ev.to_dict()
	var ev2: BattleEvent = BattleEvent.from_dict(d)
	assert_not_null(ev2.tile_anchor)
	assert_eq(ev2.tile_anchor.tile.id, TileId.S7)
	assert_eq(ev2.tile_anchor.tile.owner_seat, 1)

func test_event_roundtrip_with_extra():
	var ev := BattleEvent.make(&"WIN_DECLARED", 0, null, {
		"payout": {1: 2000, 2: 2000, 3: 2000},
		"winner_total": 6000,
		"han": 3,
		"fu": 30,
	})
	var d: Dictionary = ev.to_dict()
	var ev2: BattleEvent = BattleEvent.from_dict(d)
	assert_eq(int(ev2.extra.get("winner_total", 0)), 6000)
	assert_eq(int(ev2.extra.get("han", 0)), 3)
	var payout: Dictionary = ev2.extra.payout
	assert_eq(int(payout[1]), 2000)

func test_event_roundtrip_with_chain_id():
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 1)
	ev.chain_id = 7
	var d: Dictionary = ev.to_dict()
	var ev2: BattleEvent = BattleEvent.from_dict(d)
	assert_eq(ev2.chain_id, 7)

# ---- JSON 友好性 ----

func test_event_dict_is_json_serializable():
	# spec §4.3 网络层将走 JSON / msgpack；BattleEvent.to_dict 不应含 Object 引用
	var ti := TileSkillAnchor.make(Tile.new(TileId.W3), 0)
	var ev := BattleEvent.make(&"TILE_DRAWN", 0, ti, {"k": "v"})
	var d: Dictionary = ev.to_dict()
	var json_str: String = JSON.stringify(d)
	var parsed: Variant = JSON.parse_string(json_str)
	assert_typeof(parsed, TYPE_DICTIONARY, "round-trip 通 JSON 不崩")

# ---- 决定性 smoke：同 seed → byte-identical 事件序列 ----
#
# 这是 spec §4.3 联机权威化的硬前提：server 跟 client 必须在同 seed 下
# 产生同事件序列，否则 replay 永远无法收敛。

func test_same_seed_produces_identical_event_sequence():
	# 跑两次同 seed 的 BattleController，比较 events 序列
	var bc1 := BattleController.new(42, 0, true)
	bc1.run_to_end()
	var bc2 := BattleController.new(42, 0, true)
	bc2.run_to_end()
	assert_eq(bc1.events.size(), bc2.events.size(), "事件数应一致")
	for i in range(mini(bc1.events.size(), bc2.events.size())):
		var a: BattleEvent = bc1.events[i]
		var b: BattleEvent = bc2.events[i]
		assert_eq(String(a.type), String(b.type), "event %d type 一致" % i)
		assert_eq(a.actor_seat, b.actor_seat, "event %d actor 一致" % i)
		# 比较 dict 全字段
		assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()),
			"event %d dict 一致 (type=%s)" % [i, String(a.type)])

func test_different_seeds_produce_different_event_sequences():
	# 反向锁：seed 不同时事件 stream 也应不同（保证 seed 真分支）
	var bc1 := BattleController.new(42, 0, true)
	bc1.run_to_end()
	var bc2 := BattleController.new(43, 0, true)
	bc2.run_to_end()
	# 事件总数或某个 actor_seat 序列至少应有差异
	var bc1_signature: Array = []
	for ev in bc1.events:
		bc1_signature.append([String(ev.type), ev.actor_seat])
	var bc2_signature: Array = []
	for ev in bc2.events:
		bc2_signature.append([String(ev.type), ev.actor_seat])
	assert_ne(JSON.stringify(bc1_signature), JSON.stringify(bc2_signature),
		"不同 seed 的事件序列应有差异（保证 seed 真在洗牌等环节分支）")
