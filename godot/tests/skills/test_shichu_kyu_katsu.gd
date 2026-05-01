extends GutTest

# 麻将王 — M6 内容生产：死中求活（§8.10 #11 神级角色能力）

const Hook := preload("res://skills/hooks/shichu_kyu_katsu_hook.gd")

func _make_ability() -> SkillResource:
	var s := SkillResource.new()
	s.id = &"shichu_kyu_katsu_v1"
	s.rarity = Rarity.Kind.LEGENDARY
	s.is_ability = true
	# 角色能力 owner_trigger
	var ot: Array[StringName] = [&"WIN_DECLARED"]
	s.owner_triggers = ot
	s.hook_script = Hook
	return s

func _setup_with_score(seat: int, score: int) -> Array:
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.scores[seat] = score
	var sched := SkillScheduler.new(reg, st)
	return [reg, st, sched]

func test_shichu_adds_2_han_when_score_below_5000():
	# owner=2，点棒 4500，自胡 → +2 番
	var ctx := _setup_with_score(2, 4500)
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability()
	reg.register(ab, 2)  # 角色能力直接 register seat（无 TileInstance）
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 2))
	assert_eq(int(out_ctx.han_deltas.get(2, 0)), 2, "点棒 4500 < 5000 → +2 番")

func test_shichu_no_effect_at_threshold():
	# 点棒 = 5000 边界 → 不触发（spec："< 5000"）
	var ctx := _setup_with_score(2, 5000)
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability()
	reg.register(ab, 2)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 2))
	assert_eq(int(out_ctx.han_deltas.get(2, 0)), 0, "点棒 = 5000 边界不触发")

func test_shichu_no_effect_above_threshold():
	var ctx := _setup_with_score(2, 25000)
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability()
	reg.register(ab, 2)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 2))
	assert_eq(int(out_ctx.han_deltas.get(2, 0)), 0, "高点棒不触发")

func test_shichu_no_effect_when_other_seat_wins():
	# owner=2 点棒低，但 seat 0 胡 → 不触发
	var ctx := _setup_with_score(2, 3000)
	var reg: SkillRegistry = ctx[0]
	var sched: SkillScheduler = ctx[2]
	var ab := _make_ability()
	reg.register(ab, 2)
	var out_ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 0))
	assert_eq(int(out_ctx.han_deltas.get(0, 0)), 0, "actor=0 ≠ owner=2 不触发")
	assert_eq(int(out_ctx.han_deltas.get(2, 0)), 0, "owner 也不会被加番")
