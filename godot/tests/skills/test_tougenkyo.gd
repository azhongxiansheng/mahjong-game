extends GutTest

# 麻将王 — M7 收尾：tougenkyo_v1（§8.10 #12，M6 holdout）

const TougenkyoHook := preload("res://skills/hooks/tougenkyo_hook.gd")

func _make_skill() -> SkillResource:
	var s := SkillResource.new()
	s.id = &"tougenkyo_v1"
	s.is_ability = true
	s.rarity = Rarity.Kind.LEGENDARY
	var ot: Array[StringName] = [&"WIN_DECLARED_PRE"]
	s.owner_triggers = ot
	s.hook_script = TougenkyoHook
	return s

func _setup() -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_tougenkyo_adds_3_han_on_self_win_and_consumes():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	reg.register(sk, 0)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(out.han_deltas.get(0, 0)), 3, "self-win → +3 番（v1 简化版）")
	assert_true(sk.consumed, "consume_self（每局 1 次）")

func test_tougenkyo_no_effect_for_other_seat():
	var arr := _setup()
	var reg: SkillRegistry = arr[0]
	var sched: SkillScheduler = arr[2]
	var sk := _make_skill()
	reg.register(sk, 0)
	var out := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 2))
	assert_eq(int(out.han_deltas.get(0, 0)), 0)
	assert_false(sk.consumed)

# ---- 集成 BossAbilityFactory（PlayerAbilityFactory 的别名）----

func test_factory_knows_tougenkyo():
	var ids := BossAbilityFactory.known_ability_ids()
	assert_true(ids.has(&"tougenkyo_v1"), "factory 中应注册 tougenkyo_v1")

func test_factory_inject_tougenkyo_works():
	var reg := SkillRegistry.new()
	var ok := BossAbilityFactory.inject(reg, &"tougenkyo_v1", 0)
	assert_true(ok)
	assert_eq(reg.get_all_entries().size(), 1)
	# 集成测试：inject 后 emit 实际生效
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(ctx.han_deltas.get(0, 0)), 3)
