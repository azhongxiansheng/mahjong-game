extends GutTest

# 对局 loadout 芯片条：从 ability/relic/consumable 条目生成摘要

func test_chip_entries_from_ids() -> void:
	var entries: Array = BattleLoadoutStrip.build_entries(
		[&"seabed_hunter_v1"],
		[&"relic_lucky_cat_v1"],
		[&"wall_peek_v1"]
	)
	assert_eq(entries.size(), 3)
	assert_eq(String(entries[0].get("kind", "")), "ability")
	assert_eq(String(entries[1].get("kind", "")), "relic")
	assert_eq(String(entries[2].get("kind", "")), "consumable")
	# 有资产的遗物/道具应带 icon
	assert_true(String(entries[1].get("icon_path", "")).contains("relic_lucky_cat"))
	assert_true(String(entries[2].get("icon_path", "")).contains("wall_peek"))

func test_chip_entries_empty_safe() -> void:
	assert_eq(BattleLoadoutStrip.build_entries([], [], []).size(), 0)
