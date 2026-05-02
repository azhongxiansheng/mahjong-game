extends GutTest

# 麻将王 — M6 内容生产：3 章 Boss 签名能力单测

const Boss1Hook := preload("res://skills/hooks/boss1_iron_curtain_hook.gd")
const Boss2Hook := preload("res://skills/hooks/boss2_fortune_runner_hook.gd")
const Boss3Hook := preload("res://skills/hooks/boss3_kanmon_hook.gd")

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

# ---- Boss 1 铁幕 ----

func test_boss1_cancels_ron_when_boss_discards():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"boss1_iron_curtain_v1", Boss1Hook, [&"RON_DECLARED"])
	reg.register(ab, 2)  # Boss 在 seat 2
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 0, null, {"discarder_seat": 2}))
	assert_true(st.ron_cancelled[0], "Boss(2) 放铳被 actor=0 荣胡 → 取消")

func test_boss1_no_cancel_when_other_seat_discards():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var st: BattleState = ctx[1]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"boss1_iron_curtain_v1", Boss1Hook, [&"RON_DECLARED"])
	reg.register(ab, 2)
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 0, null, {"discarder_seat": 1}))
	assert_false(st.ron_cancelled[0], "Boss 没放铳，不取消")

# ---- Boss 2 福星 ----

func test_boss2_adds_2_han_when_self_wins():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"boss2_fortune_runner_v1", Boss2Hook, [&"WIN_DECLARED"])
	reg.register(ab, 1)  # Boss 在 seat 1
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1))
	assert_eq(int(out_ctx.han_deltas.get(1, 0)), 2)

func test_boss2_no_han_when_other_wins():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"boss2_fortune_runner_v1", Boss2Hook, [&"WIN_DECLARED"])
	reg.register(ab, 1)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 3))
	assert_eq(int(out_ctx.han_deltas.get(1, 0)), 0)
	assert_eq(int(out_ctx.han_deltas.get(3, 0)), 0)

# ---- Boss 3 关门 ----

func test_boss3_adds_3_han_at_haitei():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"boss3_kanmon_v1", Boss3Hook, [&"HAITEI", &"HOUTEI"])
	reg.register(ab, 3)
	var out_ctx := sched.emit_event(BattleEvent.make(&"HAITEI", 3))
	assert_eq(int(out_ctx.han_deltas.get(3, 0)), 3)

func test_boss3_adds_3_han_at_houtei():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"boss3_kanmon_v1", Boss3Hook, [&"HAITEI", &"HOUTEI"])
	reg.register(ab, 3)
	var out_ctx := sched.emit_event(BattleEvent.make(&"HOUTEI", 3))
	assert_eq(int(out_ctx.han_deltas.get(3, 0)), 3)

func test_boss3_no_effect_when_other_seat_wins():
	var ctx := _setup()
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability(&"boss3_kanmon_v1", Boss3Hook, [&"HAITEI", &"HOUTEI"])
	reg.register(ab, 3)
	var out_ctx := sched.emit_event(BattleEvent.make(&"HAITEI", 0))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 0)
	assert_eq(int(out_ctx.han_deltas.get(3, 0)), 0)
