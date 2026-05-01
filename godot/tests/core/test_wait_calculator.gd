extends GutTest

# WaitCalculator: 给定 13 张暗手牌 + 副露列表，返回所有听牌 id 数组（升序）。
# 算法：枚举 34 张候选 winning_tile，调用 WinPattern.detect 看 is_winning。

func _hand(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

# ---- 单骑 ----

func test_tanki_wait_dragon():
	# 234m 234p 234s 234s + 中（13 张）等中单骑
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.CHUN,
	])
	var waits := WaitCalculator.wait_tiles(h, [])
	assert_eq(waits, [TileId.CHUN], "单骑等中")

# ---- 双面 ----

func test_ryanmen_wait_two_sides():
	# 234m 234p 234s 67s + W5W5（13 张）等 5s 或 8s 双面
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7,
		TileId.W5, TileId.W5,
	])
	var waits := WaitCalculator.wait_tiles(h, [])
	assert_true(TileId.S5 in waits, "等 5s")
	assert_true(TileId.S8 in waits, "等 8s")

# ---- 嵌张 ----

func test_kanchan_wait():
	# 234m 234p 234s 24s + W5W5 → 等 3s 嵌张（注：4s 也来自嵌后段）
	# 不行，234s 已含 3s。换牌：234m 234p 567s 24s + W5W5
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S5, TileId.S6, TileId.S7,
		TileId.S2, TileId.S4,
		TileId.W5, TileId.W5,
	])
	var waits := WaitCalculator.wait_tiles(h, [])
	assert_true(TileId.S3 in waits, "等 3s 嵌张")

# ---- 边张 ----

func test_penchan_wait_low():
	# 234m 234p 234s 12s + W5W5 → 等 3s 边张（但 234s 已含 3s 也能完成）
	# 简化：234m 234p 567s 12s + W5W5 等 3s
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S5, TileId.S6, TileId.S7,
		TileId.S1, TileId.S2,
		TileId.W5, TileId.W5,
	])
	var waits := WaitCalculator.wait_tiles(h, [])
	assert_true(TileId.S3 in waits, "等 3s 边张")

# ---- 七対子 ----

func test_chiitoi_wait_one_tile():
	# 6 对 + 1 张单 → 等单成第 7 对
	var h := _hand([
		TileId.W1, TileId.W1,
		TileId.W3, TileId.W3,
		TileId.T2, TileId.T2,
		TileId.T5, TileId.T5,
		TileId.S6, TileId.S6,
		TileId.E, TileId.E,
		TileId.HAKU,
	])
	var waits := WaitCalculator.wait_tiles(h, [])
	assert_eq(waits, [TileId.HAKU], "七対子等白")

# ---- 国士 13 面待 ----

func test_kokushi_thirteen_wait():
	# 13 幺九各 1 → 听全部 13 张
	var h := _hand([
		TileId.W1, TileId.W9,
		TileId.T1, TileId.T9,
		TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.HAKU, TileId.HATSU, TileId.CHUN,
	])
	var waits := WaitCalculator.wait_tiles(h, [])
	assert_eq(waits.size(), 13, "国士 13 面待")
	# 必须全是幺九
	for tid in waits:
		assert_true(TileId.is_yaochu(tid))

# ---- 不听 ----

func test_no_wait_returns_empty():
	# 全单散无听
	var h := _hand([
		TileId.W1, TileId.W3, TileId.W5, TileId.W7, TileId.W9,
		TileId.T1, TileId.T3, TileId.T5, TileId.T7, TileId.T9,
		TileId.S1, TileId.S3, TileId.S5,
	])
	var waits := WaitCalculator.wait_tiles(h, [])
	assert_eq(waits.size(), 0, "全散不听")

# ---- 副露后听 ----

func test_wait_with_called_meld():
	# 副露 chi 234m，暗 10 张 = 234p 234s 67s W5W5 → 等 5s 或 8s
	var chi := Meld.make_chi(
		[Tile.new(TileId.W2), Tile.new(TileId.W3), Tile.new(TileId.W4)], 3)
	var h := _hand([
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7,
		TileId.W5, TileId.W5,
	])
	var waits := WaitCalculator.wait_tiles(h, [chi])
	assert_true(TileId.S5 in waits)
	assert_true(TileId.S8 in waits)

# ---- 双碰 ----

func test_shanpon_wait():
	# 234m 234p 234s + W5W5 + S3S3 → 等 W5 或 S3 双碰
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S4, TileId.S5,
		TileId.W5, TileId.W5,
		TileId.S3, TileId.S3,
	])
	# 2,3,4 + 2,3,4 + 2,4,5 (?) — 让我重做，确保结构对
	# 改：234m 234p + W5W5 + S3S3 + 234s = 13 张
	h = _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W5, TileId.W5,
		TileId.S3, TileId.S3,
	])
	var waits := WaitCalculator.wait_tiles(h, [])
	assert_true(TileId.W5 in waits, "双碰等 W5")
	assert_true(TileId.S3 in waits, "双碰等 S3")

# ---- waits 升序 ----

func test_waits_returned_in_ascending_order():
	# 双面 等多张，验证升序
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7,
		TileId.W5, TileId.W5,
	])
	var waits := WaitCalculator.wait_tiles(h, [])
	for i in range(waits.size() - 1):
		assert_lt(waits[i], waits[i + 1], "升序")
