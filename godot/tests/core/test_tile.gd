extends GutTest

func test_construct_with_id_only():
	var t := Tile.new(TileId.W5)
	assert_eq(t.id, TileId.W5)
	assert_false(t.is_red_dora)

func test_construct_red_five_man():
	var t := Tile.make_red_five_man()
	assert_eq(t.id, TileId.W5)
	assert_true(t.is_red_dora)

func test_construct_red_five_pin():
	var t := Tile.make_red_five_pin()
	assert_eq(t.id, TileId.T5)
	assert_true(t.is_red_dora)

func test_construct_red_five_sou():
	var t := Tile.make_red_five_sou()
	assert_eq(t.id, TileId.S5)
	assert_true(t.is_red_dora)

func test_equals_by_id_only_ignoring_red():
	var a := Tile.new(TileId.W5)
	var b := Tile.make_red_five_man()
	assert_true(a.equals_by_id(b), "id 相同即视为同类型，不看赤")
