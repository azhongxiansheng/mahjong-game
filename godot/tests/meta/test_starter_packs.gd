extends GutTest

# 麻将王 — M4 第 2 步 / M6 内容生产：StarterPacks 单测

# ---- 三套起始包基本结构 ----

func test_three_packs_total():
	assert_eq(StarterPacks.all().size(), 3, "spec §7.2 三套起始包")

func test_three_packs_all_available_in_m6():
	# M6 内容生产：3 套都已 available
	var avail: Array = StarterPacks.available()
	assert_eq(avail.size(), 3)

func test_pack_data_shape_complete():
	# 每个 pack dict 含 id / display_name / description / tile_variants /
	# abilities / available
	for p in StarterPacks.all():
		assert_true(p.has("id"))
		assert_true(p.has("display_name"))
		assert_true(p.has("description"))
		assert_true(p.has("tile_variants"))
		assert_true(p.has("abilities"))
		assert_true(p.has("available"))

# ---- pack id 唯一性 ----

func test_pack_ids_are_unique():
	var seen: Dictionary = {}
	for p in StarterPacks.all():
		assert_false(seen.has(p.id), "重复 pack id: %s" % p.id)
		seen[p.id] = true

# ---- 单 pack 内容 ----

func test_control_pack_id_and_name():
	var p: Dictionary = StarterPacks.control_pack()
	assert_eq(p.id, &"starter_control")
	assert_eq(p.display_name, "控场型")
	assert_true(p.available)

func test_aggro_and_fast_packs_available_in_m6():
	# M6：3 套全部 available
	assert_true(StarterPacks.aggro_pack().available)
	assert_true(StarterPacks.fast_pack().available)

# ---- apply_to RunState ----

func test_apply_control_pack_sets_run_deck():
	var rs := RunState.new(42)
	assert_true(StarterPacks.apply_to(rs, &"starter_control"))
	assert_eq(rs.deck.get("pack_id"), &"starter_control")
	assert_true(rs.deck.has("tile_variants"))
	assert_true(rs.deck.has("abilities"))

func test_apply_aggro_pack_now_succeeds():
	# M6 内容生产：aggro 已 available，apply_to 应成功
	var rs := RunState.new(42)
	assert_true(StarterPacks.apply_to(rs, &"starter_aggro"))
	assert_eq(rs.deck.get("pack_id"), &"starter_aggro")

func test_apply_unknown_pack_id_returns_false():
	var rs := RunState.new(42)
	assert_false(StarterPacks.apply_to(rs, &"starter_unknown"))
	assert_false(rs.deck.has("pack_id"))

# ---- M6: pack 内容真实化 ----

func test_control_pack_m6_has_content():
	# M6：control_pack 已填真实 tile_variants 与 abilities
	var p: Dictionary = StarterPacks.control_pack()
	assert_gt(p.tile_variants.size(), 0, "M6 tile_variants 已填")
	assert_gt(p.abilities.size(), 0, "M6 abilities 已填")

func test_apply_real_pack_populates_player_deck():
	# M6: apply_to 在 player_deck 上注册卡
	var rs := RunState.new(42)
	StarterPacks.apply_to(rs, &"starter_control")
	assert_gt(rs.player_deck.tile_variant_count(), 0, "control pack 至少 1 张牌")
	assert_gt(rs.player_deck.ability_count(), 0, "control pack 至少 1 角色能力")
