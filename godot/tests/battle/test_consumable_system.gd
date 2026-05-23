extends GutTest

# 麻将王 — 消耗品系统全链路 TDD（无 mock）


# ============================================================
# 第 1 组：ConsumableItem 数据类
# ============================================================

func test_consumable_item_creation():
	var c := ConsumableItem.new(&"test_item", ConsumableItem.Kind.BATTLE, Rarity.Kind.EPIC)
	assert_eq(c.id, &"test_item")
	assert_eq(c.kind, ConsumableItem.Kind.BATTLE)
	assert_true(c.is_battle())
	assert_false(c.is_run())

func test_consumable_item_serialization():
	var c := ConsumableItem.new(&"test_item", ConsumableItem.Kind.RUN, Rarity.Kind.COMMON)
	c.display_name = "测试道具"
	c.description = "测试用"
	var d := c.to_dict()
	var restored := ConsumableItem.from_dict(d)
	assert_eq(restored.id, &"test_item")
	assert_eq(restored.kind, ConsumableItem.Kind.RUN)
	assert_eq(restored.display_name, "测试道具")


# ============================================================
# 第 2 组：CardPool consumable pool
# ============================================================

func test_card_pool_has_consumables():
	var pool := CardPool.all_consumables()
	assert_gt(pool.size(), 0, "CardPool 应有消耗品")

func test_card_pool_battle_consumables():
	var battle := CardPool.consumables_by_kind(ConsumableItem.Kind.BATTLE)
	assert_gt(battle.size(), 0, "应有战斗消耗品")
	for c in battle:
		assert_true(c.is_battle())

func test_card_pool_run_consumables():
	var run := CardPool.consumables_by_kind(ConsumableItem.Kind.RUN)
	assert_gt(run.size(), 0, "应有旅途消耗品")
	for c in run:
		assert_true(c.is_run())

func test_each_battle_consumable_has_hook():
	for c in CardPool.consumables_by_kind(ConsumableItem.Kind.BATTLE):
		assert_ne(c.hook_resource_path, "", "%s 应有 hook 路径" % c.id)


# ============================================================
# 第 3 组：ConsumableFactory 注入
# ============================================================

func test_factory_build_iron_shield():
	var sk := ConsumableFactory.build(&"iron_shield_v1")
	assert_not_null(sk)
	assert_true(sk.is_ability)
	assert_true(sk.owner_triggers.has(&"RON_DECLARED"))

func test_factory_build_wall_peek():
	var sk := ConsumableFactory.build(&"wall_peek_v1")
	assert_not_null(sk)
	assert_true(sk.owner_triggers.has(&"GAME_BEGIN"))

func test_factory_build_double_payout():
	var sk := ConsumableFactory.build(&"double_payout_v1")
	assert_not_null(sk)
	assert_true(sk.owner_triggers.has(&"WIN_DECLARED_PRE"))

func test_factory_inject_registers():
	var reg := SkillRegistry.new()
	var ok := ConsumableFactory.inject(reg, &"iron_shield_v1", 0)
	assert_true(ok)
	assert_eq(reg.get_all_entries().size(), 1)

func test_factory_inject_all():
	var reg := SkillRegistry.new()
	var ids: Array = [&"iron_shield_v1", &"wall_peek_v1", &"double_payout_v1", &"dora_charm_v1"]
	var n := ConsumableFactory.inject_all(reg, ids, 0)
	assert_eq(n, 4)
	assert_eq(reg.get_all_entries().size(), 4)

func test_factory_unknown_id_returns_false():
	var reg := SkillRegistry.new()
	var ok := ConsumableFactory.inject(reg, &"nonexistent_v1", 0)
	assert_false(ok)
	assert_eq(reg.get_all_entries().size(), 0)


# ============================================================
# 第 4 组：消耗品在真实战斗中触发
# ============================================================

func test_iron_shield_cancels_ron_and_consumes():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"iron_shield_v1", 0)
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, null, {"discarder_seat": 0}))
	assert_true(st.ron_cancelled[1], "铁盾应取消荣胡")
	# 第二次不触发（已 consumed）
	st.ron_cancelled[1] = false
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, null, {"discarder_seat": 0}))
	assert_false(st.ron_cancelled[1], "consumed 后不再触发")

func test_wall_peek_reveals_on_game_begin():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.wall = Wall.new_full_set()
	st.wall.shuffle(42)
	st.wall.reserve_dead_wall(14)
	for i in range(4):
		st.seats.append(Seat.new(i, TileId.E))
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"wall_peek_v1", 0)
	assert_eq(st.revealed_tiles.size(), 0)
	sched.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	assert_eq(st.revealed_tiles.size(), 5, "千里眼应 reveal 5 张")

func test_double_payout_multiplies_han():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"double_payout_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(float(ctx.han_multipliers.get(0, 1.0)), 2.0, "倍率券应 ×2")
	# consumed 后不再触发
	var ctx2 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(float(ctx2.han_multipliers.get(0, 1.0)), 1.0, "consumed 后倍率回 1.0")

func test_dora_charm_adds_extra_dora():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	ConsumableFactory.inject(reg, &"dora_charm_v1", 0)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(st.extra_dora_count[0], 3, "宝牌护符应 +3 dora")


# ============================================================
# 第 5 组：消耗品 + 正常技能共存完整战斗不崩
# ============================================================

func test_consumables_with_starter_pack_battle_completes():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	var ability_ids: Array = []
	for a in rs.player_deck.abilities:
		ability_ids.append(a.id)
	# 模拟玩家带了 2 个消耗品
	var consumable_ids: Array = [&"iron_shield_v1", &"wall_peek_v1"]
	var bc := BattleController.new(42)
	BossAbilityFactory.inject_player_abilities(bc.registry, ability_ids, 0)
	TileSkillFactory.inject_player_tile_variants(bc.registry, rs.player_deck.tile_variants, 0)
	ConsumableFactory.inject_all(bc.registry, consumable_ids, 0)
	var result: Dictionary = bc.run_to_end()
	assert_true(result.has("events"), "带消耗品的战斗应正常完成")
	var has_game_begin := false
	for ev: BattleEvent in result.events:
		if ev.type == &"GAME_BEGIN":
			has_game_begin = true
			break
	assert_true(has_game_begin)
