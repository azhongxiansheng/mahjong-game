extends GutTest

# 胡牌结算 tier 名静态分类(playable_table._score_tier_label)单测。
# 覆盖役満倍数 / 数え役満 / 三倍満 / 倍満 / 跳満 / 満貫 / 普通飜符 分支。

const PT := preload("res://ui/four_player_table/playable_table.gd")


func test_yakuman_single() -> void:
	assert_eq(PT._score_tier_label(0, 0, 1), "役満")


func test_yakuman_double() -> void:
	assert_eq(PT._score_tier_label(0, 0, 2), "2 倍役満")


func test_yakuman_triple() -> void:
	assert_eq(PT._score_tier_label(0, 0, 3), "3 倍役満")


func test_kazoe_yakuman_at_13_han() -> void:
	assert_eq(PT._score_tier_label(13, 30, 0), "数え役満")


func test_sanbaiman_at_11_han() -> void:
	assert_eq(PT._score_tier_label(11, 30, 0), "三倍満")


func test_baiman_at_8_han() -> void:
	assert_eq(PT._score_tier_label(8, 30, 0), "倍満")


func test_haneman_at_6_han() -> void:
	assert_eq(PT._score_tier_label(6, 30, 0), "跳満")


func test_mangan_at_5_han() -> void:
	assert_eq(PT._score_tier_label(5, 30, 0), "満貫")


func test_plain_han_under_5() -> void:
	assert_eq(PT._score_tier_label(3, 40, 0), "3 飜 胡牌")
	assert_eq(PT._score_tier_label(1, 30, 0), "1 飜 胡牌")


# ---- _format_yaku_list ----

func test_format_yaku_list_empty() -> void:
	assert_eq(PT._format_yaku_list([]), "（无役）")


func test_format_yaku_list_single() -> void:
	assert_eq(PT._format_yaku_list([{"name": "立直", "han": 1}]), "立直 1飜")


func test_format_yaku_list_multiple_separator() -> void:
	var s := PT._format_yaku_list([
		{"name": "立直", "han": 1},
		{"name": "门前清自摸和", "han": 1},
		{"name": "平和", "han": 1},
	])
	assert_eq(s, "立直 1飜 · 门前清自摸和 1飜 · 平和 1飜")


func test_format_yaku_list_yakuman_skips_han() -> void:
	var s := PT._format_yaku_list([{"name": "大三元", "han": 0, "yakuman_multiplier": 1}])
	assert_true(s.find("大三元") >= 0, "应含役名")
	assert_false(s.find("飜") >= 0, "役満不显示飜数")


func test_format_yaku_list_double_yakuman_shows_multiplier() -> void:
	var s := PT._format_yaku_list([{"name": "四暗刻単騎", "han": 0, "yakuman_multiplier": 2}])
	assert_true(s.find("四暗刻") >= 0)
	assert_true(s.find("2 倍") >= 0, "双倍役満应标注倍数")
