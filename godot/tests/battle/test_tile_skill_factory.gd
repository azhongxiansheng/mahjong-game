extends GutTest

# 麻将王 — M7：TileSkillFactory 单测。
#
# 验证玩家 deck.tile_variants → SkillRegistry 注册路径正确，hook 可在
# 真战斗（端到端）fire。

# ---- 已知 variant 列表 ----

func test_known_variant_ids_covers_all_28():
	# CardPool 注册 28 张技能牌；factory 应全覆盖
	var ids := TileSkillFactory.known_variant_ids()
	assert_eq(ids.size(), 28, "TileSkillFactory 覆盖全部 28 张 v1 技能牌")

func test_known_variants_match_card_pool():
	# 完整性：factory 知道的每个 variant 都能在 CardPool 找到
	var pool_ids: Dictionary = {}
	for v in CardPool.all_tile_variants():
		pool_ids[v.id] = true
	for vid in TileSkillFactory.known_variant_ids():
		assert_true(pool_ids.has(vid), "factory 中 %s 应在 CardPool" % vid)

# ---- build ----

func test_build_thunder_5w_uses_owner_win_pre():
	var sk: SkillResource = TileSkillFactory.build(&"thunder_5w_v1")
	assert_not_null(sk)
	assert_false(sk.is_ability)
	assert_eq(sk.attached_tile, TileId.W5)
	assert_true(sk.owner_triggers.has(&"WIN_DECLARED_PRE"))
	assert_true(sk.holder_triggers.is_empty())

func test_build_seal_chun_uses_owner_ron():
	var sk: SkillResource = TileSkillFactory.build(&"seal_chun_v1")
	assert_not_null(sk)
	assert_eq(sk.attached_tile, TileId.CHUN)
	assert_true(sk.owner_triggers.has(&"RON_DECLARED"))

func test_build_soul_drain_uses_holder_win_post():
	# transfer_points 用 points_won → 必须 post-score 事件
	var sk: SkillResource = TileSkillFactory.build(&"soul_drain_hatsu_v1")
	assert_not_null(sk)
	assert_eq(sk.attached_tile, TileId.HATSU)
	assert_true(sk.owner_triggers.is_empty())
	assert_true(sk.holder_triggers.has(&"WIN_DECLARED"))

func test_build_pin9_haitei_uses_holder_haitei_houtei():
	var sk: SkillResource = TileSkillFactory.build(&"pin9_haitei_double_v1")
	assert_not_null(sk)
	assert_true(sk.holder_triggers.has(&"HAITEI"))
	assert_true(sk.holder_triggers.has(&"HOUTEI"))

func test_build_xray_uses_owner_tile_drawn():
	var sk: SkillResource = TileSkillFactory.build(&"xray_1w_v1")
	assert_not_null(sk)
	assert_true(sk.owner_triggers.has(&"TILE_DRAWN"))

func test_build_unknown_variant_returns_null():
	assert_null(TileSkillFactory.build(&"unknown_v1"))

# ---- inject_one ----

func test_inject_one_registers_with_tile_anchor():
	var reg := SkillRegistry.new()
	var ok := TileSkillFactory.inject_one(reg, &"thunder_5w_v1", 0)
	assert_true(ok)
	var entries: Array = reg.get_all_entries()
	assert_eq(entries.size(), 1)
	var anchor = entries[0].anchor
	assert_true(anchor is TileInstance)
	assert_eq(anchor.owner_seat, 0)
	assert_eq(anchor.tile.id, TileId.W5)

func test_inject_one_holder_skill_sets_holder_seat():
	# soul_drain_hatsu 是 holder skill；anchor.holder_seat 也应被设
	var reg := SkillRegistry.new()
	TileSkillFactory.inject_one(reg, &"soul_drain_hatsu_v1", 2)
	var entries: Array = reg.get_all_entries()
	assert_eq(entries.size(), 1)
	var anchor = entries[0].anchor
	assert_eq(anchor.owner_seat, 2)
	assert_eq(anchor.holder_seat, 2)

# ---- inject_player_tile_variants（批量）----

func test_inject_batch_with_variant_objects():
	# 模拟 Deck.tile_variants：{tile_id: TileVariant 对象}
	var reg := SkillRegistry.new()
	var variants: Dictionary = {}
	# 用 CardPool 实际取 variant 对象
	for v in CardPool.all_tile_variants():
		if v.id == &"thunder_5w_v1":
			variants[v.tile_id] = v
		elif v.id == &"seal_chun_v1":
			variants[v.tile_id] = v
	var n := TileSkillFactory.inject_player_tile_variants(reg, variants, 0)
	assert_eq(n, 2)
	assert_eq(reg.get_all_entries().size(), 2)

func test_inject_batch_with_string_ids():
	# variant id 字典输入
	var reg := SkillRegistry.new()
	var variants: Dictionary = {
		TileId.W5: &"thunder_5w_v1",
		TileId.CHUN: &"seal_chun_v1",
	}
	var n := TileSkillFactory.inject_player_tile_variants(reg, variants, 0)
	assert_eq(n, 2)

func test_inject_batch_skips_unknown():
	var reg := SkillRegistry.new()
	var variants: Dictionary = {
		TileId.W5: &"thunder_5w_v1",
		TileId.W2: &"unknown_v1",
	}
	var n := TileSkillFactory.inject_player_tile_variants(reg, variants, 0)
	assert_eq(n, 1, "未知静默跳过")

func test_inject_batch_empty():
	var reg := SkillRegistry.new()
	var n := TileSkillFactory.inject_player_tile_variants(reg, {}, 0)
	assert_eq(n, 0)

# ---- 集成：注册后真触发 ----

func test_thunder_5w_inject_then_emit_wins_with_skill_bonus():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"thunder_5w_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	# thunder_5w +2 番 (tune-2 后 BalanceConstants 1 → 2)
	assert_eq(int(ctx.han_deltas.get(0, 0)), 2)

func test_seal_chun_inject_then_ron_cancels():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"seal_chun_v1", 0)
	# discarder = owner = 0 → cancel ron from actor=2
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 2, null, {"discarder_seat": 0}))
	assert_true(st.ron_cancelled[2])
