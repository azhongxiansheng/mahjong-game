extends GutTest

# PayoutCalculator: 把基本点 + WinContext 转成 {payer_seat: points} 字典。
# 立直棒不在字典里（由 ScoreCalc 加给 winner）；本场已合并进各 payer 出的钱。
#
# 公式：
#   闲自摸：庄出 ceil_to_100(base*2)，2 闲各 ceil_to_100(base*1)；本场每家 +100
#   庄自摸：3 闲各 ceil_to_100(base*2)；本场每家 +100
#   闲荣胡：loser 出 ceil_to_100(base*4) + 本场*300
#   庄荣胡：loser 出 ceil_to_100(base*6) + 本场*300
# 包牌：
#   自摸：仅 pao_seat 出全额（含本场）
#   荣胡：pao_seat 与 loser 各半

# ---- 闲自摸 ----

func test_non_dealer_tsumo_base_480():
	# 30 符 2 番 base=480。庄 1000、2 闲 500
	var ctx := WinContext.tsumo(Tile.new(TileId.W5), TileId.E, TileId.S_WIND, 0, 1)
	var p := PayoutCalculator.payout(480, ctx)
	assert_eq(p[0], 1000, "庄家出 1000")
	assert_eq(p[2], 500, "闲家 2 出 500")
	assert_eq(p[3], 500, "闲家 3 出 500")
	assert_false(p.has(1), "winner 不出钱")

func test_non_dealer_tsumo_with_honba():
	var ctx := WinContext.tsumo(Tile.new(TileId.W5), TileId.E, TileId.S_WIND, 0, 1)
	ctx.honba = 1
	var p := PayoutCalculator.payout(480, ctx)
	assert_eq(p[0], 1100, "庄家 1000 + 100")
	assert_eq(p[2], 600)
	assert_eq(p[3], 600)

# ---- 庄自摸 ----

func test_dealer_tsumo_base_480():
	# 庄家自摸 30符2番：3 闲各出 base*2 = 1000
	var ctx := WinContext.tsumo(Tile.new(TileId.W5), TileId.E, TileId.E, 0, 0)
	var p := PayoutCalculator.payout(480, ctx)
	assert_eq(p[1], 1000)
	assert_eq(p[2], 1000)
	assert_eq(p[3], 1000)
	assert_false(p.has(0), "winner=庄不出钱")

func test_dealer_tsumo_with_honba_2():
	var ctx := WinContext.tsumo(Tile.new(TileId.W5), TileId.E, TileId.E, 0, 0)
	ctx.honba = 2
	var p := PayoutCalculator.payout(480, ctx)
	assert_eq(p[1], 1200, "1000 + 200 (2 本场)")
	assert_eq(p[2], 1200)
	assert_eq(p[3], 1200)

# ---- 闲荣胡 ----

func test_non_dealer_ron_base_480():
	# 闲荣胡：base*4 = 1920 → ceil 2000
	var ctx := WinContext.ron(Tile.new(TileId.W5), TileId.E, TileId.S_WIND, 0, 1, 2)
	var p := PayoutCalculator.payout(480, ctx)
	assert_eq(p[2], 2000, "loser 出 2000")
	assert_eq(p.size(), 1)

func test_non_dealer_ron_with_honba():
	var ctx := WinContext.ron(Tile.new(TileId.W5), TileId.E, TileId.S_WIND, 0, 1, 2)
	ctx.honba = 2
	var p := PayoutCalculator.payout(480, ctx)
	assert_eq(p[2], 2000 + 600, "+ 2 本场 600")

# ---- 庄荣胡 ----

func test_dealer_ron_base_480():
	# 庄荣胡：base*6 = 2880 → 2900
	var ctx := WinContext.ron(Tile.new(TileId.W5), TileId.E, TileId.E, 0, 0, 1)
	var p := PayoutCalculator.payout(480, ctx)
	assert_eq(p[1], 2900)

func test_dealer_ron_mangan():
	# 庄荣胡满贯 base=2000：base*6 = 12000
	var ctx := WinContext.ron(Tile.new(TileId.W5), TileId.E, TileId.E, 0, 0, 2)
	var p := PayoutCalculator.payout(2000, ctx)
	assert_eq(p[2], 12000, "庄家荣胡满贯 12000")

func test_non_dealer_ron_mangan():
	var ctx := WinContext.ron(Tile.new(TileId.W5), TileId.E, TileId.S_WIND, 0, 1, 2)
	var p := PayoutCalculator.payout(2000, ctx)
	assert_eq(p[2], 8000, "闲家荣胡满贯 8000")

# ---- 庄自摸满贯 ----

func test_dealer_tsumo_mangan():
	var ctx := WinContext.tsumo(Tile.new(TileId.W5), TileId.E, TileId.E, 0, 0)
	var p := PayoutCalculator.payout(2000, ctx)
	# base*2=4000 各家 → 12000 总
	assert_eq(p[1], 4000)
	assert_eq(p[2], 4000)
	assert_eq(p[3], 4000)

func test_non_dealer_tsumo_mangan():
	var ctx := WinContext.tsumo(Tile.new(TileId.W5), TileId.E, TileId.S_WIND, 0, 1)
	var p := PayoutCalculator.payout(2000, ctx)
	# 庄 4000、2 闲 2000 = 8000 总
	assert_eq(p[0], 4000)
	assert_eq(p[2], 2000)
	assert_eq(p[3], 2000)

# ---- 包牌 ----

func test_pao_dealer_tsumo_full_burden():
	# 庄自摸 + pao：pao_seat 出全 12000
	var ctx := WinContext.tsumo(Tile.new(TileId.HAKU), TileId.E, TileId.E, 0, 0)
	ctx.pao_seat = 2
	var p := PayoutCalculator.payout(2000, ctx)
	assert_eq(p[2], 12000, "pao_seat 出全 12000")
	assert_false(p.has(1))
	assert_false(p.has(3))

func test_pao_non_dealer_tsumo_full_burden():
	# 闲自摸 + pao：pao_seat 出全 8000
	var ctx := WinContext.tsumo(Tile.new(TileId.HAKU), TileId.E, TileId.S_WIND, 0, 1)
	ctx.pao_seat = 3
	var p := PayoutCalculator.payout(2000, ctx)
	assert_eq(p[3], 8000)
	assert_false(p.has(0))
	assert_false(p.has(2))

func test_pao_ron_split_half():
	# 闲荣胡 + pao：pao_seat 与 loser 各半 (8000/2=4000)
	var ctx := WinContext.ron(Tile.new(TileId.HAKU), TileId.E, TileId.S_WIND, 0, 1, 2)
	ctx.pao_seat = 3
	var p := PayoutCalculator.payout(2000, ctx)
	assert_eq(p[2], 4000)
	assert_eq(p[3], 4000)
