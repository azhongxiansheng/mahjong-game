extends GutTest

# 麻将王 — M7 ctx 扩展 B3-mini：multiply_han_for_seat。

# ---- ctx API 行为 ----

func test_multiply_han_default_unset_is_1():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	assert_eq(float(ctx.han_multipliers.get(0, 1.0)), 1.0)

func test_multiply_han_simple():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	ctx.multiply_han_for_seat(1, 2.0)
	assert_eq(float(ctx.han_multipliers.get(1, 1.0)), 2.0)

func test_multiply_han_stacks():
	# 多个 hook 叠加 ×2 + ×1.5 = ×3
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	ctx.multiply_han_for_seat(2, 2.0)
	ctx.multiply_han_for_seat(2, 1.5)
	assert_eq(float(ctx.han_multipliers.get(2, 1.0)), 3.0)

func test_multiply_han_only_target_seat():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	ctx.multiply_han_for_seat(0, 2.0)
	assert_eq(float(ctx.han_multipliers.get(0, 1.0)), 2.0)
	assert_eq(float(ctx.han_multipliers.get(1, 1.0)), 1.0)

func test_multiply_han_invalid_seat_safe():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	ctx.multiply_han_for_seat(-1, 5.0)
	ctx.multiply_han_for_seat(4, 5.0)
	assert_false(ctx.han_multipliers.has(-1))
	assert_false(ctx.han_multipliers.has(4))

# ---- BattleController._apply_han_multiplier ----

func test_apply_han_multiplier_factor_1_no_op():
	var yl := YakuList.new()
	yl.add_yaku(&"riichi", 1)
	yl.add_yaku(&"tanyao", 1)
	BattleController._apply_han_multiplier(yl, 1.0)
	assert_eq(yl.total_han(), 2, "factor=1.0 不操作")
	assert_eq(yl.yaku.size(), 2)

func test_apply_han_multiplier_factor_2_doubles():
	var yl := YakuList.new()
	yl.add_yaku(&"riichi", 1)
	yl.add_yaku(&"tanyao", 1)
	yl.dora_count = 1  # +1
	# total_han = 2 + 1 = 3
	BattleController._apply_han_multiplier(yl, 2.0)
	# 加 (2-1)*3 = 3 → 总 6
	assert_eq(yl.total_han(), 6)

func test_apply_han_multiplier_factor_below_1_no_op():
	# < 1.0 不操作（避免 ScoreFormula 钳制 < 0 番时混乱）
	var yl := YakuList.new()
	yl.add_yaku(&"riichi", 2)
	BattleController._apply_han_multiplier(yl, 0.5)
	assert_eq(yl.total_han(), 2)

# ---- _composite_multiplier ----

func test_composite_multiplier_empty_array():
	assert_eq(BattleController._composite_multiplier(0, []), 1.0)

func test_composite_multiplier_with_null_safe():
	assert_eq(BattleController._composite_multiplier(0, [null, null]), 1.0)

func test_composite_multiplier_multiple_ctxs():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var c1 := SkillCtx.new(st, ev)
	c1.multiply_han_for_seat(0, 2.0)
	var c2 := SkillCtx.new(st, ev)
	c2.multiply_han_for_seat(0, 1.5)
	# 2.0 × 1.5 = 3.0
	assert_eq(BattleController._composite_multiplier(0, [c1, c2]), 3.0)

func test_composite_multiplier_only_winner_seat():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var c1 := SkillCtx.new(st, ev)
	c1.multiply_han_for_seat(1, 99.0)  # 不是 winner
	c1.multiply_han_for_seat(2, 99.0)
	assert_eq(BattleController._composite_multiplier(0, [c1]), 1.0)
