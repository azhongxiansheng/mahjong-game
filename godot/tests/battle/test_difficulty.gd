extends GutTest

func test_difficulty_display_names():
	assert_eq(Difficulty.display_name(Difficulty.Level.NORMAL), "普通")
	assert_eq(Difficulty.display_name(Difficulty.Level.HARD), "困难")
	assert_eq(Difficulty.display_name(Difficulty.Level.LUNATIC), "狂气")

func test_hp_modifiers():
	assert_eq(Difficulty.hp_modifier(Difficulty.Level.NORMAL), 0)
	assert_eq(Difficulty.hp_modifier(Difficulty.Level.HARD), -1)
	assert_eq(Difficulty.hp_modifier(Difficulty.Level.LUNATIC), -2)

func test_ai_flags():
	assert_false(Difficulty.use_heuristic_ai(Difficulty.Level.NORMAL))
	assert_true(Difficulty.use_heuristic_ai(Difficulty.Level.HARD))
	assert_true(Difficulty.use_heuristic_ai(Difficulty.Level.LUNATIC))
	assert_false(Difficulty.use_shanten_ai(Difficulty.Level.NORMAL))
	assert_false(Difficulty.use_shanten_ai(Difficulty.Level.HARD))
	assert_true(Difficulty.use_shanten_ai(Difficulty.Level.LUNATIC))

func test_shop_price_multiplier():
	assert_eq(Difficulty.shop_price_multiplier(Difficulty.Level.NORMAL), 1.0)
	assert_eq(Difficulty.shop_price_multiplier(Difficulty.Level.LUNATIC), 1.5)

func test_run_state_difficulty_serialization():
	var rs := RunState.new(42)
	rs.difficulty = Difficulty.Level.HARD
	var d := rs.to_dict()
	var restored := RunState.from_dict(d)
	assert_eq(restored.difficulty, Difficulty.Level.HARD)

func test_colors_are_distinct():
	var n := Difficulty.color(Difficulty.Level.NORMAL)
	var h := Difficulty.color(Difficulty.Level.HARD)
	var l := Difficulty.color(Difficulty.Level.LUNATIC)
	assert_ne(n, h)
	assert_ne(h, l)
