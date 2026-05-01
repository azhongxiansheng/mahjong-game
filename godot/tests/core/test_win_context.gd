extends GutTest

# WinContext: 胡牌瞬时上下文（区别于持续的 BattleState）
# - winning_tile: 自摸/荣胡的那张
# - is_tsumo: 自摸 vs 荣胡
# - is_riichi/double_riichi/ippatsu: 立直状态
# - is_haitei/houtei/rinshan/chankan: 4 种特殊和牌时机
# - round_wind/seat_wind: 场风/自风（用 TileId.E/S_WIND/W_WIND/N）
# - honba/riichi_sticks: 本场 + 立直棒（结算用）
# - dealer_seat/winner_seat/loser_seat/pao_seat: 4 个 seat 标识
#   loser_seat 仅荣胡有效，pao_seat 不触发时为 NO_SEAT

func test_default_values():
	var ctx := WinContext.new()
	assert_false(ctx.is_tsumo)
	assert_false(ctx.is_riichi)
	assert_false(ctx.is_double_riichi)
	assert_false(ctx.is_ippatsu)
	assert_false(ctx.is_haitei)
	assert_false(ctx.is_houtei)
	assert_false(ctx.is_rinshan)
	assert_false(ctx.is_chankan)
	assert_eq(ctx.honba, 0)
	assert_eq(ctx.riichi_sticks, 0)
	assert_eq(ctx.loser_seat, WinContext.NO_SEAT)
	assert_eq(ctx.pao_seat, WinContext.NO_SEAT)

func test_tsumo_factory():
	var ctx := WinContext.tsumo(
		Tile.new(TileId.W5),
		TileId.E,        # round_wind
		TileId.S_WIND,   # seat_wind
		0,               # dealer_seat
		1,               # winner_seat
	)
	assert_true(ctx.is_tsumo)
	assert_eq(ctx.winning_tile.id, TileId.W5)
	assert_eq(ctx.round_wind, TileId.E)
	assert_eq(ctx.seat_wind, TileId.S_WIND)
	assert_eq(ctx.dealer_seat, 0)
	assert_eq(ctx.winner_seat, 1)
	assert_eq(ctx.loser_seat, WinContext.NO_SEAT, "自摸无放铳者")

func test_ron_factory():
	var ctx := WinContext.ron(
		Tile.new(TileId.T3),
		TileId.E,
		TileId.E,        # 庄家自风也是东
		0,
		0,               # winner = dealer
		2,               # loser_seat
	)
	assert_false(ctx.is_tsumo)
	assert_eq(ctx.winning_tile.id, TileId.T3)
	assert_eq(ctx.winner_seat, 0)
	assert_eq(ctx.loser_seat, 2)

func test_winner_is_dealer_helper():
	var ctx_dealer := WinContext.tsumo(Tile.new(TileId.W1), TileId.E, TileId.E, 0, 0)
	assert_true(ctx_dealer.winner_is_dealer())
	var ctx_non := WinContext.tsumo(Tile.new(TileId.W1), TileId.E, TileId.S_WIND, 0, 1)
	assert_false(ctx_non.winner_is_dealer())

func test_riichi_flags_settable():
	var ctx := WinContext.tsumo(Tile.new(TileId.W5), TileId.E, TileId.S_WIND, 0, 1)
	ctx.is_riichi = true
	ctx.is_ippatsu = true
	ctx.is_double_riichi = true
	assert_true(ctx.is_riichi)
	assert_true(ctx.is_ippatsu)
	assert_true(ctx.is_double_riichi)

func test_honba_and_sticks():
	var ctx := WinContext.ron(Tile.new(TileId.T3), TileId.E, TileId.E, 0, 0, 2)
	ctx.honba = 3
	ctx.riichi_sticks = 2
	assert_eq(ctx.honba, 3)
	assert_eq(ctx.riichi_sticks, 2)

func test_pao_seat_settable():
	var ctx := WinContext.ron(Tile.new(TileId.HAKU), TileId.E, TileId.S_WIND, 0, 1, 2)
	ctx.pao_seat = 3
	assert_eq(ctx.pao_seat, 3)
	assert_true(ctx.has_pao())

func test_no_seat_constant_is_negative():
	assert_lt(WinContext.NO_SEAT, 0, "用负值哨兵区分有效 seat (0..3)")
