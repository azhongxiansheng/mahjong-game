extends GutTest

# 麻将王 — M8 端到端：章 3 半庄战 Boss 节点完整链路验证
#
# 验证：从 RunState 章 3 → ChapterMap → NodeRef.session_kind="hanchan"
# → BattleNodeRunner → GameDriver 8 局 → NodeResult 半庄翻倍 HP/Gold
# → 存档 v2 roundtrip 全链路打通。

const BOSS_ID := &"boss3_kanmon_v1"

# ---- 章 3 NodeRef 全部 hanchan ----

func test_chapter_3_run_state_all_nodes_hanchan():
	var rs := RunState.new(42)
	rs.chapter = 3
	rs._generate_chapter_map(3)
	for n in rs.current_map.nodes:
		assert_eq(n.session_kind, "hanchan",
			"章 3 节点 %d 必 hanchan" % n.index)

func test_chapter_3_boss_node_is_hanchan_and_kind_boss():
	var rs := RunState.new(42)
	rs._generate_chapter_map(3)
	var boss: NodeRef = rs.current_map.nodes[rs.current_map.boss_node]
	assert_eq(boss.kind, NodeKind.Kind.BOSS)
	assert_eq(boss.session_kind, "hanchan")

# ---- BattleNodeRunner 跑章 3 Boss 8 局 ----

func test_battle_node_runner_chapter_3_boss_runs_8_hands():
	# 签名: (seed, boss, abilities, heuristic, tile_variants, tiebreak_seed, ai_abilities_seed, session_kind)
	var stats: Dictionary = BattleNodeRunner.run_battle_with_stats(
		1234, BOSS_ID, [], false, {}, 0, 0, "hanchan"
	)
	assert_eq(int(stats.hand_count), 8,
		"章 3 hanchan Boss 应跑满 8 局（v1 SimpleAi 多流局，无连庄）")
	# 守恒
	var sum := 0
	for s in stats.final_scores:
		sum += int(s)
	assert_eq(sum, 100000, "Boss inject + 8 局后总分守恒")

func test_battle_node_runner_chapter_3_boss_node_result_is_hanchan():
	var nr: NodeResult = BattleNodeRunner.run_battle_to_node_result(
		1234, BOSS_ID, [], false, {}, 0, 0, "hanchan"
	)
	assert_eq(nr.session_kind, "hanchan", "NodeResult 透传 session_kind")
	# rank → hp_delta 应在半庄数组内
	var bc_hp: Array = BalanceConstants.get_node_rank_hp_delta("hanchan")
	assert_eq(nr.hp_delta, int(bc_hp[nr.rank - 1]),
		"rank %d hp_delta 与 hanchan 数组一致" % nr.rank)
	# 半庄 rank 4 应 -4 HP（vs east_round -2）
	if nr.rank == 4:
		assert_eq(nr.hp_delta, -4)
	if nr.rank == 1:
		assert_eq(nr.gold_reward, 60)

# ---- 存档 v2 roundtrip 含 hanchan NodeRef ----

func test_run_state_with_chapter_3_map_save_load_roundtrip():
	var rs := RunState.new(42)
	rs._generate_chapter_map(3)
	rs.chapter = 3
	rs.gold = 250
	rs.hp = 4
	# 模拟访问 1 个章 3 节点
	rs.history.append(rs.current_map.nodes[0])

	var d: Dictionary = rs.to_dict()
	assert_eq(int(d.version), 2, "v2 写出")

	var rs2: RunState = RunState.from_dict(d)
	assert_not_null(rs2)
	assert_eq(rs2.chapter, 3)
	assert_eq(rs2.history.size(), 1)
	assert_eq(rs2.history[0].session_kind, "hanchan",
		"章 3 history NodeRef session_kind hanchan")
	# 章 3 map 全 hanchan
	for n in rs2.current_map.nodes:
		assert_eq(n.session_kind, "hanchan",
			"v2 重载后章 3 map 节点 %d 仍 hanchan" % n.index)

# ---- M7 → M8 升级路径：v1 存档加载到章 3 后下一个节点仍正常 ----

func test_v1_save_load_into_chapter_3_then_next_node_is_hanchan():
	# 模拟用户在 M7 存档（v1，无 session_kind 字段），升级到 M8 后
	# 加载存档，进入下一节点。下一章应按当前代码（M8）的章配置走。
	var v1_dict := {
		"version": 1,
		"hp": 5,
		"max_hp": 5,
		"gold": 0,
		"chapter": 2,
		"run_seed": 42,
		"current_map": null,
		"history": [],
		"deck": {},
		"player_deck": {},
		"pity_state": {},
		"consumables": [],
		"finished": false,
		"won": false,
	}
	var rs: RunState = RunState.from_dict(v1_dict)
	assert_not_null(rs, "M7 v1 存档应被接受")
	# 用户在章 2 推进；章 3 进入由 RunState.complete_node 触发
	# 这里简化：直接 _generate_chapter_map(3) 模拟跨章
	rs._generate_chapter_map(3)
	for n in rs.current_map.nodes:
		assert_eq(n.session_kind, "hanchan",
			"v1 存档加载后进入章 3 → 节点仍按 M8 章 3 配置生成 hanchan")
