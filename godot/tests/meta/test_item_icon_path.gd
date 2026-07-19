extends GutTest

# icon_path：遗物/消耗品可选字段 + 默认资产路径解析

func test_relic_icon_path_roundtrip_and_default() -> void:
	var r := RelicItem.new(&"relic_lucky_cat_v1", Rarity.Kind.UNCOMMON)
	r.display_name = "招财猫"
	r.icon_path = "res://assets/roguelike/relics/relic_lucky_cat.png"
	var back := RelicItem.from_dict(r.to_dict())
	assert_eq(back.icon_path, r.icon_path)
	# 缺字段兼容旧存档
	var legacy := RelicItem.from_dict({"id": "relic_iron_will_v1", "rarity": 1})
	assert_eq(legacy.icon_path, "")
	assert_eq(RelicItem.default_icon_path(&"relic_lucky_cat_v1"),
		"res://assets/roguelike/relics/relic_lucky_cat.png")
	assert_true(ResourceLoader.exists(RelicItem.default_icon_path(&"relic_lucky_cat_v1")))

func test_consumable_icon_path_roundtrip_and_default() -> void:
	# 池内 id 是 wall_peek_v1，磁盘文件是 consumable_wall_peek.png
	var c := ConsumableItem.new(&"wall_peek_v1", ConsumableItem.Kind.BATTLE)
	c.icon_path = ConsumableItem.default_icon_path(c.id)
	var back := ConsumableItem.from_dict(c.to_dict())
	assert_eq(back.icon_path, c.icon_path)
	assert_eq(ConsumableItem.default_icon_path(&"wall_peek_v1"),
		"res://assets/roguelike/consumables/consumable_wall_peek.png")
	assert_true(ResourceLoader.exists(ConsumableItem.default_icon_path(&"wall_peek_v1")))

func test_default_icon_path_missing_returns_empty() -> void:
	assert_eq(RelicItem.default_icon_path(&"relic_no_such_thing_v1"), "")
	assert_eq(ConsumableItem.default_icon_path(&"no_such_consumable_v1"), "")

func test_newly_added_pool_icons_resolve() -> void:
	assert_true(ResourceLoader.exists(RelicItem.default_icon_path(&"relic_red_string_v1")))
	assert_true(ResourceLoader.exists(RelicItem.default_icon_path(&"relic_pity_breaker_v1")))
	assert_true(ResourceLoader.exists(ConsumableItem.default_icon_path(&"hp_potion_v1")))
	assert_true(ResourceLoader.exists(ConsumableItem.default_icon_path(&"tsubame_v1")))

func test_run_ui_resolve_gacha_icon() -> void:
	var r := GachaResult.new()
	r.kind = GachaResult.KIND_RELIC
	r.relic = RelicItem.new(&"relic_soul_mirror_v1")
	r.relic.icon_path = RelicItem.default_icon_path(r.relic.id)
	var path: String = RunUi.resolve_gacha_icon_path(r)
	assert_eq(path, "res://assets/roguelike/relics/relic_soul_mirror.png")
