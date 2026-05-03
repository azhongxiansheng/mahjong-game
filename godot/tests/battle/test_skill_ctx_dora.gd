extends GutTest

# 麻将王 — M7 ctx 扩展 B2：Dora 系（mark_extra_dora_for_seat / mark_red_dora_for_seat）。
#
# 验证：
# 1. ctx API 语义（累加到 BattleState 对应数组）
# 2. BattleController 在 ScoreCalc 之前正确把 winner seat 的累计加到
#    yaku_list.dora_count（_apply_extra_dora 私有 helper 间接通过端到端
#    集成测试覆盖 — 见 test_haitei_houtei_emit）

# ---- mark_extra_dora_for_seat ----

func test_mark_extra_dora_accumulates():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	assert_eq(int(st.extra_dora_count[0]), 0, "初始 0")
	ctx.mark_extra_dora_for_seat(0, 1)
	assert_eq(int(st.extra_dora_count[0]), 1)
	ctx.mark_extra_dora_for_seat(0, 2)
	assert_eq(int(st.extra_dora_count[0]), 3, "累加：1 + 2 = 3")

func test_mark_extra_dora_default_count_is_1():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	ctx.mark_extra_dora_for_seat(2)  # 无 count 参数 → 默认 1
	assert_eq(int(st.extra_dora_count[2]), 1)

func test_mark_extra_dora_only_target_seat():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	ctx.mark_extra_dora_for_seat(1, 2)
	assert_eq(int(st.extra_dora_count[0]), 0)
	assert_eq(int(st.extra_dora_count[1]), 2)
	assert_eq(int(st.extra_dora_count[2]), 0)
	assert_eq(int(st.extra_dora_count[3]), 0)

func test_mark_extra_dora_invalid_seat_safe():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	# seat -1 / 4 都越界 → 安全返回（不修改任何 seat）
	ctx.mark_extra_dora_for_seat(-1, 5)
	ctx.mark_extra_dora_for_seat(4, 5)
	for i in range(4):
		assert_eq(int(st.extra_dora_count[i]), 0)

# ---- mark_red_dora_for_seat ----

func test_mark_red_dora_accumulates():
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	ctx.mark_red_dora_for_seat(3, 1)
	ctx.mark_red_dora_for_seat(3, 1)
	assert_eq(int(st.extra_red_dora_count[3]), 2)

func test_mark_red_dora_separate_bucket_from_normal():
	# red dora 与普通 extra dora 各走自己的字段（便于未来上限审计）
	var st := BattleState.new()
	var ev := BattleEvent.make(&"WIN_DECLARED_PRE", 0)
	var ctx := SkillCtx.new(st, ev)
	ctx.mark_extra_dora_for_seat(0, 1)
	ctx.mark_red_dora_for_seat(0, 1)
	assert_eq(int(st.extra_dora_count[0]), 1, "普通 dora 桶")
	assert_eq(int(st.extra_red_dora_count[0]), 1, "赤 dora 桶")

# ---- 集成：dora_count 加到 yaku_list ----

func test_apply_extra_dora_boosts_yaku_list_dora_count():
	# 直接验证 BattleController._apply_extra_dora 行为
	var bc := BattleController.new(42, 0)
	bc.state.extra_dora_count[0] = 3
	bc.state.extra_red_dora_count[0] = 2
	var yl := YakuList.new()
	yl.dora_count = 1  # 已有 1 张普通 dora（visible indicator）
	bc._apply_extra_dora(yl, 0)
	assert_eq(yl.dora_count, 6, "1 base + 3 extra + 2 red = 6 番（含 dora）")

func test_apply_extra_dora_only_winner_seat_applied():
	var bc := BattleController.new(42, 0)
	bc.state.extra_dora_count[1] = 5
	bc.state.extra_dora_count[3] = 99
	var yl := YakuList.new()
	yl.dora_count = 0
	bc._apply_extra_dora(yl, 0)  # winner = 0
	assert_eq(yl.dora_count, 0, "winner=0 没 extra dora，不混合其它座位")
