extends GutTest

# 麻将王 — M7 baseline 5 假设 J/M：BossAbilityFactory.inject_random_ai_seat_abilities

func test_inject_random_ai_seat_abilities_default_3_seats():
	var reg := SkillRegistry.new()
	var n := BossAbilityFactory.inject_random_ai_seat_abilities(reg, 42)
	assert_eq(n, 3, "默认 3 个 AI seats（1/2/3）")
	assert_eq(reg.get_all_entries().size(), 3)
	# 验证 anchor 是 seat int 而非 TileInstance（ability path）
	for e in reg.get_all_entries():
		assert_true(e.anchor is int, "ability anchor 应为 seat int")
		var seat: int = e.anchor
		assert_true(seat >= 1 and seat <= 3, "应在 [1, 3] 范围")

func test_inject_random_ai_seat_abilities_excludes_boss():
	# Pool 排除 boss id；不会把 boss1/2/3 分配给 AI
	var reg := SkillRegistry.new()
	BossAbilityFactory.inject_random_ai_seat_abilities(reg, 42)
	for e in reg.get_all_entries():
		var sk_id: StringName = e.skill.id
		assert_false(BossAbilityFactory.known_boss_ids().has(sk_id),
			"AI seat 不应分到 Boss ability，得到 %s" % sk_id)

func test_inject_random_ai_seat_abilities_excludes_player_held():
	# excluded_ids 中的 id 不会出现
	var reg := SkillRegistry.new()
	var excluded: Array = [&"shichu_kyu_katsu_v1", &"san_kyoku_kiseki_v1", &"isshun_senken_v1"]
	BossAbilityFactory.inject_random_ai_seat_abilities(reg, 42, [1, 2, 3], excluded)
	for e in reg.get_all_entries():
		assert_false(excluded.has(e.skill.id),
			"被排除 id 不应出现：%s" % e.skill.id)

func test_inject_random_ai_seat_abilities_deterministic_by_seed():
	# 相同 seed → 相同 ability 序列
	var reg1 := SkillRegistry.new()
	var reg2 := SkillRegistry.new()
	BossAbilityFactory.inject_random_ai_seat_abilities(reg1, 42)
	BossAbilityFactory.inject_random_ai_seat_abilities(reg2, 42)
	var ids1: Array = []
	var ids2: Array = []
	for e in reg1.get_all_entries():
		ids1.append(e.skill.id)
	for e in reg2.get_all_entries():
		ids2.append(e.skill.id)
	assert_eq(ids1, ids2, "同 seed → 同 ability 序列")

func test_inject_random_ai_seat_abilities_different_seats():
	# 自定义 seat 列表
	var reg := SkillRegistry.new()
	var n := BossAbilityFactory.inject_random_ai_seat_abilities(reg, 1, [2, 3])
	assert_eq(n, 2, "只 inject 2 个 seat")
	for e in reg.get_all_entries():
		var seat: int = e.anchor
		assert_true(seat == 2 or seat == 3)
