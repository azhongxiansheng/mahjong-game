extends GutTest

func test_chi_meld_3_tiles_consecutive():
	var m := Meld.make_chi([Tile.new(TileId.W2), Tile.new(TileId.W3), Tile.new(TileId.W4)], 0)
	assert_eq(m.kind, Meld.Kind.CHI)
	assert_eq(m.tiles.size(), 3)
	assert_eq(m.from_seat, 0)

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
	assert_eq(m.from_seat, -1, "暗杠不来自任何人")

func test_added_kan_from_existing_pon():
	var m := Meld.make_added_kan([
		Tile.new(TileId.E), Tile.new(TileId.E),
		Tile.new(TileId.E), Tile.new(TileId.E)
	], 3)
	assert_eq(m.kind, Meld.Kind.ADDED_KAN)

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
