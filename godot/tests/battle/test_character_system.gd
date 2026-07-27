extends GutTest

func test_character_pool_has_12_characters():
	var pool: Array = CharacterPool.all()
	assert_eq(pool.size(), 12)

func test_all_characters_unlocked_at_zero_renown():
	var unlocked: Array = CharacterPool.unlocked(0)
	assert_eq(unlocked.size(), 3, "3 初始角色应在 0 声望解锁")

func test_find_lin_yeche():
	var c: Character = CharacterPool.find(&"lin_yeche")
	assert_not_null(c)
	assert_eq(c.display_name, "林夜彻")
	assert_eq(c.starting_hp, 4)
	assert_eq(c.starting_gold, 50)
	assert_eq(c.ability_id, &"char_akagi_passive_v1")

func test_find_qiu_jue():
	var c: Character = CharacterPool.find(&"qiu_jue")
	assert_not_null(c)
	assert_eq(c.starting_hp, 5)
	assert_eq(c.ability_id, &"char_kaiji_passive_v1")

func test_find_bai_touli():
	var c: Character = CharacterPool.find(&"bai_touli")
	assert_not_null(c)
	assert_eq(c.starting_hp, 6)
	assert_eq(c.ability_id, &"char_washizu_passive_v1")

func test_character_serialization():
	var c: Character = CharacterPool.find(&"lin_yeche")
	var d := c.to_dict()
	var restored := Character.from_dict(d)
	assert_eq(restored.id, &"lin_yeche")
	assert_eq(restored.starting_hp, 4)
	assert_eq(restored.starting_gold, 50)
	assert_eq(restored.portrait_path, c.portrait_path)

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
	assert_gt(st.revealed_tiles.size(), 0, "读脊应 reveal 对手手牌")


func test_akagi_passive_accumulates_only_new_live_tile_instances():
	var reg := SkillRegistry.new()
	var st := BattleState.for_east_round(340, 0, 1, 0, 0)
	var sched := SkillScheduler.new(reg, st)
	assert_true(BossAbilityFactory.inject(reg, &"char_akagi_passive_v1", 0))
	for turn in range(13):
		st.turn_count = turn * 4
		sched.emit_event(BattleEvent.make(&"TILE_DRAWN", 0))
	assert_eq(st.revealed_tiles.size(), 13,
		"下家仍有未揭示牌时，每次发动必须新增真实实体")
	var ids: Dictionary = {}
	for record in st.revealed_tiles:
		var instance := (record as Dictionary).tile as TileInstance
		ids[instance.tile.instance_id] = true
	assert_eq(ids.size(), 13, "累计揭示不得重复同一 instance_id")
	st.turn_count += 4
	var exhausted_ctx := sched.emit_event(BattleEvent.make(&"TILE_DRAWN", 0))
	assert_eq(st.revealed_tiles.size(), 13)
	assert_true(exhausted_ctx.triggered_skills.is_empty(),
		"没有新信息时不得发 SKILL_TRIGGERED/ability 语音")

func test_kaiji_passive_adds_han_when_low_score():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.scores[0] = 10000
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"char_kaiji_passive_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(ctx.han_deltas.get(0, 0)), 2, "绝崖低分时应 +2 番")

func test_kaiji_passive_no_han_when_high_score():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"char_kaiji_passive_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(ctx.han_deltas.get(0, 0)), 0, "绝崖高分时不增番")

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
	assert_eq(st.revealed_tiles.size(), 6, "透璃应 reveal 3 对手各 2 张 = 6 张")
