extends GutTest

func test_no_melds_is_menzen():
	assert_true(MenzenHelper.is_menzen([] as Array[Meld]))

func test_with_chi_not_menzen():
	var chi := Meld.make_chi([
		Tile.new(TileId.W2), Tile.new(TileId.W3), Tile.new(TileId.W4)
	], 0)
	assert_false(MenzenHelper.is_menzen([chi] as Array[Meld]))

func test_with_pon_not_menzen():
	var pon := Meld.make_pon([
		Tile.new(TileId.E), Tile.new(TileId.E), Tile.new(TileId.E)
	], 0)
	assert_false(MenzenHelper.is_menzen([pon] as Array[Meld]))

func test_only_ankan_still_menzen():
	var ankan := Meld.make_ankan([
		Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1)
	])
	assert_true(MenzenHelper.is_menzen([ankan] as Array[Meld]))

func test_minkan_breaks_menzen():
	var minkan := Meld.make_minkan([
		Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1)
	], 0)
	assert_false(MenzenHelper.is_menzen([minkan] as Array[Meld]))
