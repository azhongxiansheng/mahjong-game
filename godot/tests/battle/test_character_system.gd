extends GutTest

func test_character_pool_has_3_characters():
	var pool: Array = CharacterPool.all()
	assert_eq(pool.size(), 3)

func test_all_characters_unlocked_at_zero_renown():
	var unlocked: Array = CharacterPool.unlocked(0)
	assert_eq(unlocked.size(), 3, "3 初始角色应在 0 声望解锁")

func test_find_akagi():
	var c: Character = CharacterPool.find(&"akagi")
	assert_not_null(c)
	assert_eq(c.display_name, "赤木")
	assert_eq(c.starting_hp, 4)
	assert_eq(c.starting_gold, 50)

func test_find_kaiji():
	var c: Character = CharacterPool.find(&"kaiji")
	assert_not_null(c)
	assert_eq(c.starting_hp, 5)

func test_find_washizu():
	var c: Character = CharacterPool.find(&"washizu")
	assert_not_null(c)
	assert_eq(c.starting_hp, 6)

func test_character_serialization():
	var c: Character = CharacterPool.find(&"akagi")
	var d := c.to_dict()
	var restored := Character.from_dict(d)
	assert_eq(restored.id, &"akagi")
	assert_eq(restored.starting_hp, 4)
	assert_eq(restored.starting_gold, 50)

func test_akagi_passive_adds_1_han():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"char_akagi_passive_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(ctx.han_deltas.get(0, 0)), 1, "赤木被动应 +1 番")

func test_kaiji_passive_cancels_ron_sometimes():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"char_kaiji_passive_v1", 0)
	var cancelled_count := 0
	for seed_val in range(20):
		st.ron_cancelled[1] = false
		var ev := BattleEvent.make(&"RON_DECLARED", 1, null, {"discarder_seat": 0})
		ev.chain_id = seed_val
		sched.emit_event(ev)
		if st.ron_cancelled[1]:
			cancelled_count += 1
	assert_gt(cancelled_count, 0, "开司被动应偶尔取消 ron")
	assert_lt(cancelled_count, 20, "开司被动不应总是取消")

func test_washizu_passive_reveals_wall():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.wall = Wall.new_full_set()
	st.wall.shuffle(42)
	st.wall.reserve_dead_wall(14)
	for i in range(4):
		st.seats.append(Seat.new(i, TileId.E))
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"char_washizu_passive_v1", 0)
	sched.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	assert_eq(st.revealed_tiles.size(), 3, "鹲巣被动应 reveal 3 张")

func test_run_state_character_applied():
	var rs := RunState.new(42)
	rs.selected_character_id = &"akagi"
	var d := rs.to_dict()
	var restored := RunState.from_dict(d)
	assert_eq(restored.selected_character_id, &"akagi")

func test_battle_with_character_passive():
	var result: NodeResult = BattleNodeRunner.run_battle_to_node_result(
		42, &"", [&"char_akagi_passive_v1"]
	)
	assert_not_null(result)
	assert_between(result.rank, 1, 4)
