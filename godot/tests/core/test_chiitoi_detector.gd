extends GutTest

func test_seven_distinct_pairs_is_chiitoi():
	var ids := [
		TileId.W1, TileId.W1,
		TileId.W3, TileId.W3,
		TileId.T2, TileId.T2,
		TileId.T9, TileId.T9,
		TileId.S5, TileId.S5,
		TileId.E, TileId.E,
		TileId.HAKU, TileId.HAKU,
	]
	assert_true(ChiitoiDetector.is_chiitoi(ids))

func test_four_of_a_kind_is_not_chiitoi():
	# 1111m 22m 33m 44m 55m 66m 77m
	var ids := [
		TileId.W1, TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W2,
		TileId.W3, TileId.W3,
		TileId.W4, TileId.W4,
		TileId.W5, TileId.W5,
		TileId.W6, TileId.W6,
	]
	assert_false(ChiitoiDetector.is_chiitoi(ids), "同种 4 张不允许（必须 7 对都不同）")

func test_six_pairs_one_triplet_not_chiitoi():
	var ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W2,
		TileId.W3, TileId.W3,
		TileId.W4, TileId.W4,
		TileId.W5, TileId.W5,
		TileId.W6, TileId.W6,
		TileId.W7,
	]
	assert_false(ChiitoiDetector.is_chiitoi(ids))

func test_wrong_size_returns_false():
	assert_false(ChiitoiDetector.is_chiitoi([TileId.W1, TileId.W1]))
	assert_false(ChiitoiDetector.is_chiitoi([]))
