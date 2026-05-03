extends GutTest

# 麻将王 — M7 ctx 扩展 B3-mini：ensure_mangan_for_seat。

# ---- ctx API 行为 ----

func test_ensure_mangan_marks_seat():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	ctx.ensure_mangan_for_seat(0)
	assert_true(bool(ctx.mangan_floor_seats.get(0, false)))
	assert_false(bool(ctx.mangan_floor_seats.get(1, false)), "其它 seat 不影响")

func test_ensure_mangan_invalid_seat_safe():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	ctx.ensure_mangan_for_seat(-1)
	ctx.ensure_mangan_for_seat(4)
	assert_false(ctx.mangan_floor_seats.has(-1))
	assert_false(ctx.mangan_floor_seats.has(4))

# ---- BattleController._has_mangan_floor / _apply_mangan_floor ----

func test_has_mangan_floor_returns_false_for_empty():
	assert_false(BattleController._has_mangan_floor(0, []))

func test_has_mangan_floor_detects_marked_seat():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var c := SkillCtx.new(st, ev)
	c.ensure_mangan_for_seat(2)
	assert_true(BattleController._has_mangan_floor(2, [c]))
	assert_false(BattleController._has_mangan_floor(0, [c]), "其它 seat 不命中")

func test_apply_mangan_floor_below_threshold_pads_to_5():
	var yl := YakuList.new()
	yl.add_yaku(&"riichi", 1)
	yl.dora_count = 1
	# total_han = 2，< 5
	BattleController._apply_mangan_floor(yl)
	assert_eq(yl.total_han(), 5, "补差到 5 番（满贯阈值）")

func test_apply_mangan_floor_at_threshold_no_op():
	var yl := YakuList.new()
	# 5 番 = 已满贯
	for _i in range(5):
		yl.add_yaku(&"some_yaku", 1)
	var size_before := yl.yaku.size()
	BattleController._apply_mangan_floor(yl)
	assert_eq(yl.yaku.size(), size_before, "已满贯不补差")
	assert_eq(yl.total_han(), 5)

func test_apply_mangan_floor_above_threshold_no_op():
	var yl := YakuList.new()
	for _i in range(8):
		yl.add_yaku(&"some_yaku", 1)
	BattleController._apply_mangan_floor(yl)
	assert_eq(yl.total_han(), 8, "已超满贯不动")

# ---- 集成：white_mangan_floor 经 BattleController 计入 score ----
# （end-to-end 的"实际胡牌经 ScoreCalc"测试见 test_haitei_houtei_emit；
# 此处只验证 ctx-level 标记能被 _has_mangan_floor 正确读到）

func test_ensure_mangan_marked_in_ctx_recoverable_by_helper():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 1)
	var c := SkillCtx.new(st, ev)
	c.ensure_mangan_for_seat(1)
	# 在多个 ctx 数组里也能找到
	assert_true(BattleController._has_mangan_floor(1, [null, c, null]))
