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

# ---- 0e: owner_seat 扩展 ----

func test_default_owner_seat_is_no_seat():
	var t := Tile.new(TileId.W5)
	assert_eq(t.owner_seat, Tile.NO_OWNER, "owner_seat 默认 -1（无主）")

func test_construct_with_owner_seat():
	var t := Tile.new(TileId.W5, false, 2)
	assert_eq(t.owner_seat, 2)

func test_red_five_factories_keep_no_owner():
	# 工厂方法不显式传 owner，应保持 NO_OWNER；卡组系统接入时再填
	assert_eq(Tile.make_red_five_man().owner_seat, Tile.NO_OWNER)
	assert_eq(Tile.make_red_five_pin().owner_seat, Tile.NO_OWNER)
	assert_eq(Tile.make_red_five_sou().owner_seat, Tile.NO_OWNER)
