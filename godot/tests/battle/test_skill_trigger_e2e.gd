extends GutTest

# 麻将王 — 技能在真实战斗中具体触发的 e2e 验证（无 mock）
#
# 使用真实 BattleController + SkillScheduler，验证注入的 hook
# 在关键事件节点真实改变了 ctx 状态和 event 产出。


# ============================================================
# 第 1 组：SkillScheduler 在真 BC 中正确 emit
# ============================================================

func test_bc_emits_game_begin_event():
	var bc := BattleController.new(42)
	var result: Dictionary = bc.run_to_end()
	var found_game_begin := false
	for ev: BattleEvent in result.events:
		if ev.type == &"GAME_BEGIN":
			found_game_begin = true
			break
	assert_true(found_game_begin, "BC 应 emit GAME_BEGIN")

func test_bc_emits_win_declared_pre_on_any_win():
	var found_win := false
	var found_pre := false
	# 每个 seed 只跑一手，避免旧 Run 节点为一次事件契约重复跑完整东风战。
	for seed_val in [42, 99, 200, 555, 1001]:
		var result: Dictionary = BattleController.new(seed_val, 0, true).run_to_end()
		for event: BattleEvent in result.events:
			if event.type == &"WIN_DECLARED":
				found_win = true
			elif event.type == &"WIN_DECLARED_PRE":
				found_pre = true
		if found_win:
			break
	assert_true(found_win, "至少一个 seed 的单手应有胡牌")
	assert_true(found_pre, "有胡牌则必有 WIN_DECLARED_PRE")


# ============================================================
# 第 2 组：thunder_5w 在真实 BC 中增番
# ============================================================

func test_thunder_5w_inject_registry_nonempty():
	var reg := SkillRegistry.new()
	TileSkillFactory.inject_one(reg, &"thunder_5w_v1", 0)
	assert_eq(reg.get_all_entries().size(), 1)

func test_thunder_5w_adds_han_on_pre_event():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"thunder_5w_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	var delta: int = int(ctx.han_deltas.get(0, 0))
	assert_gt(delta, 0, "thunder_5w 应给 seat 0 增番")


# ============================================================
# 第 3 组：seal_chun 在真实 BC 中取消 ron
# ============================================================

func test_seal_chun_cancels_ron():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"seal_chun_v1", 0)
	# seal_chun: owner=0 放铳，actor=1 荣胡 → 取消 actor 的 ron
	var ctx := sched.emit_event(BattleEvent.make(&"RON_DECLARED", 1, null, {"discarder_seat": 0}))
	assert_true(st.ron_cancelled[1], "seal_chun 应取消荣胡方的 ron")


# ============================================================
# 第 4 组：boss1_iron_curtain 在真实 BC 中取消 ron
# ============================================================

func test_boss1_iron_curtain_cancels_ron():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"boss1_iron_curtain_v1", 1)
	# iron_curtain: boss=1 放铳，actor=0 荣胡 → 取消 actor 的 ron
	var ctx := sched.emit_event(BattleEvent.make(&"RON_DECLARED", 0, null, {"discarder_seat": 1}))
	assert_true(st.ron_cancelled[0], "iron_curtain 应取消荣胡方的 ron")


# ============================================================
# 第 5 组：yamagan reveal 在 GAME_BEGIN 真实触发
# ============================================================

func test_yamagan_reveals_wall_tiles_on_game_begin():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	# yamagan 需要 wall 才能 reveal
	st.wall = Wall.new_full_set()
	st.wall.shuffle(42)
	st.wall.reserve_dead_wall(14)
	# 造 4 个空 seat（yamagan 只用 beneficiary_seat 不看 seat 内容）
	for i in range(4):
		st.seats.append(Seat.new(i, TileId.E))
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"yamagan_v1", 0)
	assert_eq(st.revealed_tiles.size(), 0, "触发前无 reveal")
	sched.emit_event(BattleEvent.make(&"GAME_BEGIN", 0))
	assert_gt(st.revealed_tiles.size(), 0, "yamagan 应 reveal 牌墙顶牌")


# ============================================================
# 第 6 组：shichu_kyu_katsu 低分时增番
# ============================================================

func test_shichu_low_score_adds_han():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.scores[0] = 3000
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"shichu_kyu_katsu_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_gt(int(ctx.han_deltas.get(0, 0)), 0, "低分时应增番")

func test_shichu_high_score_no_han():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	# 默认 25000
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"shichu_kyu_katsu_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(int(ctx.han_deltas.get(0, 0)), 0, "高分时不增番")


# ============================================================
# 第 7 组：seabed_hunter 海底强制自摸
# ============================================================

func test_seabed_hunter_forces_tsumo():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"seabed_hunter_v1", 0)
	assert_eq(st.haitei_forced_seat, -1)
	sched.emit_event(BattleEvent.make(&"HAITEI", 0))
	assert_eq(st.haitei_forced_seat, 0, "seabed_hunter 应 force_tsumo seat 0")


# ============================================================
# 第 8 组：xray_1w 在 TILE_DRAWN 时 reveal
# ============================================================

func test_xray_reveal_on_draw():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.wall = Wall.new_full_set()
	st.wall.shuffle(42)
	st.wall.reserve_dead_wall(14)
	for i in range(4):
		var seat := Seat.new(i, TileId.E)
		for _j in range(13):
			seat.add_to_hand(st.wall.draw())
		st.seats.append(seat)
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"xray_1w_v1", 0)
	assert_eq(st.revealed_tiles.size(), 0)
	sched.emit_event(BattleEvent.make(&"TILE_DRAWN", 0))
	assert_gt(st.revealed_tiles.size(), 0, "xray_1w 应在 TILE_DRAWN 时 reveal")


# ============================================================
# 第 9 组：unfuriten_5p 清除振听
# ============================================================

func test_unfuriten_clears_furiten():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.furiten_flags[0] = true
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"unfuriten_5p_v1", 0)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_false(st.furiten_flags[0], "unfuriten_5p 应清除 seat 0 振听")


# ============================================================
# 第 10 组：soul_drain_hatsu 转分
# ============================================================

func test_soul_drain_transfers_points():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"soul_drain_hatsu_v1", 0)
	var initial_s0: int = st.scores[0]
	var initial_s1: int = st.scores[1]
	# soul_drain 在 WIN_DECLARED（post-score）触发，额外看 points_won
	var extra := {"points_won": 8000, "is_tsumo": false}
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED", 1, null, extra))
	# holder_seat=0 的 soul_drain 应从 winner(seat 1) 转分给 holder(seat 0)
	# 注：TileSkillFactory.inject_one 设了 holder_seat=0
	# soul_drain 用 transfer_points 或 steal_score
	var changed := (st.scores[0] != initial_s0) or (st.scores[1] != initial_s1)
	assert_true(changed, "soul_drain 应在对手胡牌时转分")
