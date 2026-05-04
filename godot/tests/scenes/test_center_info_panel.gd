extends GutTest

# 麻将王 — M8 Step 7: CenterInfoPanel 静态 helpers 单测
#
# 只覆盖 round_name 风圈推进；scene-level 行为（_refresh_labels）走 F6 手测。

# ---- round_name (M7 兼容) ----

func test_round_name_default_hands_per_round_is_4():
	# 不传 hands_per_round → 默认 4，等同于东风战
	assert_eq(CenterInfoPanel.round_name(0), "东 1 局")
	assert_eq(CenterInfoPanel.round_name(3), "东 4 局")

func test_round_name_east_round_hands_0_to_3():
	for h in range(4):
		assert_eq(CenterInfoPanel.round_name(h, 4), "东 %d 局" % (h + 1))

# ---- round_name (M8 半庄战) ----

func test_round_name_hand_4_is_south_1():
	assert_eq(CenterInfoPanel.round_name(4, 4), "南 1 局",
		"hand_index=4 半庄 → 南 1")

func test_round_name_hand_7_is_south_4():
	assert_eq(CenterInfoPanel.round_name(7, 4), "南 4 局")

func test_round_name_south_round_full():
	for h in range(4, 8):
		var local := h - 4
		assert_eq(CenterInfoPanel.round_name(h, 4), "南 %d 局" % (local + 1))

# ---- 边界 ----

func test_round_name_negative_index_fallback():
	# 极端边界：保留 "局 N" fallback（M7 行为）
	var s := CenterInfoPanel.round_name(-1, 4)
	assert_true(s.contains("局"), "负索引应用 fallback 显示")

func test_round_name_extreme_renchan_overflow_fallback():
	# 半庄战连庄到 hand_index=8 已是 "南 4 连庄"，本质仍是南 4 局；
	# round_name(8, 4) 落在 round_index=2 → fallback
	var s := CenterInfoPanel.round_name(8, 4)
	assert_true(s.contains("局"), "超出 2 风圈 fallback")
