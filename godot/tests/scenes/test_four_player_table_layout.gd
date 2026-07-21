extends GutTest

# 麻将王 — 里程碑 3 第 2 步：4 人桌布局 helper 单测
#
# 仅覆盖纯静态 helper，不实例化 Control / Node2D 节点（GUT headless 跑得快）。
# UI 渲染层的视觉验证留给 F6 smoke 场景人测。

# ---- SeatPanel.rotation_for_seat ----

func test_seat_rotation_zero_for_player():
	assert_eq(SeatPanel.rotation_for_seat(0), 0.0, "玩家在下方，无旋转")

func test_seat_rotation_minus_90_for_right():
	assert_eq(SeatPanel.rotation_for_seat(1), -90.0, "右家旋转 -90 度")

func test_seat_rotation_180_for_opposite():
	assert_eq(SeatPanel.rotation_for_seat(2), 180.0, "对家旋转 180 度")

func test_seat_rotation_90_for_left():
	assert_eq(SeatPanel.rotation_for_seat(3), 90.0, "左家旋转 +90 度")

# ---- SeatPanel.seat_display_name ----

func test_seat_name_player_is_you():
	assert_eq(SeatPanel.seat_display_name(0), "你")

func test_seat_name_ai():
	assert_eq(SeatPanel.seat_display_name(1), "AI 1")
	assert_eq(SeatPanel.seat_display_name(2), "AI 2")
	assert_eq(SeatPanel.seat_display_name(3), "AI 3")

# ---- SeatPanel.wind_name ----

func test_wind_name_e():
	assert_eq(SeatPanel.wind_name(TileId.E), "东")

func test_wind_name_s():
	assert_eq(SeatPanel.wind_name(TileId.S_WIND), "南")

func test_wind_name_w():
	assert_eq(SeatPanel.wind_name(TileId.W_WIND), "西")

func test_wind_name_n():
	assert_eq(SeatPanel.wind_name(TileId.N), "北")

func test_wind_name_unknown():
	assert_eq(SeatPanel.wind_name(99), "?")

# ---- CenterInfoPanel.round_name ----

func test_round_name_east_1():
	assert_eq(CenterInfoPanel.round_name(0), "东 1 局")

func test_round_name_east_4():
	assert_eq(CenterInfoPanel.round_name(3), "东 4 局")

func test_round_name_out_of_range_falls_back():
	# M8 起 hand_index 4..7 是南场（半庄战），fallback 移到 hand_index >= 8
	assert_eq(CenterInfoPanel.round_name(8), "局 9", "南 4 之外 fallback")

# ---- CenterInfoPanel.dora_summary ----

func test_dora_summary_empty():
	assert_eq(CenterInfoPanel.dora_summary([]), "Dora: -")

func test_dora_summary_single():
	# 4万 = TileId.W4 = 3
	assert_eq(CenterInfoPanel.dora_summary([TileId.W4]), "Dora: 4万")

func test_dora_summary_mixed():
	# 含数字牌 + 字牌
	var s := CenterInfoPanel.dora_summary([TileId.W1, TileId.S5, TileId.E])
	assert_eq(s, "Dora: 1万, 5条, 东")

func test_dora_summary_all_seven_winds_and_dragons():
	# 字牌全 7 张
	var ids := [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N, TileId.HAKU, TileId.HATSU, TileId.CHUN]
	var s := CenterInfoPanel.dora_summary(ids)
	assert_eq(s, "Dora: 东, 南, 西, 北, 白, 发, 中")

# ---- FourPlayerTable.seat_position ----

func test_seat_position_player_at_bottom_center():
	var p: Vector2 = FourPlayerTable.seat_position(0)
	assert_eq(p.x, FourPlayerTable.TABLE_WIDTH / 2.0)
	assert_true(p.y > FourPlayerTable.TABLE_HEIGHT / 2.0, "玩家 y 在桌面下半")

func test_seat_position_right_at_right_center():
	var p: Vector2 = FourPlayerTable.seat_position(1)
	assert_eq(p, Vector2(1495.0, 370.0), "右家匹配参考站固定座位锚点")

func test_seat_position_opposite_at_top_center():
	var p: Vector2 = FourPlayerTable.seat_position(2)
	assert_eq(p.x, FourPlayerTable.TABLE_WIDTH / 2.0)
	assert_true(p.y < FourPlayerTable.TABLE_HEIGHT / 2.0, "对家 y 在桌面上半")

func test_seat_position_left_at_left_center():
	var p: Vector2 = FourPlayerTable.seat_position(3)
	assert_eq(p, Vector2(105.0, 370.0), "左家匹配参考站固定座位锚点")

# ---- AbilityPanel.SLOT_COUNT 不变量 ----

func test_ability_panel_slot_count_is_5():
	# spec §10 + §14：5 槽默认
	assert_eq(AbilityPanel.SLOT_COUNT, 5)
