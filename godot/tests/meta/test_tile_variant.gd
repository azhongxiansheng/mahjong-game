extends GutTest

# 当前图鉴与牌桌技能共用的 TileVariant + AbilityCard 单测

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
