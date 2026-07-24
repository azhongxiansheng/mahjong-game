extends GutTest

func test_chi_meld_3_tiles_consecutive():
	var m := Meld.make_chi([Tile.new(TileId.W2), Tile.new(TileId.W3), Tile.new(TileId.W4)], 0)
	assert_eq(m.kind, Meld.Kind.CHI)
	assert_eq(m.tiles.size(), 3)
	assert_eq(m.from_seat, 0)


func test_open_meld_preserves_exact_called_tile_identity():
	# called_tile 按 instance_id 从 tiles 派生（不存第二份引用）
	# 唯一契约：第 3 参 = meld_id(int)，第 4 参 = called Tile
	var called := Tile.new(TileId.W3, false, Tile.NO_OWNER, 50)
	var a := Tile.new(TileId.W2, false, Tile.NO_OWNER, 51)
	var b := Tile.new(TileId.W4, false, Tile.NO_OWNER, 52)
	var m := Meld.make_chi([a, called, b], 0, 1, called)
	assert_eq(m.meld_id, 1)
	assert_eq(m.called_tile_instance_id, 50)
	assert_same(m.called_tile, called,
		"参考副露牌序必须知道真正从河里叫来的 Tile，不能按排序位置猜")

func test_pon_meld_3_tiles_same():
	var m := Meld.make_pon([Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)], 1)
	assert_eq(m.kind, Meld.Kind.PON)

func test_minkan_4_tiles_open():
	var m := Meld.make_minkan([
		Tile.new(TileId.W7), Tile.new(TileId.W7),
		Tile.new(TileId.W7), Tile.new(TileId.W7)
	], 2)
	assert_eq(m.kind, Meld.Kind.MINKAN)

func test_ankan_4_tiles_concealed():
	var m := Meld.make_ankan([
		Tile.new(TileId.HAKU), Tile.new(TileId.HAKU),
		Tile.new(TileId.HAKU), Tile.new(TileId.HAKU)
	])
	assert_eq(m.kind, Meld.Kind.ANKAN)
	assert_eq(m.from_seat, Meld.NO_SOURCE_SEAT, "暗杠不来自任何人")

func test_added_kan_from_existing_pon():
	var called := Tile.new(TileId.E, false, Tile.NO_OWNER, 10)
	var t1 := Tile.new(TileId.E, false, Tile.NO_OWNER, 11)
	var t2 := Tile.new(TileId.E, false, Tile.NO_OWNER, 12)
	var t3 := Tile.new(TileId.E, false, Tile.NO_OWNER, 13)
	var m := Meld.make_pon([called, t1, t2], 3, 2, called)
	assert_true(m.promote_to_added_kan(t3))
	assert_eq(m.kind, Meld.Kind.ADDED_KAN)
	assert_eq(m.meld_id, 2)
	assert_eq(m.called_tile_instance_id, 10)
	assert_eq(m.added_tile_instance_id, 13)
	assert_same(m.called_tile, called, "加杠必须继承原碰的 called tile")

func test_is_concealed():
	assert_true(Meld.make_ankan([
		Tile.new(TileId.W1), Tile.new(TileId.W1),
		Tile.new(TileId.W1), Tile.new(TileId.W1)
	]).is_concealed())
	assert_false(Meld.make_pon([
		Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1)
	], 0).is_concealed())

func test_is_kan():
	var ankan := Meld.make_ankan([
		Tile.new(TileId.W1), Tile.new(TileId.W1),
		Tile.new(TileId.W1), Tile.new(TileId.W1)
	])
	assert_true(ankan.is_kan())
	var pon := Meld.make_pon([
		Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1)
	], 0)
	assert_false(pon.is_kan())

func test_to_id_array():
	var m := Meld.make_chi([
		Tile.new(TileId.W2), Tile.new(TileId.W3), Tile.new(TileId.W4)
	], 0)
	assert_eq(m.to_id_array(), [TileId.W2, TileId.W3, TileId.W4])
