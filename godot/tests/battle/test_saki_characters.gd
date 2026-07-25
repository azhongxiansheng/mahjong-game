extends GutTest

# 中段 3 角色被动 + 解锁阶梯（id 已迁至原创）

func test_character_pool_has_12_characters():
	assert_eq(CharacterPool.all().size(), 12)

func test_3_unlocked_at_zero_renown():
	assert_eq(CharacterPool.unlocked(0).size(), 3)

func test_hua_ling_unlocked_at_50():
	assert_eq(CharacterPool.unlocked(50).size(), 4)
	assert_not_null(CharacterPool.find(&"hua_ling"))

func test_lian_yao_unlocked_at_100():
	assert_eq(CharacterPool.unlocked(100).size(), 5)
	assert_not_null(CharacterPool.find(&"lian_yao"))

func test_an_cheng_unlocked_at_200():
	assert_eq(CharacterPool.unlocked(200).size(), 6)
	assert_not_null(CharacterPool.find(&"an_cheng"))

func test_saki_passive_adds_dora():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"char_saki_passive_v1", 0)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(st.extra_dora_count[0], 2, "岭华应 +2 dora")

func test_teru_passive_accumulates_han():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"char_teru_passive_v1", 0)
	var ctx1 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(ctx1.han_deltas.get(0, 0)), 1, "连曜第 1 次胡 +1")
	var ctx2 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(ctx2.han_deltas.get(0, 0)), 2, "连曜第 2 次胡 +2")
	var ctx3 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(ctx3.han_deltas.get(0, 0)), 3, "连曜第 3 次胡 +3")

func test_awai_passive_clears_furiten_and_reveals():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.wall = Wall.new_full_set()
	st.wall.shuffle(42)
	st.wall.reserve_dead_wall(14)
	st.furiten_flags[0] = true
	for i in range(4):
		var seat := Seat.new(i, TileId.E)
		for _j in range(13):
			seat.add_to_hand(st.wall.draw())
		st.seats.append(seat)
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"char_awai_passive_v1", 0)
	sched.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	assert_false(st.furiten_flags[0], "澄安应清振听")
	assert_gt(st.revealed_tiles.size(), 0, "澄安应 reveal 下张牌")

func test_late_six_passives_inject_via_factory():
	for ab_id in [
		&"char_koromo_passive_v1", &"char_nodoka_passive_v1", &"char_toki_passive_v1",
		&"char_kuro_passive_v1", &"char_momoko_passive_v1", &"char_tetsuya_passive_v1",
	]:
		var reg := SkillRegistry.new()
		assert_true(BossAbilityFactory.inject(reg, ab_id, 0), "后六 inject: %s" % ab_id)
