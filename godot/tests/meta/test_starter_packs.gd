extends GutTest

# 麻将王 — M4 第 2 步：StarterPacks 单测

# ---- 三套起始包基本结构 ----

func test_three_packs_total():
	assert_eq(StarterPacks.all().size(), 3, "spec §7.2 三套起始包")

func test_only_control_pack_available_in_v1():
	# plan-4 D7：v1 仅控场型有效，其余 2 套 M6 实装
	var avail: Array = StarterPacks.available()
	assert_eq(avail.size(), 1)
	assert_eq(avail[0].id, &"starter_control")

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

func test_aggro_and_fast_packs_unavailable_in_v1():
	assert_false(StarterPacks.aggro_pack().available)
	assert_false(StarterPacks.fast_pack().available)

# ---- apply_to RunState ----

func test_apply_control_pack_sets_run_deck():
	var rs := RunState.new(42)
	assert_true(StarterPacks.apply_to(rs, &"starter_control"))
	assert_eq(rs.deck.get("pack_id"), &"starter_control")
	assert_true(rs.deck.has("tile_variants"))
	assert_true(rs.deck.has("abilities"))

func test_apply_unavailable_pack_returns_false():
	var rs := RunState.new(42)
	assert_false(StarterPacks.apply_to(rs, &"starter_aggro"))
	assert_false(rs.deck.has("pack_id"), "未应用，deck 不变")

func test_apply_unknown_pack_id_returns_false():
	var rs := RunState.new(42)
	assert_false(StarterPacks.apply_to(rs, &"starter_unknown"))
	assert_false(rs.deck.has("pack_id"))

# ---- v1 留空 deck 合法性 ----

func test_control_pack_v1_empty_deck_is_legal():
	# plan-4 D7：v1 留空数组 / 字典合法
	var p: Dictionary = StarterPacks.control_pack()
	assert_eq(p.tile_variants.size(), 0, "v1 tile_variants 留空")
	assert_eq(p.abilities.size(), 0, "v1 abilities 留空")
