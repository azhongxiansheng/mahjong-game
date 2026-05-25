extends GutTest

# M12 新增能力 + Boss 変種 単体テスト

const HisaHook := preload("res://skills/hooks/hisa_bad_wait_hook.gd")
const TsubameHook := preload("res://skills/hooks/tsubame_gaeshi_hook.gd")
const StreakHook := preload("res://skills/hooks/streak_escalation_hook.gd")
const Boss2DoraThiefHook := preload("res://skills/hooks/boss2_dora_thief_hook.gd")

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func _make_ability(id: StringName, hook: GDScript, triggers: Array) -> SkillResource:
	var s := SkillResource.new()
	s.id = id
	s.rarity = Rarity.Kind.LEGENDARY
	s.is_ability = true
	var ot: Array[StringName] = []
	for t in triggers:
		ot.append(t)
	s.owner_triggers = ot
	s.hook_script = hook
	return s

# ---- hisa_bad_wait: +2 han on self win ----

func test_hisa_bad_wait_adds_2_han_on_self_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"hisa_bad_wait_v1", HisaHook, [&"WIN_DECLARED_PRE"])
	reg.register(ab, 0)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 2, "hisa: self win +2 han")

func test_hisa_bad_wait_no_effect_on_other_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"hisa_bad_wait_v1", HisaHook, [&"WIN_DECLARED_PRE"])
	reg.register(ab, 0)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 0, "hisa: other win no effect")
	assert_eq(int(out_ctx.han_deltas.get(1, 0)), 0, "hisa: other win no effect on actor")

# ---- tsubame_gaeshi: +3 han + consume_self ----

func test_tsubame_gaeshi_adds_3_han_and_consumes():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"tsubame_gaeshi_v1", TsubameHook, [&"WIN_DECLARED_PRE"])
	reg.register(ab, 0)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 3, "tsubame: +3 han")
	assert_true(ab.consumed, "tsubame: consumed after use")

func test_tsubame_gaeshi_no_effect_when_consumed():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"tsubame_gaeshi_v1", TsubameHook, [&"WIN_DECLARED_PRE"])
	reg.register(ab, 0)
	# First use
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_true(ab.consumed)
	# Second use — consumed skills should not fire (scheduler skips consumed)
	var out_ctx2 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out_ctx2.han_deltas.get(0, 0)), 0, "tsubame: no effect after consumed")

# ---- streak_escalation: cumulative +han ----

func test_streak_escalation_cumulative():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"streak_escalation_v1", StreakHook,
		[&"WIN_DECLARED_PRE", &"WIN_DECLARED", &"EXHAUSTIVE_DRAW"])
	reg.register(ab, 0)

	# Win 1: PRE fires first (streak=0 → +0 han), then WIN_DECLARED increments to 1
	var out1 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out1.han_deltas.get(0, 0)), 0, "streak: first win PRE → +0")
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(int(ab.params.get("streak_count", 0)), 1, "streak: count = 1 after first win")

	# Win 2: PRE fires (streak=1 → +1 han), then WIN_DECLARED increments to 2
	var out2 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out2.han_deltas.get(0, 0)), 1, "streak: second win PRE → +1")
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(int(ab.params.get("streak_count", 0)), 2, "streak: count = 2 after second win")

	# Win 3: PRE fires (streak=2 → +2 han)
	var out3 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out3.han_deltas.get(0, 0)), 2, "streak: third win PRE → +2")
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))

	# Exhaustive draw resets
	sched.emit_event(BattleEvent.make(&"EXHAUSTIVE_DRAW", 0))
	assert_eq(int(ab.params.get("streak_count", 0)), 0, "streak: reset after draw")

	# After reset: PRE should give +0 again
	var out4 := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out4.han_deltas.get(0, 0)), 0, "streak: after reset PRE → +0")

# ---- boss2_dora_thief: +2 dora for boss ----

func test_boss2_dora_thief_adds_2_dora_for_boss():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"boss2_dora_thief_v1", Boss2DoraThiefHook, [&"WIN_DECLARED_PRE"])
	reg.register(ab, 1)  # Boss at seat 1
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1))
	assert_eq(int(st.extra_dora_count[1]), 2, "boss2 thief: +2 dora for boss")

func test_boss2_dora_thief_no_effect_on_player_win():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"boss2_dora_thief_v1", Boss2DoraThiefHook, [&"WIN_DECLARED_PRE"])
	reg.register(ab, 1)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(st.extra_dora_count[0]), 0, "boss2 thief: no effect on player win")
	assert_eq(int(st.extra_dora_count[1]), 0, "boss2 thief: no dora for boss when player wins")
