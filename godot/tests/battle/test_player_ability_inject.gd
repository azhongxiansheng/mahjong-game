extends GutTest

# 麻将王 — M7：玩家 ability → BattleController.registry 接入。
#
# 此前 BossAbilityFactory 只支持 3 章 Boss inject；玩家 deck.abilities
# 永不在真战斗 fire。本批改：扩 _ABILITY_TRIGGERS 覆盖 9 张 M6 玩家能力，
# 加 inject_player_abilities helper，BattleNodeRunner 接受
# player_ability_ids 参数。

# ---- _ABILITY_TRIGGERS 完整性 ----

func test_known_ability_ids_includes_boss_and_player():
	var ids := BossAbilityFactory.known_ability_ids()
	# 3 boss + 9 player = 12
	for needed in [
		&"boss1_iron_curtain_v1", &"boss2_fortune_runner_v1", &"boss3_kanmon_v1",
		&"seabed_hunter_v1", &"shichu_kyu_katsu_v1", &"mineu_no_oni_v1",
		&"san_kyoku_kiseki_v1", &"isshun_senken_v1",
		&"yamagan_v1", &"tenpai_seethru_v1", &"ryukyoku_yudou_v1",
		&"tousotsu_v1", &"riichi_kago_v1",
	]:
		assert_true(ids.has(needed), "ability id 缺失: %s" % needed)

func test_known_boss_ids_only_returns_6():
	# 严格只含 Boss id（3 章原版 + 3 变体）,不混入玩家能力
	var ids := BossAbilityFactory.known_boss_ids()
	assert_eq(ids.size(), 6)

# ---- build for player abilities ----

func test_build_seabed_hunter_uses_haitei_trigger():
	var sk: SkillResource = BossAbilityFactory.build(&"seabed_hunter_v1")
	assert_not_null(sk)
	assert_true(sk.is_ability)
	assert_true(sk.owner_triggers.has(&"HAITEI"))

func test_build_shichu_uses_win_declared_pre():
	var sk: SkillResource = BossAbilityFactory.build(&"shichu_kyu_katsu_v1")
	assert_not_null(sk)
	assert_true(sk.owner_triggers.has(&"WIN_DECLARED_PRE"))

func test_build_yamagan_uses_game_begin():
	var sk: SkillResource = BossAbilityFactory.build(&"yamagan_v1")
	assert_not_null(sk)
	assert_true(sk.owner_triggers.has(&"GAME_BEGIN"))

func test_build_isshun_senken_uses_tile_drawn():
	var sk: SkillResource = BossAbilityFactory.build(&"isshun_senken_v1")
	assert_not_null(sk)
	assert_true(sk.owner_triggers.has(&"TILE_DRAWN"))

# ---- inject_player_abilities ----

func test_inject_player_abilities_registers_each():
	var reg := SkillRegistry.new()
	var ids: Array = [&"shichu_kyu_katsu_v1", &"san_kyoku_kiseki_v1"]
	var n := BossAbilityFactory.inject_player_abilities(reg, ids, 0)
	assert_eq(n, 2)
	var entries: Array = reg.get_all_entries()
	assert_eq(entries.size(), 2)
	for e in entries:
		assert_eq(int(e.anchor), 0, "anchor 是玩家 seat 0")

func test_inject_player_abilities_skips_unknown():
	var reg := SkillRegistry.new()
	var ids: Array = [&"shichu_kyu_katsu_v1", &"unknown_ability_v1", &"san_kyoku_kiseki_v1"]
	var n := BossAbilityFactory.inject_player_abilities(reg, ids, 0)
	assert_eq(n, 2, "未知 id 静默跳过")

func test_inject_player_abilities_empty_array():
	var reg := SkillRegistry.new()
	var n := BossAbilityFactory.inject_player_abilities(reg, [], 0)
	assert_eq(n, 0)
	assert_eq(reg.get_all_entries().size(), 0)

# ---- 集成：注入后真触发 ----

func test_inject_shichu_then_emit_pre_with_low_score_adds_2_han():
	# shichu_kyu_katsu：score < 5000 时 +2 番
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.scores[0] = 3000  # < 5000
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"shichu_kyu_katsu_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(ctx.han_deltas.get(0, 0)), 2)

func test_inject_shichu_then_emit_pre_with_high_score_no_han():
	# shichu_kyu_katsu：score ≥ 5000 时不触发
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	# 默认 STARTING_SCORE = 25000
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"shichu_kyu_katsu_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(ctx.han_deltas.get(0, 0)), 0)

# ---- BattleNodeRunner: player_ability_ids 参数 ----

func test_run_battle_with_player_abilities_completes():
	var ids: Array = [&"shichu_kyu_katsu_v1"]
	var r: NodeResult = BattleNodeRunner.run_battle_to_node_result(42, &"", ids)
	assert_not_null(r)
	# 守恒
	var sum := 0
	for s in r.final_scores:
		sum += int(s)
	assert_eq(sum, 100000, "玩家 ability inject 后总分仍守恒")

func test_run_battle_with_player_and_boss_abilities():
	# 同时 inject Boss + 玩家能力（不同 seat 不冲突）
	var ids: Array = [&"shichu_kyu_katsu_v1", &"san_kyoku_kiseki_v1"]
	var r: NodeResult = BattleNodeRunner.run_battle_to_node_result(
		42, &"boss1_iron_curtain_v1", ids
	)
	assert_not_null(r)

func test_run_battle_with_unknown_player_ability_silently_skips():
	var ids: Array = [&"unknown_ability_v1"]
	var r: NodeResult = BattleNodeRunner.run_battle_to_node_result(42, &"", ids)
	assert_not_null(r)
