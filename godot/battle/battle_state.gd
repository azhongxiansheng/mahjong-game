class_name BattleState

# 一局对战快照（spec §5）。
# 0e 加字段：turn_count（spec §6.1 一发/双立直/九种九牌依赖巡数）+ first_round_active

const _SEAT_WINDS: Array = [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N]

var seats: Array = []                  # Array[Seat] 长度 4
var wall: Wall                         # 含 dead_wall 切片
var dora_indicators: DoraIndicators
var discards_per_seat: Array = []      # 4 个 Array[Tile]
var dealer_seat: int = 0               # 庄家 seat_id（一局内不变）
var current_seat: int = 0
var phase: int = BattlePhase.Kind.DRAW
var round_wind: int = TileId.E         # 东风战恒为东
var hand_number: int = 1               # 1..4 (东 1..东 4)
var honba: int = 0
var riichi_sticks: int = 0
var event_chain_depth: int = 0

# 0e 新增
var turn_count: int = 0
var first_round_active: bool = true

static func for_east_round(seed: int, dealer_seat: int, hand_number_arg: int, honba_arg: int, riichi_sticks_arg: int) -> BattleState:
	var s := BattleState.new()
	s.hand_number = hand_number_arg
	s.honba = honba_arg
	s.riichi_sticks = riichi_sticks_arg
	s.dealer_seat = dealer_seat
	s.current_seat = dealer_seat

	# 4 seat：自风按 dealer 旋转（dealer 是 E）
	for i in range(4):
		var relative: int = (i - dealer_seat + 4) % 4
		var seat_wind: int = _SEAT_WINDS[relative]
		s.seats.append(Seat.new(i, seat_wind))
		s.discards_per_seat.append([])

	# 牌墙：洗 + 切 dead wall
	s.wall = Wall.new_full_set()
	s.wall.shuffle(seed)
	s.wall.reserve_dead_wall(14)

	# 翻初始 dora indicator
	s.dora_indicators = DoraIndicators.new()
	s.dora_indicators.add_visible(s.wall.peek_dora_indicator(0))

	# 发 13 张 × 4
	for _i in range(13):
		for seat_id in range(4):
			s.seats[seat_id].add_to_hand(s.wall.draw())

	return s
