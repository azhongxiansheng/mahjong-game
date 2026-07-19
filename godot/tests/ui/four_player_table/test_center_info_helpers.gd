extends GutTest

# CenterInfoPanel.wall_color 牌墙剩余分级配色单测。
# round_name / dora_summary 已被 tests/scenes/test_center_info_panel.gd 覆盖。

func test_wall_color_early_white() -> void:
	# > 30 张:早盘,骨白
	var c := CenterInfoPanel.wall_color(70)
	assert_almost_eq(c.r, 0.92, 0.02)
	assert_almost_eq(c.g, 0.90, 0.02)


func test_wall_color_mid_yellow() -> void:
	# 11..30 张:中盘,黄
	var c := CenterInfoPanel.wall_color(20)
	assert_almost_eq(c.r, 0.95, 0.02)
	assert_almost_eq(c.g, 0.85, 0.02)


func test_wall_color_late_orange() -> void:
	# 5..10 张:终盘,橙
	var c := CenterInfoPanel.wall_color(8)
	assert_almost_eq(c.r, 1.0, 0.02)
	assert_almost_eq(c.g, 0.55, 0.02)


func test_wall_color_critical_red() -> void:
	# <=4 张:海底/河底警戒,红
	var c := CenterInfoPanel.wall_color(4)
	assert_almost_eq(c.r, 1.0, 0.02)
	var c0 := CenterInfoPanel.wall_color(0)
	assert_almost_eq(c0.r, 1.0, 0.02)


func test_wall_color_thresholds_monotone() -> void:
	# 红/橙/黄/白 在临界点的过渡:5 → 橙(>4 出红区), 11 → 黄, 31 → 白
	assert_ne(CenterInfoPanel.wall_color(5), CenterInfoPanel.wall_color(4))
	assert_ne(CenterInfoPanel.wall_color(11), CenterInfoPanel.wall_color(10))
	assert_ne(CenterInfoPanel.wall_color(31), CenterInfoPanel.wall_color(30))


# ---- dora_summary 路由 ----
# 之前 CenterInfoPanel 有自家的 _tile_short_name 拷贝,现统一改走
# CardTileBack.tile_short_name。这条测试保护路由不再回退/再次重复。

func test_dora_summary_routes_honor_tiles() -> void:
	# 字牌名(东南西北白发中)与 CardTileBack.tile_short_name 一致
	var s := CenterInfoPanel.dora_summary([TileId.E, TileId.HATSU, TileId.CHUN])
	assert_true(s.find("东") >= 0)
	assert_true(s.find("发") >= 0)
	assert_true(s.find("中") >= 0)


func test_dora_summary_matches_card_tile_back_for_all_kinds() -> void:
	# 一张万 / 一张筒 / 一张索 / 一张字,逐项与 CardTileBack 比对
	for tid in [TileId.W1, TileId.T5, TileId.S9, TileId.HAKU]:
		var expected := CardTileBack.tile_short_name(tid)
		var summary := CenterInfoPanel.dora_summary([tid])
		assert_true(summary.find(expected) >= 0,
			"%s 牌名 '%s' 应出现在 dora_summary 中" % [tid, expected])


# 桌上立直棒 >0 时视觉棒 + 金光呼吸
func test_riichi_sticks_visual_and_glow() -> void:
	var panel: CenterInfoPanel = load(
		"res://ui/four_player_table/center_info_panel.tscn").instantiate()
	add_child_autofree(panel)
	await get_tree().process_frame
	panel.set_riichi_sticks(0)
	assert_eq(panel.count_riichi_stick_visuals(), 0)
	assert_false(panel.is_riichi_stick_glow_active(), "0 棒无发光")
	panel.set_riichi_sticks(2)
	assert_eq(panel.count_riichi_stick_visuals(), 2, "应画 2 根棒")
	assert_true(panel.is_riichi_stick_glow_active(), "有棒应启发光 tween")
	panel.set_riichi_sticks(0)
	assert_eq(panel.count_riichi_stick_visuals(), 0)
	assert_false(panel.is_riichi_stick_glow_active())
