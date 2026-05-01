extends GutTest

# 麻将王 — 里程碑 3 第 3 步：归属可视化 helper 单测
#
# 仅覆盖 CardTileBack / TileStamp 的纯静态 helper（颜色映射、tile 名、
# rarity 标签、tooltip 格式）。视觉效果留给 F6 smoke 人测。

# ---- CardTileBack.tile_back_color ----

func test_tile_back_color_player_is_gold():
	var c: Color = CardTileBack.tile_back_color(0)
	# GOLD 应有较高 R 与 G、较低 B
	assert_gt(c.r, 0.7)
	assert_gt(c.g, 0.6)
	assert_lt(c.b, 0.4)

func test_tile_back_color_red_for_seat_1():
	var c: Color = CardTileBack.tile_back_color(1)
	# RED 应 R 高、G/B 低
	assert_gt(c.r, 0.6)
	assert_lt(c.g, 0.4)
	assert_lt(c.b, 0.4)

func test_tile_back_color_green_for_seat_2():
	var c: Color = CardTileBack.tile_back_color(2)
	assert_lt(c.r, 0.4)
	assert_gt(c.g, 0.5)
	assert_lt(c.b, 0.4)

func test_tile_back_color_blue_for_seat_3():
	var c: Color = CardTileBack.tile_back_color(3)
	assert_lt(c.r, 0.4)
	assert_lt(c.g, 0.5)
	assert_gt(c.b, 0.6)

func test_tile_back_color_unknown_seat_falls_back_to_grey():
	# 越界 seat 应走 fallback 灰色
	assert_eq(CardTileBack.tile_back_color(-1), CardTileBack.UNKNOWN_OWNER_COLOR)
	assert_eq(CardTileBack.tile_back_color(4), CardTileBack.UNKNOWN_OWNER_COLOR)
	assert_eq(CardTileBack.tile_back_color(99), CardTileBack.UNKNOWN_OWNER_COLOR)

func test_seat_tile_back_colors_count_is_4():
	# spec §10：4 套牌背
	assert_eq(CardTileBack.SEAT_TILE_BACK_COLORS.size(), 4)

# ---- CardTileBack.tile_short_name ----

func test_tile_short_name_man():
	assert_eq(CardTileBack.tile_short_name(TileId.W1), "1万")
	assert_eq(CardTileBack.tile_short_name(TileId.W9), "9万")

func test_tile_short_name_pin():
	assert_eq(CardTileBack.tile_short_name(TileId.T1), "1筒")
	assert_eq(CardTileBack.tile_short_name(TileId.T5), "5筒")
	assert_eq(CardTileBack.tile_short_name(TileId.T9), "9筒")

func test_tile_short_name_sou():
	assert_eq(CardTileBack.tile_short_name(TileId.S1), "1条")
	assert_eq(CardTileBack.tile_short_name(TileId.S9), "9条")

func test_tile_short_name_winds_and_dragons():
	assert_eq(CardTileBack.tile_short_name(TileId.E), "东")
	assert_eq(CardTileBack.tile_short_name(TileId.S_WIND), "南")
	assert_eq(CardTileBack.tile_short_name(TileId.W_WIND), "西")
	assert_eq(CardTileBack.tile_short_name(TileId.N), "北")
	assert_eq(CardTileBack.tile_short_name(TileId.HAKU), "白")
	assert_eq(CardTileBack.tile_short_name(TileId.HATSU), "发")
	assert_eq(CardTileBack.tile_short_name(TileId.CHUN), "中")

func test_tile_short_name_unknown():
	assert_eq(CardTileBack.tile_short_name(-1), "?")
	assert_eq(CardTileBack.tile_short_name(99), "?")

# ---- TileStamp.rarity_color ----

func test_rarity_color_count_is_4():
	# spec §9.1：4 档稀有度
	assert_eq(TileStamp.RARITY_COLORS.size(), 4)

func test_rarity_color_common_is_grey():
	# 普通 = 灰，R≈G≈B
	var c: Color = TileStamp.rarity_color(0)
	assert_almost_eq(c.r, c.g, 0.05)
	assert_almost_eq(c.g, c.b, 0.05)

func test_rarity_color_uncommon_is_blue():
	var c: Color = TileStamp.rarity_color(1)
	assert_gt(c.b, c.r)
	assert_gt(c.b, c.g)

func test_rarity_color_epic_is_purple():
	# 紫 = R 与 B 都高、G 低
	var c: Color = TileStamp.rarity_color(2)
	assert_gt(c.r, c.g)
	assert_gt(c.b, c.g)

func test_rarity_color_legendary_is_gold():
	# 金 = R 高、G 中高、B 低
	var c: Color = TileStamp.rarity_color(3)
	assert_gt(c.r, 0.8)
	assert_gt(c.g, 0.6)
	assert_lt(c.b, 0.4)

func test_rarity_color_unknown_falls_back():
	assert_eq(TileStamp.rarity_color(-1), TileStamp.UNKNOWN_RARITY_COLOR)
	assert_eq(TileStamp.rarity_color(4), TileStamp.UNKNOWN_RARITY_COLOR)

# ---- TileStamp.rarity_label ----

func test_rarity_label_zh_names():
	assert_eq(TileStamp.rarity_label(0), "普通")
	assert_eq(TileStamp.rarity_label(1), "精良")
	assert_eq(TileStamp.rarity_label(2), "史诗")
	assert_eq(TileStamp.rarity_label(3), "神话")

func test_rarity_label_unknown():
	assert_eq(TileStamp.rarity_label(99), "?")

# ---- TileStamp.format_tooltip ----

func test_format_tooltip_null_returns_empty():
	assert_eq(TileStamp.format_tooltip(null), "")

func test_format_tooltip_minimum_skill():
	var sk := SkillResource.new()
	sk.id = &"thunder_5w_v1"
	sk.rarity = 2
	var s := TileStamp.format_tooltip(sk)
	assert_true(s.find("thunder_5w_v1") >= 0, "tooltip 含 id")
	assert_true(s.find("史诗") >= 0, "tooltip 含稀有度标签")

func test_format_tooltip_full_skill():
	var sk := SkillResource.new()
	sk.id = &"thunder_5w_v1"
	sk.display_name = "5万·闪电"
	sk.description = "owner 自胡时 +1 番"
	sk.rarity = 2
	var ot: Array[StringName] = [&"WIN_DECLARED"]
	sk.owner_triggers = ot
	var s := TileStamp.format_tooltip(sk)
	assert_true(s.find("5万·闪电") >= 0)
	assert_true(s.find("owner 自胡时") >= 0, "tooltip 含 description")
	assert_true(s.find("owner@WIN_DECLARED") >= 0, "tooltip 含 trigger")

func test_format_tooltip_ability():
	var sk := SkillResource.new()
	sk.id = &"seabed_hunter"
	sk.rarity = 3
	sk.is_ability = true
	var s := TileStamp.format_tooltip(sk)
	assert_true(s.find("(角色能力)") >= 0)
