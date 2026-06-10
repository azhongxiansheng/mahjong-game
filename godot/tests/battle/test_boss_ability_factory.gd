extends GutTest

# 麻将王 — M6 收尾：BossAbilityFactory 单测

func test_known_boss_ids_are_6():
	# 3 章原版 Boss + M12 3 个变体（commit 77d1435）
	var ids := BossAbilityFactory.known_boss_ids()
	assert_eq(ids.size(), 6, "3 章 Boss + 3 变体")
	assert_true(ids.has(&"boss1_iron_curtain_v1"))
	assert_true(ids.has(&"boss2_fortune_runner_v1"))
	assert_true(ids.has(&"boss3_kanmon_v1"))
	assert_true(ids.has(&"boss1_stealth_wall_v1"))
	assert_true(ids.has(&"boss2_dora_thief_v1"))
	assert_true(ids.has(&"boss3_yakuman_pressure_v1"))

func test_build_boss1_returns_skill_with_ron_trigger():
	var sk: SkillResource = BossAbilityFactory.build(&"boss1_iron_curtain_v1")
	assert_not_null(sk)
	assert_true(sk.is_ability)
	assert_eq(sk.id, &"boss1_iron_curtain_v1")
	assert_true(sk.owner_triggers.has(&"RON_DECLARED"))
	assert_not_null(sk.hook_script, "hook_script 来自 CardPool.hook_resource_path")

func test_build_boss2_returns_skill_with_win_pre_trigger():
	# M7：boss2 改用 WIN_DECLARED_PRE 让 +2 番在 ScoreCalc 之前应用
	var sk: SkillResource = BossAbilityFactory.build(&"boss2_fortune_runner_v1")
	assert_not_null(sk)
	assert_true(sk.owner_triggers.has(&"WIN_DECLARED_PRE"))

func test_build_boss3_returns_skill_with_haitei_houtei_triggers():
	var sk: SkillResource = BossAbilityFactory.build(&"boss3_kanmon_v1")
	assert_not_null(sk)
	assert_true(sk.owner_triggers.has(&"HAITEI"))
	assert_true(sk.owner_triggers.has(&"HOUTEI"))

func test_build_unknown_boss_returns_null():
	assert_null(BossAbilityFactory.build(&"unknown_boss_v1"))

func test_build_empty_id_returns_null():
	assert_null(BossAbilityFactory.build(&""))

# ---- inject ----

func test_inject_registers_boss_to_registry():
	var reg := SkillRegistry.new()
	var ok := BossAbilityFactory.inject(reg, &"boss1_iron_curtain_v1", 1)
	assert_true(ok)
	var entries: Array = reg.get_all_entries()
	assert_eq(entries.size(), 1)
	assert_eq(int(entries[0].anchor), 1, "anchor 是 seat 1")
	assert_eq(StringName(entries[0].skill.id), &"boss1_iron_curtain_v1")

func test_inject_unknown_boss_returns_false_and_no_register():
	var reg := SkillRegistry.new()
	var ok := BossAbilityFactory.inject(reg, &"unknown_boss_v1")
	assert_false(ok)
	assert_eq(reg.get_all_entries().size(), 0)

# ---- 集成：boss inject 后真实触发 ----

func test_inject_boss1_then_emit_ron_cancels():
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"boss1_iron_curtain_v1", 1)
	sched.emit_event(BattleEvent.make(&"RON_DECLARED", 0, null, {"discarder_seat": 1}))
	assert_true(st.ron_cancelled[0], "Boss(seat 1) 出铳被 actor=0 荣胡 → cancel")

func test_inject_boss2_then_emit_win_pre_marks_2_extra_dora():
	# M7 B2：boss2 已升级到 mark_extra_dora_for_seat（替代 add_han）
	var reg := SkillRegistry.new()
	var st := BattleState.new()
	var sched := SkillScheduler.new(reg, st)
	BossAbilityFactory.inject(reg, &"boss2_fortune_runner_v1", 2)
	sched.emit_event(BattleEvent.make(&"WIN_DECLARED_PRE", 2))
	assert_eq(int(st.extra_dora_count[2]), 2)
