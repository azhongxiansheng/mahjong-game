extends GutTest

# 麻将王 — triggered_skills 噪音过滤验证
#
# 验证：hook 被调用但条件不满足（没改变 state）时不记录 triggered_skills。

func test_shichu_high_score_not_triggered():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	# 默认 25000 > 5000 → shichu 不触发
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"shichu_kyu_katsu_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(ctx.triggered_skills.size(), 0, "高分时 shichu 不该记录为 triggered")

func test_shichu_low_score_is_triggered():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.scores[0] = 3000
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"shichu_kyu_katsu_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(ctx.triggered_skills.size(), 1, "低分时 shichu 应记录")

func test_seal_chun_wrong_discarder_not_triggered():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"seal_chun_v1", 0)
	# discarder=1 不等于 owner=0 → 不触发
	var ctx := sched.emit_event(BattleEvent.make(&"RON_DECLARED", 2, null, {"discarder_seat": 1}))
	assert_eq(ctx.triggered_skills.size(), 0, "discarder 不匹配时 seal_chun 不该记录")

func test_seal_chun_correct_discarder_is_triggered():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"seal_chun_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"RON_DECLARED", 2, null, {"discarder_seat": 0}))
	assert_eq(ctx.triggered_skills.size(), 1, "discarder 匹配时 seal_chun 应记录")

func test_thunder_5w_wrong_actor_not_triggered():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"thunder_5w_v1", 0)
	# actor=1 ≠ beneficiary=0 → thunder_5w 内部 return
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1))
	assert_eq(ctx.triggered_skills.size(), 0, "actor 不匹配时 thunder_5w 不该记录")

func test_thunder_5w_correct_actor_is_triggered():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"thunder_5w_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(ctx.triggered_skills.size(), 1, "actor 匹配时 thunder_5w 应记录")

func test_boss2_wrong_seat_not_triggered():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"boss2_fortune_runner_v1", 1)
	# actor=0 ≠ boss beneficiary=1
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(ctx.triggered_skills.size(), 0, "非 boss 座 WIN_DECLARED_PRE 不该触发 boss2")
