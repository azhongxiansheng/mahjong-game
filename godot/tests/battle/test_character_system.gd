extends GutTest

func test_character_pool_has_12_characters():
	# 6 初版 + M12 咲 6 角色
	var pool: Array = CharacterPool.all()
	assert_eq(pool.size(), 12)

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

func test_akagi_passive_reveals_opponent_hand():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.wall = Wall.new_full_set()
	st.wall.shuffle(42)
	st.wall.reserve_dead_wall(14)
	for i in range(4):
		var seat := Seat.new(i, TileId.E)
		for _j in range(13):
			seat.add_to_hand(st.wall.draw())
		st.seats.append(seat)
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"char_akagi_passive_v1", 0)
	sched.emit_event(BattleEvent.make(&"TILE_DRAWN", 0))
	assert_gt(st.revealed_tiles.size(), 0, "赤木鬼読み应 reveal 对手手牌")

func test_kaiji_passive_adds_han_when_low_score():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.scores[0] = 10000
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"char_kaiji_passive_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(ctx.han_deltas.get(0, 0)), 2, "开司低分时应 +2 番")

func test_kaiji_passive_no_han_when_high_score():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"char_kaiji_passive_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(ctx.han_deltas.get(0, 0)), 0, "开司高分时不增番")

func test_washizu_passive_reveals_all_opponents():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.wall = Wall.new_full_set()
	st.wall.shuffle(42)
	st.wall.reserve_dead_wall(14)
	for i in range(4):
		var seat := Seat.new(i, TileId.E)
		for _j in range(13):
			seat.add_to_hand(st.wall.draw())
		st.seats.append(seat)
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"char_washizu_passive_v1", 0)
	sched.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	assert_eq(st.revealed_tiles.size(), 6, "鹲巣应 reveal 3 对手各 2 张 = 6 张")

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
