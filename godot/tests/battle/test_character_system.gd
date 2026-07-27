extends GutTest

const ViewerRevealResolverScript := preload("res://battle/viewer_reveal_resolver.gd")

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
		var instance := (record as Dictionary).tile as TileSkillAnchor
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
	var ctx := sched.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	assert_eq(st.revealed_tiles.size(), 6, "透璃应 reveal 3 对手各 2 张 = 6 张")
	assert_eq(ctx.triggered_skills.size(), 1, "真实 GAME_BEGIN 只触发一次白透璃能力")
	var unique_ids: Dictionary = {}
	var counts_by_holder: Dictionary = {}
	for value in st.revealed_tiles:
		var record := value as Dictionary
		var instance := record.tile as TileSkillAnchor
		unique_ids[instance.tile.instance_id] = true
		counts_by_holder[instance.holder_seat] = int(
			counts_by_holder.get(instance.holder_seat, 0)) + 1
		assert_eq(record.visible_to, [0], "每张牌只能授权给白透璃座位")
	assert_eq(unique_ids.size(), 6, "同一对手的两次揭示不得重复同一实体")
	assert_eq(counts_by_holder, {1: 2, 2: 2, 3: 2}, "三名对手必须各揭示两张")


func test_washizu_reveal_survives_authority_restore_and_new_hand_clears() -> void:
	var source := BattleController.new(341, 0, false, TileId.E, 0)
	assert_true(BossAbilityFactory.inject(
		source.registry, &"char_washizu_passive_v1", 0))
	var ctx := source.scheduler.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	assert_eq(ctx.triggered_skills.size(), 1)
	var snapshot := AuthorityReplaySnapshot.capture(source)
	assert_not_null(snapshot)
	assert_true(snapshot.can_restore())
	var restored := BattleController.new(999, 1, false, TileId.S_WIND, 0)
	assert_true(snapshot.restore_into(restored))
	var grouped: Dictionary = ViewerRevealResolverScript.tiles_by_holder(restored.state, 0)
	for holder in [1, 2, 3]:
		assert_eq((grouped.get(holder, []) as Array).size(), 2,
			"恢复后每家授权子集保持两张")
	assert_true(ViewerRevealResolverScript.tiles_by_holder(restored.state, 2).is_empty(),
		"权威恢复不得扩大 viewer 授权")
	var next_hand := BattleController.new(342, 0, false, TileId.E, 1)
	assert_true(next_hand.state.revealed_tiles.is_empty(), "新局必须清空上局揭示")


func test_an_cheng_next_draw_survives_restore_then_expires_on_draw() -> void:
	var source := BattleController.new(344, 0, false, TileId.E, 0)
	assert_true(BossAbilityFactory.inject(source.registry, &"char_awai_passive_v1", 0))
	var expected: Tile = source.state.wall.peek_next_draw()
	var ctx := source.scheduler.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	assert_eq(ctx.triggered_skills.size(), 1)
	var snapshot := AuthorityReplaySnapshot.capture(source)
	assert_not_null(snapshot)
	assert_true(snapshot.can_restore())
	var restored := BattleController.new(999, 1, false, TileId.S_WIND, 0)
	assert_true(snapshot.restore_into(restored))
	var predicted: TileSkillAnchor = ViewerRevealResolverScript.next_draw_for_viewer(
		restored.state, 0)
	assert_not_null(predicted)
	assert_eq(predicted.tile.instance_id, expected.instance_id)
	assert_null(ViewerRevealResolverScript.next_draw_for_viewer(restored.state, 1))
	assert_eq(restored.state.wall.draw().instance_id, expected.instance_id)
	assert_null(ViewerRevealResolverScript.next_draw_for_viewer(restored.state, 0),
		"摸走已预知实体后恢复态投影必须立即清除")
	var next_hand := BattleController.new(345, 0, false, TileId.E, 1)
	assert_null(ViewerRevealResolverScript.next_draw_for_viewer(next_hand.state, 0),
		"新局不得继承上一局预知")
