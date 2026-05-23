extends GutTest

# 麻将王 — 遗物系统全链路 TDD

func test_relic_item_creation():
	var r := RelicItem.new(&"relic_lucky_cat_v1", Rarity.Kind.UNCOMMON)
	r.display_name = "招财猫"
	assert_eq(r.id, &"relic_lucky_cat_v1")
	assert_eq(r.rarity, Rarity.Kind.UNCOMMON)

func test_relic_serialization():
	var r := RelicItem.new(&"relic_test", Rarity.Kind.EPIC)
	r.display_name = "测试遗物"
	r.description = "测试用"
	var d := r.to_dict()
	var restored := RelicItem.from_dict(d)
	assert_eq(restored.id, &"relic_test")
	assert_eq(restored.display_name, "测试遗物")

func test_card_pool_has_relics():
	var pool: Array = CardPool.all_relics()
	assert_eq(pool.size(), 4, "应有 4 个遗物")

func test_relic_factory_build():
	var sk: SkillResource = RelicFactory.build(&"relic_lucky_cat_v1")
	assert_not_null(sk)
	assert_true(sk.is_ability)
	assert_true(sk.owner_triggers.has(&"WIN_DECLARED_PRE"))

func test_relic_factory_inject():
	var reg := SkillRegistry.new()
	var ok := RelicFactory.inject(reg, &"relic_lucky_cat_v1", 0)
	assert_true(ok)
	assert_eq(reg.get_all_entries().size(), 1)

func test_relic_lucky_cat_adds_dora():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	RelicFactory.inject(reg, &"relic_lucky_cat_v1", 0)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(st.extra_dora_count[0], 1, "招财猫应 +1 dora")
	# 遗物不消耗——第二次也触发
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(st.extra_dora_count[0], 2, "遗物永久——再 +1")

func test_relic_iron_will_reduces_han():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	RelicFactory.inject(reg, &"relic_iron_will_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1, null, {"discarder_seat": 0}))
	assert_eq(int(ctx.han_deltas.get(1, 0)), -1, "铁壁意志应给对手 -1 番")

func test_relic_soul_mirror_steals_score():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	RelicFactory.inject(reg, &"relic_soul_mirror_v1", 0)
	var before_0: int = st.scores[0]
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1))
	assert_gt(st.scores[0], before_0, "魂镜应偷取得分")

func test_run_state_relic_management():
	var rs := RunState.new(42)
	var pool: Array = CardPool.all_relics()
	assert_eq(rs.relic_count(), 0)
	rs.add_relic(pool[0])
	assert_eq(rs.relic_count(), 1)
	assert_true(rs.has_relic(pool[0].id))
	# 不允许重复
	var dup: bool = rs.add_relic(pool[0])
	assert_false(dup, "不允许重复遗物")
	assert_eq(rs.relic_count(), 1)

func test_run_state_relic_serialization():
	var rs := RunState.new(42)
	for r in CardPool.all_relics():
		rs.add_relic(r)
	var d := rs.to_dict()
	var restored := RunState.from_dict(d)
	assert_eq(restored.relic_count(), rs.relic_count())

func test_gacha_result_make_relic():
	var item: RelicItem = CardPool.all_relics()[0]
	var r := GachaResult.make_relic(item)
	assert_eq(r.kind, GachaResult.KIND_RELIC)
	assert_not_null(r.relic)

func test_relic_with_battle_completes():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	for r in CardPool.all_relics():
		rs.add_relic(r)
	var ability_ids: Array = []
	for a in rs.player_deck.abilities:
		ability_ids.append(a.id)
	var result: NodeResult = BattleNodeRunner.run_battle_to_node_result(
		42, &"", ability_ids, false, rs.player_deck.tile_variants, 0, 0, "east_round", false, [], rs.relic_ids()
	)
	assert_not_null(result)
	assert_between(result.rank, 1, 4)
