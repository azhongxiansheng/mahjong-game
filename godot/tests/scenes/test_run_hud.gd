extends GutTest

# US-008 RunHud 排版升级单测：HP bar 颜色 + format helpers

func test_format_chapter_text():
	assert_eq(RunHud.format_chapter_text(1, "3"), "📍 章 1 · 层 3")

func test_format_hp_text():
	assert_eq(RunHud.format_hp_text(3, 5), "♥ 3 / 5")

func test_format_gold_text():
	assert_eq(RunHud.format_gold_text(120), "🪙 120")

func test_format_deck_text():
	assert_eq(RunHud.format_deck_text(7), "🃏 卡组 7")

func test_hp_bar_color_full_health_green():
	# > 50%
	var c: Color = RunHud.hp_bar_color(5, 5)
	assert_almost_eq(c.g, 0.75, 0.01)

func test_hp_bar_color_above_quarter_yellow():
	# 25% < ratio <= 50%（4 / 10 = 40%）
	var c: Color = RunHud.hp_bar_color(4, 10)
	assert_almost_eq(c.r, 0.90, 0.01)
	assert_almost_eq(c.g, 0.70, 0.01)

func test_hp_bar_color_low_red():
	# <= 25%（1 / 5 = 20%）
	var c: Color = RunHud.hp_bar_color(1, 5)
	assert_almost_eq(c.r, 0.85, 0.01)

func test_hp_bar_color_zero_max_returns_gray():
	# 防 0 除：max_hp=0 应返灰
	var c: Color = RunHud.hp_bar_color(0, 0)
	assert_eq(c, Color(0.6, 0.6, 0.6))
