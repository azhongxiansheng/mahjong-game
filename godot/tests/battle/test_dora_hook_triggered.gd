extends GutTest

# 麻将王 — dora 系 hook 在 triggered_skills 中正确记录

func test_sou4_records_triggered_skill():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"sou4_uradora_pick_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(ctx.triggered_skills.size(), 1, "sou4 mark_extra_dora 应被记录为 triggered")

func test_man6_treasure_records_triggered_skill():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"man6_treasure_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(ctx.triggered_skills.size(), 1, "man6 mark_extra_dora 应被记录")

func test_white_red_change_records_triggered_skill():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"white_red_change_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(ctx.triggered_skills.size(), 1, "white_red mark_red_dora 应被记录")
