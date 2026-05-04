extends GutTest

# 麻将王 — M9 ctx B3：force_yakuman_for_seat。

# ---- ctx API 行为 ----

func test_force_yakuman_marks_seat():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	ctx.force_yakuman_for_seat(0)
	assert_true(bool(ctx.yakuman_force_seats.get(0, false)))
	assert_false(bool(ctx.yakuman_force_seats.get(1, false)), "其它 seat 不影响")

func test_force_yakuman_invalid_seat_safe():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	ctx.force_yakuman_for_seat(-1)
	ctx.force_yakuman_for_seat(4)
	assert_false(ctx.yakuman_force_seats.has(-1))
	assert_false(ctx.yakuman_force_seats.has(4))

# ---- BattleController helper ----

func test_has_yakuman_force_returns_false_for_empty():
	assert_false(BattleController._has_yakuman_force(0, []))

func test_has_yakuman_force_detects_marked_seat():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var c := SkillCtx.new(st, ev)
	c.force_yakuman_for_seat(2)
	assert_true(BattleController._has_yakuman_force(2, [c]))
	assert_false(BattleController._has_yakuman_force(0, [c]))

func test_apply_yakuman_force_sets_flag_and_multiplier():
	var yl := YakuList.new()
	yl.add_yaku(&"riichi", 1)
	BattleController._apply_yakuman_force(yl)
	assert_true(yl.is_yakuman, "is_yakuman 置 true")
	assert_eq(yl.yakuman_multiplier, 1, "yakuman_multiplier ≥ 1")

func test_apply_yakuman_force_preserves_existing_higher_multiplier():
	# 已是 ×2 役满（如 spec §14 yakuman_multiplier_cap），force 不降低
	var yl := YakuList.new()
	yl.is_yakuman = true
	yl.yakuman_multiplier = 2
	BattleController._apply_yakuman_force(yl)
	assert_eq(yl.yakuman_multiplier, 2, "已 ×2 不降到 1")

func test_apply_yakuman_force_to_non_yakuman_hand():
	# 非役满手牌（无 yaku）→ force 后 is_yakuman=true, multiplier=1
	var yl := YakuList.new()
	BattleController._apply_yakuman_force(yl)
	assert_true(yl.is_yakuman)
	assert_eq(yl.yakuman_multiplier, 1)

# ---- 跨多 ctx 检测 ----

func test_has_yakuman_force_across_multiple_ctxs():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var c1 := SkillCtx.new(st, ev)  # 不标
	var c2 := SkillCtx.new(st, ev)
	c2.force_yakuman_for_seat(1)
	assert_true(BattleController._has_yakuman_force(1, [c1, c2]))
	assert_true(BattleController._has_yakuman_force(1, [null, c2]))
