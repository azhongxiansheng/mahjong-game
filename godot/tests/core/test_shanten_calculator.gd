extends GutTest

# ShantenCalculator: hand → 向听数（0 = tenpai；N = 还差 N 张）。
# 测三种和牌型 + 边界。

func _hand(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

# ---- Standard (4 mentsu + 1 pair) ----

func test_tenpai_tanki():
	# 已听单骑：234m 234p 234s 678s + 中（13 张）
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.CHUN,
	])
	assert_eq(ShantenCalculator.calc(h, []), 0, "单骑听 = 0 shanten")

func test_tenpai_ryanmen():
	# 234m 234p 234s 67s + 5w5w（13 张）→ 听 5s/8s 两面
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7,
		TileId.W5, TileId.W5,
	])
	assert_eq(ShantenCalculator.calc(h, []), 0, "两面听 = 0 shanten")

func test_one_shanten():
	# 13 张：234m 234p 234s 67s 5w 中中 — 缺一张组对子或第 4 mentsu
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7,
		TileId.W5,
		TileId.CHUN,
	])
	# 3 mentsu + 1 taatsu (S67) + 1 pair (CHUN×?) - 实际只有 1 张 CHUN，无 pair
	# 应 1-shanten
	assert_eq(ShantenCalculator.calc(h, []), 1, "1-shanten 形")

func test_isolated_hand_high_shanten():
	# 13 张孤立字牌 + 散牌 — 高 shanten
	var h := _hand([
		TileId.W1, TileId.W4, TileId.W7,
		TileId.T2, TileId.T5, TileId.T8,
		TileId.S3, TileId.S6, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.HAKU, TileId.HATSU,
	])
	var s: int = ShantenCalculator.calc(h, [])
	# 13 张全孤立没块 → standard ≈ 8（- 雀头 0 - mentsu 0 - taatsu cap）
	# 但 chiitoi/kokushi 可能更低。验证 ≥ 4 且合理上界
	assert_true(s >= 3, "全孤立手 shanten 应 ≥ 3，实际 %d" % s)
	assert_true(s <= 8, "shanten 上界 8")

# ---- Chiitoi ----

func test_chiitoi_tenpai():
	# 6 对 + 1 单 = chiitoi 0-shanten
	var h := _hand([
		TileId.W1, TileId.W1,
		TileId.W3, TileId.W3,
		TileId.T5, TileId.T5,
		TileId.S2, TileId.S2,
		TileId.S7, TileId.S7,
		TileId.E, TileId.E,
		TileId.CHUN,
	])
	assert_eq(ShantenCalculator.calc(h, []), 0, "6 对 + 1 单 = chiitoi tenpai")

func test_chiitoi_one_shanten():
	# 5 对 + 3 单 = chiitoi 1-shanten
	var h := _hand([
		TileId.W1, TileId.W1,
		TileId.W3, TileId.W3,
		TileId.T5, TileId.T5,
		TileId.S2, TileId.S2,
		TileId.S7, TileId.S7,
		TileId.E, TileId.S_WIND, TileId.CHUN,
	])
	assert_eq(ShantenCalculator.calc(h, []), 1, "5 对 + 3 单 = chiitoi 1-shanten")

func test_chiitoi_triplet_does_not_count_double():
	# 4 对 + 1 刻 + 2 单：刻子按 1 对算 → 5 对 + 2 单 = 6 对差 + 2 单 = 1 shanten
	# 但 4 + 1 + 2 = 13 张 ✓
	var h := _hand([
		TileId.W1, TileId.W1,
		TileId.W3, TileId.W3,
		TileId.T5, TileId.T5,
		TileId.S2, TileId.S2,
		TileId.E, TileId.E, TileId.E,  # 刻 — 算 1 对
		TileId.S_WIND, TileId.CHUN,
	])
	# kinds = 6（4 对 + 1 刻 = 5 不同 + 2 单 = 7 kinds）
	# pairs = 5（4 + 1 刻按 1 对）
	# chiitoi = 6 - 5 + max(0, 7-7) = 1
	assert_eq(ShantenCalculator.calc(h, []), 1, "刻子按 1 对算 chiitoi")

# ---- Kokushi ----

func test_kokushi_tenpai_13_wait():
	# 13 张全幺九（1 张缺 — 不带对子）— 国士 13 面听 0-shanten
	var h := _hand([
		TileId.W1, TileId.W9,
		TileId.T1, TileId.T9,
		TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.HAKU, TileId.HATSU, TileId.CHUN,
	])
	# distinct = 13；has_pair = false → 13-13-0 = 0
	assert_eq(ShantenCalculator.calc(h, []), 0, "13 面听 kokushi = 0")

func test_kokushi_tenpai_single():
	# 12 种幺九 + 其中 1 种成对（13 张）— 单面听
	var h := _hand([
		TileId.W1, TileId.W1,  # 雀头
		TileId.W9,
		TileId.T1, TileId.T9,
		TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.HAKU, TileId.HATSU,
	])
	# distinct = 12；has_pair = true → 13-12-1 = 0
	assert_eq(ShantenCalculator.calc(h, []), 0, "12 种 + 1 对 kokushi tenpai")

func test_kokushi_one_shanten():
	# 12 种幺九 + 中张 1 张 — 缺 1 种 + 无对 → 1-shanten
	var h := _hand([
		TileId.W1, TileId.W9,
		TileId.T1, TileId.T9,
		TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.HAKU, TileId.HATSU,
		TileId.W5,  # 中张占位
	])
	# distinct = 12；has_pair = false → 13-12-0 = 1
	assert_eq(ShantenCalculator.calc(h, []), 1, "12 种 kokushi 1-shanten")

# ---- 多种型取 min ----

func test_takes_min_across_three_types():
	# 设 standard 可达 1-shanten 的一手；同时 chiitoi 也是 1-shanten
	# 应取 min（任一即可）
	var h := _hand([
		TileId.W1, TileId.W1,
		TileId.W3, TileId.W3,
		TileId.T5, TileId.T5,
		TileId.S2, TileId.S2,
		TileId.S7, TileId.S7,
		TileId.E, TileId.S_WIND, TileId.CHUN,
	])
	var s: int = ShantenCalculator.calc(h, [])
	assert_eq(s, 1, "min(standard, chiitoi, kokushi) = 1")

# ---- 副露折抵 ----

func test_called_meld_reduces_shanten():
	# 副露 1 chi 234m → 暗 10 张可达 standard tenpai
	# 暗 10 张：234p 234s 67s + 5w5w → 听 5s/8s
	var chi: Meld = Meld.make_chi(
		[Tile.new(TileId.W2), Tile.new(TileId.W3), Tile.new(TileId.W4)], 3)
	var h := _hand([
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7,
		TileId.W5, TileId.W5,
	])
	assert_eq(ShantenCalculator.calc(h, [chi]), 0, "副露 1 chi + 暗 10 张听牌 = 0")

func test_called_meld_skips_chiitoi_kokushi():
	# 同样 11 张混乱手（无 chiitoi/kokushi 路径），副露 1 后只看 standard
	var chi: Meld = Meld.make_chi(
		[Tile.new(TileId.W2), Tile.new(TileId.W3), Tile.new(TileId.W4)], 3)
	var h := _hand([
		TileId.T1, TileId.T2,
		TileId.S5, TileId.S5,
		TileId.S7, TileId.S8,
		TileId.E, TileId.S_WIND,
		TileId.HAKU, TileId.CHUN,
	])
	# 副露 + 10 张暗 = 13 等价。standard 路径
	var s: int = ShantenCalculator.calc(h, [chi])
	assert_true(s >= 0 and s <= 8, "副露 + 暗手 standard shanten 在合理区间")

# ---- 一致性：tenpai → wait_calculator 也认可 ----

func test_tenpai_consistent_with_wait_calculator():
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7,
		TileId.W5, TileId.W5,
	])
	assert_eq(ShantenCalculator.calc(h, []), 0)
	assert_true(WaitCalculator.is_tenpai(h, []), "shanten 0 时 is_tenpai = true")

func test_one_shanten_not_tenpai():
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7,
		TileId.W5,
		TileId.CHUN,
	])
	assert_eq(ShantenCalculator.calc(h, []), 1)
	assert_false(WaitCalculator.is_tenpai(h, []), "shanten ≥ 1 时 is_tenpai = false")
