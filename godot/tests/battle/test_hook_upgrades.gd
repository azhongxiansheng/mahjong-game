extends GutTest

# 麻将王 — stub hook 升级验证（v2 真实效果）


# ============================================================
# sou4_uradora_pick: add_han → mark_extra_dora
# ============================================================

func test_sou4_marks_dora_instead_of_han():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"sou4_uradora_pick_v1", 0)
	var ctx := sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	# v2: 应走 mark_extra_dora 而非 add_han
	assert_gt(st.extra_dora_count[0], 0, "sou4 应增加 extra_dora_count")
	assert_eq(int(ctx.han_deltas.get(0, 0)), 0, "sou4 不应直接 add_han")

func test_sou4_wrong_actor_no_effect():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"sou4_uradora_pick_v1", 0)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1))
	assert_eq(st.extra_dora_count[0], 0, "非 owner 自胡时不增 dora")


# ============================================================
# hatsu_stick_refund: add_han → transfer_points
# ============================================================

func test_hatsu_transfers_points():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"hatsu_stick_refund_v1", 0)
	var before_0: int = st.scores[0]
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_gt(st.scores[0], before_0, "hatsu_stick_refund 应给 owner 增分")
	assert_eq(int(st.han_deltas.get(0, 0) if st.has_method("han_deltas") else 0), 0)

func test_hatsu_takes_from_lowest_score_opponent():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	# 设置不同分数
	st.scores[0] = 25000
	st.scores[1] = 20000
	st.scores[2] = 30000
	st.scores[3] = 15000  # 最低
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"hatsu_stick_refund_v1", 0)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 0))
	assert_eq(st.scores[3], 14000, "应从最低分对手 seat 3 扣 1000")
	assert_eq(st.scores[0], 26000, "owner 应得 1000")


# ============================================================
# sou8_scapegoat: add_han(-1) → transfer_points
# ============================================================

func test_sou8_transfers_from_highest_opponent():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	st.scores[0] = 25000  # owner (放铳方)
	st.scores[1] = 25000  # winner
	st.scores[2] = 30000  # 最高分非胜者/非owner
	st.scores[3] = 20000
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"sou8_scapegoat_v1", 0)
	# actor=1 是胜者，discarder=0 是 owner
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1, null, {"discarder_seat": 0}))
	assert_eq(st.scores[2], 28000, "应从最高分第三方 seat 2 扣 2000")
	assert_eq(st.scores[0], 27000, "owner 应得 2000")

func test_sou8_wrong_discarder_no_effect():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var before := st.scores.duplicate()
	var sched := SkillScheduler.new(reg, st)
	TileSkillFactory.inject_one(reg, &"sou8_scapegoat_v1", 0)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 1, null, {"discarder_seat": 2}))
	assert_eq(st.scores, before, "非 owner 放铳时不触发")


# ============================================================
# 全套回归：升级后战斗仍然正常完成 + 守恒
# ============================================================

func test_upgraded_hooks_battle_conserves():
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	var ability_ids: Array = []
	for a in rs.player_deck.abilities:
		ability_ids.append(a.id)
	for seed_val in [42, 99, 200]:
		var result: NodeResult = BattleNodeRunner.run_battle_to_node_result(
			seed_val, &"", ability_ids, false, rs.player_deck.tile_variants
		)
		assert_not_null(result)
		var sum := 0
		for s in result.final_scores:
			sum += int(s)
		assert_eq(sum, 100000, "seed %d 守恒" % seed_val)
