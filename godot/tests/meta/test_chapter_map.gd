extends GutTest

# 麻将王 — M4 第 1 步：ChapterMap + ChapterMapGenerator 单测
# 覆盖：节点图生成的硬约束（plan-4 D2）、连通性、必有节点位置。

# ---- 单元：ChapterMap.next_options / advance_to ----

func test_next_options_at_entry_returns_entry_node():
	var m := ChapterMap.new()
	m.nodes = [NodeRef.new(0, 0, NodeKind.Kind.NORMAL), NodeRef.new(1, 1, NodeKind.Kind.NORMAL)]
	m.edges = [[1], []]
	m.entry_node = 0
	m.boss_node = 1
	m.current_node = -1
	assert_eq(m.next_options(), [0])

func test_advance_to_valid():
	var m := ChapterMap.new()
	m.nodes = [NodeRef.new(0, 0, NodeKind.Kind.NORMAL), NodeRef.new(1, 1, NodeKind.Kind.NORMAL)]
	m.edges = [[1], []]
	m.entry_node = 0
	m.boss_node = 1
	m.current_node = -1
	assert_true(m.advance_to(0))
	assert_eq(m.current_node, 0)

func test_advance_to_invalid_keeps_state():
	var m := ChapterMap.new()
	m.nodes = [NodeRef.new(0, 0, NodeKind.Kind.NORMAL), NodeRef.new(1, 1, NodeKind.Kind.NORMAL)]
	m.edges = [[1], []]
	m.entry_node = 0
	m.boss_node = 1
	m.current_node = -1
	assert_false(m.advance_to(99), "非法 index 应拒绝")
	assert_eq(m.current_node, -1, "状态不应变")

# ---- 集成：Generator 生成的图通过约束 ----

func _gen_chapter_1(seed: int = 42) -> ChapterMap:
	return ChapterMapGenerator.generate(ChapterConfig.chapter_1(), seed)

func test_generated_map_is_connected():
	for seed in [1, 7, 42, 123, 999]:
		var m := _gen_chapter_1(seed)
		assert_true(m.has_path_to_boss(), "seed=%d 入口到 Boss 应连通" % seed)

func test_generated_map_all_nodes_reachable():
	for seed in [1, 7, 42, 123, 999]:
		var m := _gen_chapter_1(seed)
		assert_true(m.all_nodes_reachable_from_entry(),
			"seed=%d 不应有孤儿节点" % seed)

func test_floor_zero_is_normal_entry():
	var m := _gen_chapter_1(42)
	var entry: NodeRef = m.nodes[m.entry_node]
	assert_eq(entry.floor_index, 0, "入口在 floor 0")
	assert_eq(entry.kind, NodeKind.Kind.NORMAL, "入口必为 NORMAL")

func test_boss_floor_is_last_and_has_one_boss():
	var m := _gen_chapter_1(42)
	var boss: NodeRef = m.nodes[m.boss_node]
	var floor_count: int = int(ChapterConfig.chapter_1().floor_count)
	assert_eq(boss.floor_index, floor_count - 1, "Boss 在最后一层")
	assert_eq(boss.kind, NodeKind.Kind.BOSS)

func test_boss_previous_floor_all_camp():
	var m := _gen_chapter_1(42)
	var floor_count: int = int(ChapterConfig.chapter_1().floor_count)
	var pre_boss_floor: int = floor_count - 2
	for n in m.nodes:
		if n.floor_index == pre_boss_floor:
			assert_eq(n.kind, NodeKind.Kind.CAMP,
				"Boss 前一层节点 %d 应为营地" % n.index)

func test_node_count_within_bounds():
	# floor_count=7，nodes_per_floor=(1,3)；entry=1, boss=1, pre_boss=1，
	# 中间 4 floor 各 1-3。总数 ∈ [3+4=7, 3+12=15]
	var m := _gen_chapter_1(42)
	assert_gte(m.node_count(), 7)
	assert_lte(m.node_count(), 15)

func test_seed_determinism():
	var m1 := _gen_chapter_1(42)
	var m2 := _gen_chapter_1(42)
	assert_eq(m1.node_count(), m2.node_count())
	for i in range(m1.node_count()):
		assert_eq(m1.nodes[i].kind, m2.nodes[i].kind)
		assert_eq(m1.nodes[i].floor_index, m2.nodes[i].floor_index)

# ---- 章 2 / 章 3 配置 ----

func test_chapter_2_floor_count_is_8():
	var m := ChapterMapGenerator.generate(ChapterConfig.chapter_2(), 42)
	var c: NodeRef = m.nodes[m.boss_node]
	assert_eq(c.floor_index, 7)
	assert_true(m.has_path_to_boss())

func test_chapter_3_more_elite_nodes():
	# 章 3 ELITE 权重 0.30，比章 1 (0.15) 高；多 seed 平均后应有更多 ELITE。
	var c1_elites := _count_kind_avg_over_seeds(ChapterConfig.chapter_1(), NodeKind.Kind.ELITE)
	var c3_elites := _count_kind_avg_over_seeds(ChapterConfig.chapter_3(), NodeKind.Kind.ELITE)
	assert_gt(c3_elites, c1_elites, "章 3 平均 ELITE 数应多于章 1")

func _count_kind_avg_over_seeds(config: Dictionary, kind: int) -> float:
	var total := 0
	var seeds := [1, 7, 42, 123, 999, 314, 271, 161]
	for s in seeds:
		var m := ChapterMapGenerator.generate(config, s)
		for n in m.nodes:
			if n.kind == kind:
				total += 1
	return float(total) / float(seeds.size())

# ---- ChapterConfig.get_chapter 哨兵 ----

func test_get_chapter_invalid_returns_empty():
	assert_eq(ChapterConfig.get_chapter(0), {})
	assert_eq(ChapterConfig.get_chapter(4), {})
	assert_eq(ChapterConfig.chapter_count(), 3)
