extends GutTest

# 麻将王 — M5 第 2 步：各数据类 to_dict / from_dict roundtrip 单测

# ---- NodeRef ----

func test_node_ref_roundtrip():
	var n := NodeRef.new(5, 2, NodeKind.Kind.ELITE, {"hint": "demo"})
	var d: Dictionary = n.to_dict()
	var back := NodeRef.from_dict(d)
	assert_eq(back.index, 5)
	assert_eq(back.floor_index, 2)
	assert_eq(back.kind, NodeKind.Kind.ELITE)
	assert_eq(back.meta.get("hint"), "demo")

func test_node_ref_from_empty_returns_null():
	assert_null(NodeRef.from_dict({}))

# ---- NodeResult ----

func test_node_result_roundtrip():
	var r := NodeResult.new(3, [25000, 26000, 24000, 25000])
	var d: Dictionary = r.to_dict()
	var back := NodeResult.from_dict(d)
	assert_eq(back.rank, 3)
	assert_eq(back.hp_delta, -1)
	assert_eq(back.gold_reward, 5)
	assert_eq(back.final_scores, [25000, 26000, 24000, 25000])

# ---- PityState ----

func test_pity_state_roundtrip():
	var p := PityState.new()
	for i in range(5):
		p.record_draw(Rarity.Kind.COMMON)
	var back := PityState.from_dict(p.to_dict())
	assert_eq(back.node_single_no_epic_streak, 5)

# ---- TileVariant ----

func test_tile_variant_roundtrip():
	var v := TileVariant.new(&"thunder_5w_v1", TileId.W5, Rarity.Kind.UNCOMMON)
	v.display_name = "5万·闪电"
	v.description = "owner 自胡 +1 番"
	v.skill_resource_path = "res://skills/hooks/thunder_5w_hook.gd"
	var back := TileVariant.from_dict(v.to_dict())
	assert_eq(back.id, &"thunder_5w_v1")
	assert_eq(back.tile_id, TileId.W5)
	assert_eq(back.rarity, Rarity.Kind.UNCOMMON)
	assert_eq(back.display_name, "5万·闪电")
	assert_eq(back.description, "owner 自胡 +1 番")
	assert_eq(back.skill_resource_path, "res://skills/hooks/thunder_5w_hook.gd")

# ---- AbilityCard ----

func test_ability_card_roundtrip():
	var a := AbilityCard.new(&"seabed_hunter_v1", Rarity.Kind.LEGENDARY)
	a.display_name = "海底狩人"
	var back := AbilityCard.from_dict(a.to_dict())
	assert_eq(back.id, &"seabed_hunter_v1")
	assert_eq(back.rarity, Rarity.Kind.LEGENDARY)
	assert_eq(back.display_name, "海底狩人")

# ---- Deck ----

func test_deck_roundtrip_with_tiles_and_abilities():
	var d := Deck.new()
	var v1 := TileVariant.new(&"v1", TileId.W5, Rarity.Kind.UNCOMMON)
	v1.display_name = "闪电"
	d.add_tile_variant(v1)
	var v2 := TileVariant.new(&"v2", TileId.T3, Rarity.Kind.COMMON)
	d.add_tile_variant(v2)
	var a := AbilityCard.new(&"a1", Rarity.Kind.EPIC)
	d.add_ability(a)

	var back := Deck.from_dict(d.to_dict())
	assert_eq(back.tile_variant_count(), 2)
	assert_true(back.has_tile_variant(TileId.W5))
	assert_true(back.has_tile_variant(TileId.T3))
	assert_eq(back.get_tile_variant(TileId.W5).display_name, "闪电")
	assert_eq(back.ability_count(), 1)
	assert_true(back.has_ability(&"a1"))

func test_deck_empty_roundtrip():
	var d := Deck.new()
	var back := Deck.from_dict(d.to_dict())
	assert_eq(back.tile_variant_count(), 0)
	assert_eq(back.ability_count(), 0)

# ---- ChapterMap ----

func test_chapter_map_roundtrip_preserves_topology():
	var m := ChapterMapGenerator.generate(ChapterConfig.chapter_1(), 42)
	# 模拟玩家推进一步
	m.advance_to(m.entry_node)
	var back := ChapterMap.from_dict(m.to_dict())
	assert_eq(back.node_count(), m.node_count())
	assert_eq(back.entry_node, m.entry_node)
	assert_eq(back.boss_node, m.boss_node)
	assert_eq(back.current_node, m.current_node)
	# 边表完整
	for i in range(m.edges.size()):
		assert_eq(back.edges[i], m.edges[i])

func test_chapter_map_roundtrip_preserves_node_kinds():
	var m := ChapterMapGenerator.generate(ChapterConfig.chapter_2(), 7)
	var back := ChapterMap.from_dict(m.to_dict())
	for i in range(m.nodes.size()):
		assert_eq(back.nodes[i].kind, m.nodes[i].kind)
		assert_eq(back.nodes[i].floor_index, m.nodes[i].floor_index)

# ---- RunState ----

func test_run_state_roundtrip_full():
	var rs := RunState.new(42)
	rs.gold = 100
	rs.hp = 3
	rs.chapter = 2
	rs.deck["pack_id"] = "starter_control"
	# 推进 + 模拟 history
	rs.choose_next_node(rs.current_map.entry_node)
	rs.history.append(NodeRef.new(0, 0, NodeKind.Kind.NORMAL))

	var back := RunState.from_dict(rs.to_dict())
	assert_not_null(back)
	assert_eq(back.run_seed, 42)
	assert_eq(back.gold, 100)
	assert_eq(back.hp, 3)
	assert_eq(back.chapter, 2)
	assert_eq(back.deck.get("pack_id"), "starter_control")
	assert_eq(back.history.size(), 1)
	assert_not_null(back.current_map)
	assert_eq(back.current_map.current_node, rs.current_map.current_node)

func test_run_state_version_mismatch_returns_null():
	var d: Dictionary = {"version": 99, "run_seed": 42}
	assert_null(RunState.from_dict(d), "未来版本不应被 v1 from_dict 接受")

func test_run_state_empty_dict_returns_null():
	assert_null(RunState.from_dict({}))
