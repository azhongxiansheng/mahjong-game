extends GutTest

# 麻将王 — M5 第 1 步：CardPool v1 hardcoded 单测

func test_all_tile_variants_non_empty():
	var pool: Array = CardPool.all_tile_variants()
	assert_gt(pool.size(), 30, "v1 池子至少 30+ 张占位 + demo")

func test_all_tile_variants_each_has_valid_tile_id():
	for v in CardPool.all_tile_variants():
		assert_gte(v.tile_id, 0)
		assert_lt(v.tile_id, 34)

func test_each_rarity_has_at_least_one_tile_variant():
	# v1 池子需保证每档稀有度至少 1 张牌（避免抽卡走 fallback）
	for r in range(Rarity.COUNT):
		var pool: Array = CardPool.tile_variants_by_rarity(r)
		assert_gt(pool.size(), 0, "rarity=%d 应至少有 1 张牌" % r)

func test_demo_skill_tiles_present():
	# M1 5 个 demo skill 应都在池子里
	var pool: Array = CardPool.all_tile_variants()
	var ids: Dictionary = {}
	for v in pool:
		ids[v.id] = true
	for required_id in [&"thunder_5w_v1", &"seal_chun_v1", &"soul_drain_hatsu_v1", &"xray_1w_v1", &"unfuriten_5p_v1"]:
		assert_true(ids.has(required_id), "M1 demo %s 应在池子里" % required_id)

func test_demo_skill_tiles_have_skill_path():
	# demo 牌 has_skill() 应为 true（区分占位无技能牌）
	for v in CardPool.all_tile_variants():
		if v.id == &"thunder_5w_v1":
			assert_true(v.has_skill(), "thunder_5w_v1 应带技能")
			return
	assert_true(false, "thunder_5w_v1 找不到")

func test_placeholder_tiles_have_no_skill():
	for v in CardPool.all_tile_variants():
		if String(v.id).begins_with("placeholder_"):
			assert_false(v.has_skill(), "占位牌不带技能")

# ---- abilities ----

func test_all_abilities_non_empty():
	assert_gt(CardPool.all_abilities().size(), 1)

func test_seabed_hunter_ability_present():
	var ids: Dictionary = {}
	for a in CardPool.all_abilities():
		ids[a.id] = true
	assert_true(ids.has(&"seabed_hunter_v1"))

func test_each_rarity_has_at_least_one_ability_with_fallback():
	# M6 内容生产：5 张 COMMON 占位 ability 已被真实 EPIC/LEGENDARY 替换；
	# 至少 EPIC 与 LEGENDARY 各 1（spec §10 ability 槽位强制高质量）。
	assert_gt(CardPool.abilities_by_rarity(Rarity.Kind.EPIC).size(), 0)
	assert_gt(CardPool.abilities_by_rarity(Rarity.Kind.LEGENDARY).size(), 0)
