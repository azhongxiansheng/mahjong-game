extends GutTest

# Rarity.color() 单测 —— UI 统一稀有度色入口(灰/蓝/紫/金,spec §9.1)。

func test_common_is_gray() -> void:
	var c := Rarity.color(Rarity.Kind.COMMON)
	# 三通道几乎相等 → 中性灰
	assert_almost_eq(c.r, c.g, 0.02)
	assert_almost_eq(c.g, c.b, 0.02)


func test_uncommon_is_blue() -> void:
	var c := Rarity.color(Rarity.Kind.UNCOMMON)
	assert_gt(c.b, c.r, "蓝通道应高于红")


func test_epic_is_purple() -> void:
	var c := Rarity.color(Rarity.Kind.EPIC)
	# 紫:红和蓝高,绿低
	assert_gt(c.r, c.g)
	assert_gt(c.b, c.g)


func test_legendary_is_gold() -> void:
	var c := Rarity.color(Rarity.Kind.LEGENDARY)
	# 金:红高、绿中、蓝低
	assert_gt(c.r, c.b)
	assert_gt(c.g, c.b)


func test_unknown_returns_neutral() -> void:
	var c := Rarity.color(99)
	assert_almost_eq(c.r, c.g, 0.02)


func test_each_rarity_distinct() -> void:
	var seen: Array[Color] = []
	for r in [Rarity.Kind.COMMON, Rarity.Kind.UNCOMMON, Rarity.Kind.EPIC, Rarity.Kind.LEGENDARY]:
		var c := Rarity.color(r)
		for prev in seen:
			assert_ne(c, prev, "稀有度色应两两不同")
		seen.append(c)
