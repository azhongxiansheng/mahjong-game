extends GutTest

# BattleState (spec §5)：一局对战的快照 + 工厂。
# 0e 加字段：turn_count / first_round_active（spec §6.1 一发/双立直/九种九牌依赖）

func test_default_construct_empty():
	var s := BattleState.new()
	assert_eq(s.seats.size(), 0)
	assert_eq(s.honba, 0)
	assert_eq(s.riichi_sticks, 0)
	assert_eq(s.turn_count, 0)
	assert_true(s.first_round_active)
	assert_eq(s.event_chain_depth, 0)

# ---- for_east_round 工厂 ----

func test_factory_creates_4_seats():
	var s := BattleState.for_east_round(42, 0, 1, 0, 0)
	assert_eq(s.seats.size(), 4)

func test_factory_dealer_seat_wind_is_east():
	var s := BattleState.for_east_round(42, 0, 1, 0, 0)
	assert_eq(s.seats[0].seat_wind, TileId.E, "dealer 自风=东")
	assert_eq(s.seats[1].seat_wind, TileId.S_WIND)
	assert_eq(s.seats[2].seat_wind, TileId.W_WIND)
	assert_eq(s.seats[3].seat_wind, TileId.N)

func test_factory_dealer_2_seat_winds_rotate():
	# dealer_seat=2: seats[2]=E, seats[3]=S, seats[0]=W, seats[1]=N
	var s := BattleState.for_east_round(42, 2, 1, 0, 0)
	assert_eq(s.seats[2].seat_wind, TileId.E)
	assert_eq(s.seats[3].seat_wind, TileId.S_WIND)
	assert_eq(s.seats[0].seat_wind, TileId.W_WIND)
	assert_eq(s.seats[1].seat_wind, TileId.N)

func test_factory_round_wind_is_east_for_east_round():
	var s := BattleState.for_east_round(42, 0, 1, 0, 0)
	assert_eq(s.round_wind, TileId.E)

func test_factory_each_seat_starts_with_13_tiles():
	var s := BattleState.for_east_round(42, 0, 1, 0, 0)
	for seat_id in range(4):
		assert_eq(s.seats[seat_id].hand.size(), 13, "seat %d 应 13 张" % seat_id)

func test_factory_live_wall_after_deal():
	# 122 live wall - 13×4 dealt = 70
	var s := BattleState.for_east_round(42, 0, 1, 0, 0)
	assert_eq(s.wall.live_wall_size(), 70)

func test_factory_dora_indicator_revealed():
	var s := BattleState.for_east_round(42, 0, 1, 0, 0)
	assert_eq(s.dora_indicators.visible.size(), 1, "开局翻 1 张 dora indicator")

func test_factory_phase_is_draw():
	var s := BattleState.for_east_round(42, 0, 1, 0, 0)
	assert_eq(s.phase, BattlePhase.Kind.DRAW)

func test_factory_current_seat_is_dealer():
	var s := BattleState.for_east_round(42, 1, 1, 0, 0)
	assert_eq(s.current_seat, 1)

func test_factory_discards_per_seat_initialized_empty():
	var s := BattleState.for_east_round(42, 0, 1, 0, 0)
	assert_eq(s.discards_per_seat.size(), 4)
	for arr in s.discards_per_seat:
		assert_eq(arr.size(), 0)

func test_factory_passes_honba_and_sticks():
	var s := BattleState.for_east_round(42, 0, 2, 3, 1)
	assert_eq(s.hand_number, 2)
	assert_eq(s.honba, 3)
	assert_eq(s.riichi_sticks, 1)

func test_factory_deterministic_with_seed():
	var s1 := BattleState.for_east_round(123, 0, 1, 0, 0)
	var s2 := BattleState.for_east_round(123, 0, 1, 0, 0)
	# 同种子下 dealer 起手应一致
	assert_eq(s1.seats[0].hand.to_id_array(), s2.seats[0].hand.to_id_array())
