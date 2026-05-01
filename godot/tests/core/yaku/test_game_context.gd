extends GutTest

func test_default_context_is_no_riichi_no_tsumo():
	var c := GameContext.new()
	assert_false(c.is_riichi)
	assert_false(c.is_tsumo)
	assert_false(c.is_ippatsu)

func test_set_basic_flags():
	var c := GameContext.new()
	c.bakaze = TileId.E
	c.jikaze = TileId.S_WIND
	c.is_riichi = true
	c.is_tsumo = true
	assert_eq(c.bakaze, TileId.E)
	assert_eq(c.jikaze, TileId.S_WIND)
	assert_true(c.is_riichi)
	assert_true(c.is_tsumo)

func test_dora_count_field():
	var c := GameContext.new()
	c.dora_count = 3
	assert_eq(c.dora_count, 3)
