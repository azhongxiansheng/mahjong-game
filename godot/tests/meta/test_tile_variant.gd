extends GutTest

# 麻将王 — M5 第 1 步：TileVariant + AbilityCard + GachaResult 单测

# ---- TileVariant ----

func test_tile_variant_default_no_skill():
	var v := TileVariant.new(&"x", TileId.W5)
	assert_false(v.has_skill())

func test_tile_variant_has_skill_when_path_set():
	var v := TileVariant.new(&"x", TileId.W5)
	v.skill_resource_path = "res://skills/hooks/x.gd"
	assert_true(v.has_skill())

func test_tile_variant_summary_includes_rarity():
	var v := TileVariant.new(&"thunder", TileId.W5, Rarity.Kind.EPIC)
	v.display_name = "5万·闪电"
	assert_true(v.summary().find("史诗") >= 0)
	assert_true(v.summary().find("5万·闪电") >= 0)

func test_tile_variant_summary_falls_back_to_id():
	var v := TileVariant.new(&"raw_id", TileId.W5)
	# 不设 display_name
	assert_true(v.summary().find("raw_id") >= 0)

# ---- AbilityCard ----

func test_ability_card_summary_marks_role_ability():
	var a := AbilityCard.new(&"seabed", Rarity.Kind.LEGENDARY)
	a.display_name = "海底狩人"
	assert_true(a.summary().find("角色能力") >= 0, "summary 应显式标'角色能力'")
	assert_true(a.summary().find("神话") >= 0)

# ---- GachaResult ----

func test_gacha_result_make_tile():
	var v := TileVariant.new(&"v1", TileId.W5, Rarity.Kind.UNCOMMON)
	var r := GachaResult.make_tile(v)
	assert_eq(r.kind, GachaResult.KIND_TILE)
	assert_eq(r.tile_variant, v)
	assert_eq(r.rarity, Rarity.Kind.UNCOMMON)
	assert_null(r.ability)

func test_gacha_result_make_ability():
	var a := AbilityCard.new(&"a1", Rarity.Kind.EPIC)
	var r := GachaResult.make_ability(a)
	assert_eq(r.kind, GachaResult.KIND_ABILITY)
	assert_eq(r.ability, a)
	assert_eq(r.rarity, Rarity.Kind.EPIC)
	assert_null(r.tile_variant)

func test_gacha_result_summary_for_tile():
	var v := TileVariant.new(&"v1", TileId.W5, Rarity.Kind.COMMON)
	v.display_name = "占位牌"
	var r := GachaResult.make_tile(v)
	assert_eq(r.summary(), v.summary())

func test_gacha_result_summary_empty():
	# 空 GachaResult.new() 不带 tile/ability
	var r := GachaResult.new()
	assert_true(r.summary().find("空") >= 0)
