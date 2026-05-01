extends GutTest

# 输入：14 张牌的 id 数组（升序），返回所有可行分解（每个分解 = {melds: [...], pair: id}）
# 若不能胡，返回空数组。

func test_pure_pinfu_pattern():
	# 234m 567p 678s 234s 11p
	var ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1, TileId.T1,
	]
	ids.sort()
	var results := StandardDecomposer.decompose(ids)
	assert_gt(results.size(), 0, "应能分解")
	var d = results[0]
	assert_eq(d.melds.size(), 4)
	assert_eq(d.pair, TileId.T1)

func test_all_triplets_pattern():
	# 111m 222m 333m 444m 55m
	var ids := [
		TileId.W1, TileId.W1, TileId.W1,
		TileId.W2, TileId.W2, TileId.W2,
		TileId.W3, TileId.W3, TileId.W3,
		TileId.W4, TileId.W4, TileId.W4,
		TileId.W5, TileId.W5,
	]
	var results := StandardDecomposer.decompose(ids)
	assert_gt(results.size(), 0)
	# 第一个分解：4 个刻子
	var d = results[0]
	assert_eq(d.melds.size(), 4)
	for meld_ids in d.melds:
		assert_eq(meld_ids[0], meld_ids[1])
		assert_eq(meld_ids[1], meld_ids[2])

func test_invalid_hand_returns_empty():
	# 全乱：1m 3m 5m 7m 9m 1p 3p 5p 7p 9p 1s 3s 5s 7s
	var ids := [
		TileId.W1, TileId.W3, TileId.W5, TileId.W7, TileId.W9,
		TileId.T1, TileId.T3, TileId.T5, TileId.T7, TileId.T9,
		TileId.S1, TileId.S3, TileId.S5, TileId.S7,
	]
	var results := StandardDecomposer.decompose(ids)
	assert_eq(results.size(), 0)

func test_multiple_decompositions():
	# 234567m 234567p 11s 这种型可能有不同分解
	var ids := [
		TileId.W2, TileId.W3, TileId.W4, TileId.W5, TileId.W6, TileId.W7,
		TileId.T2, TileId.T3, TileId.T4, TileId.T5, TileId.T6, TileId.T7,
		TileId.S1, TileId.S1,
	]
	var results := StandardDecomposer.decompose(ids)
	assert_gt(results.size(), 0)

func test_honor_pair_with_three_chow():
	# 123m 456m 789p 123s EE
	var ids := [
		TileId.W1, TileId.W2, TileId.W3,
		TileId.W4, TileId.W5, TileId.W6,
		TileId.T7, TileId.T8, TileId.T9,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.E, TileId.E,
	]
	var results := StandardDecomposer.decompose(ids)
	assert_gt(results.size(), 0)
	var d = results[0]
	assert_eq(d.pair, TileId.E)

func test_with_open_melds_count():
	# 副露 1 个吃 234m 后，剩 11 张需分解为 3 面子 + 1 雀头
	# 567p 678s 234s 11p（11 张）
	var ids := [
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.T1, TileId.T1,
	]
	ids.sort()
	var results := StandardDecomposer.decompose(ids)
	assert_gt(results.size(), 0)
	var d = results[0]
	assert_eq(d.melds.size(), 3)
	assert_eq(d.pair, TileId.T1)
