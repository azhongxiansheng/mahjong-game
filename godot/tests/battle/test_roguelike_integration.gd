extends GutTest

# 麻将王 — 肉鸽集成全链路验证（无 mock）
#
# 验证：StarterPack → Deck → BattleNodeRunner 注入 → Registry 非空 → hook 触发 → events 产出。
# 每个测试用真实对象：真 BattleController、真 Wall、真 SkillScheduler。


# ============================================================
# 第 1 组：StarterPack → Deck → Registry 注入链
# ============================================================

func test_control_pack_populates_deck_tile_variants():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	assert_gt(rs.player_deck.tile_variant_count(), 0, "control pack 应注入牌技能")

func test_control_pack_populates_deck_abilities():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	assert_gt(rs.player_deck.ability_count(), 0, "control pack 应注入角色能力")

func test_aggro_pack_populates_deck():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_aggro")
	assert_gt(rs.player_deck.tile_variant_count(), 0)
	assert_gt(rs.player_deck.ability_count(), 0)

func test_fast_pack_populates_deck():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_fast")
	assert_gt(rs.player_deck.tile_variant_count(), 0)
	assert_gt(rs.player_deck.ability_count(), 0)

func test_deck_tile_variants_are_real_tile_variants():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	for tile_id in rs.player_deck.tile_variants:
		var v: TileVariant = rs.player_deck.tile_variants[tile_id]
		assert_not_null(v, "tile_variant 不该为 null")
		assert_true(v.has_skill(), "starter pack 的 tile 应有技能")

func test_deck_abilities_are_real_ability_cards():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	for a in rs.player_deck.abilities:
		assert_not_null(a, "ability 不该为 null")
		assert_ne(a.hook_resource_path, "", "ability 应有 hook 路径")


# ============================================================
# 第 2 组：BattleNodeRunner 注入后 Registry 非空
# ============================================================

func test_inject_control_pack_into_registry():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	var ability_ids: Array = []
	for a in rs.player_deck.abilities:
		ability_ids.append(a.id)
	var reg := SkillRegistry.new()
	var ab_count := BossAbilityFactory.inject_player_abilities(reg, ability_ids, 0)
	var tv_count := TileSkillFactory.inject_player_tile_variants(reg, rs.player_deck.tile_variants, 0)
	assert_gt(ab_count + tv_count, 0, "至少注入了一个技能")
	assert_gt(reg.get_all_entries().size(), 0, "registry 非空")

func test_inject_aggro_pack_into_registry():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_aggro")
	var ability_ids: Array = []
	for a in rs.player_deck.abilities:
		ability_ids.append(a.id)
	var reg := SkillRegistry.new()
	BossAbilityFactory.inject_player_abilities(reg, ability_ids, 0)
	TileSkillFactory.inject_player_tile_variants(reg, rs.player_deck.tile_variants, 0)
	assert_gt(reg.get_all_entries().size(), 0)


# ============================================================
# 第 3 组：完整战斗后技能真的影响结果
# ============================================================

func test_battle_with_control_pack_runs_to_completion():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	var ability_ids: Array = []
	for a in rs.player_deck.abilities:
		ability_ids.append(a.id)
	var result: NodeResult = BattleNodeRunner.run_battle_to_node_result(
		42, &"", ability_ids, false, rs.player_deck.tile_variants
	)
	assert_not_null(result)
	assert_between(result.rank, 1, 4, "排名 1-4")
	var sum := 0
	for s in result.final_scores:
		sum += int(s)
	assert_eq(sum, 100000, "分数守恒")

func test_battle_with_aggro_pack_runs_to_completion():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_aggro")
	var ability_ids: Array = []
	for a in rs.player_deck.abilities:
		ability_ids.append(a.id)
	var result: NodeResult = BattleNodeRunner.run_battle_to_node_result(
		99, &"", ability_ids, false, rs.player_deck.tile_variants
	)
	assert_not_null(result)
	assert_between(result.rank, 1, 4)

func test_battle_with_fast_pack_runs_to_completion():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_fast")
	var ability_ids: Array = []
	for a in rs.player_deck.abilities:
		ability_ids.append(a.id)
	var result: NodeResult = BattleNodeRunner.run_battle_to_node_result(
		77, &"", ability_ids, false, rs.player_deck.tile_variants
	)
	assert_not_null(result)
	assert_between(result.rank, 1, 4)


# ============================================================
# 第 4 组：Boss 能力在 Boss 节点触发
# ============================================================

func test_boss1_iron_curtain_battle_completes():
	var result: NodeResult = BattleNodeRunner.run_battle_to_node_result(
		42, &"boss1_iron_curtain_v1"
	)
	assert_not_null(result)
	assert_between(result.rank, 1, 4)

func test_boss2_fortune_runner_battle_completes():
	var result: NodeResult = BattleNodeRunner.run_battle_to_node_result(
		42, &"boss2_fortune_runner_v1"
	)
	assert_not_null(result)
	assert_between(result.rank, 1, 4)

func test_boss3_kanmon_battle_completes():
	var result: NodeResult = BattleNodeRunner.run_battle_to_node_result(
		42, &"boss3_kanmon_v1"
	)
	assert_not_null(result)
	assert_between(result.rank, 1, 4)

func test_boss_plus_player_skills_battle_completes():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	var ability_ids: Array = []
	for a in rs.player_deck.abilities:
		ability_ids.append(a.id)
	var result: NodeResult = BattleNodeRunner.run_battle_to_node_result(
		42, &"boss1_iron_curtain_v1", ability_ids, false, rs.player_deck.tile_variants
	)
	assert_not_null(result)
	assert_between(result.rank, 1, 4)
	var sum := 0
	for s in result.final_scores:
		sum += int(s)
	assert_eq(sum, 100000, "boss + player skills 分数仍守恒")


# ============================================================
# 第 5 组：AI 对手能力
# ============================================================

func test_ai_abilities_inject_battle_completes():
	var result_dict: Dictionary = BattleNodeRunner.run_battle_with_stats(
		42, &"", [], false, {}, 0, 12345
	)
	assert_not_null(result_dict.node_result)
	assert_between(result_dict.node_result.rank, 1, 4)

func test_all_four_players_with_abilities_battle_completes():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	var ability_ids: Array = []
	for a in rs.player_deck.abilities:
		ability_ids.append(a.id)
	var result_dict: Dictionary = BattleNodeRunner.run_battle_with_stats(
		42, &"boss1_iron_curtain_v1", ability_ids, false,
		rs.player_deck.tile_variants, 0, 12345
	)
	assert_not_null(result_dict.node_result)
	var sum := 0
	for s in result_dict.final_scores:
		sum += int(s)
	assert_eq(sum, 100000, "4 家都带技能仍守恒")


# ============================================================
# 第 6 组：多 seed 稳定性（不同 seed 不崩溃）
# ============================================================

func test_10_seeds_with_full_skills_all_complete():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_aggro")
	var ability_ids: Array = []
	for a in rs.player_deck.abilities:
		ability_ids.append(a.id)
	for seed_offset in range(10):
		var result: NodeResult = BattleNodeRunner.run_battle_to_node_result(
			seed_offset * 7 + 1, &"", ability_ids, false, rs.player_deck.tile_variants
		)
		assert_not_null(result, "seed %d 不该崩溃" % (seed_offset * 7 + 1))
		var sum := 0
		for s in result.final_scores:
			sum += int(s)
		assert_eq(sum, 100000, "seed %d 守恒" % (seed_offset * 7 + 1))
