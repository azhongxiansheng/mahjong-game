class_name BattleState

# 一局对战快照（spec §5）。
# 合并自 plan 0e（含 seats/wall/phase 等完整对战字段）与 main PR #8 里程碑 1（技能框架字段）。
# 两条路线共存：
#   - 0e 字段：seats / wall / dora_indicators / discards_per_seat / phase / current/dealer 等
#     —— TurnEngine 与 ScoreCalc 用
#   - 里程碑 1 字段：scores / furiten_flags / ron_cancelled / revealed_tiles / haitei_forced_seat
#     —— SkillScheduler 与 SkillCtx 用
# 注：scores 与 seats[i].points 在概念上重复；当前两个分支独立维护各自的来源，后续 plan
# 应将一者改为派生（避免漂移）。0e 已加 turn_count 维护巡数。

const MAX_EVENT_CHAIN_DEPTH := 16
const STARTING_SCORE := 25000

const _SEAT_WINDS: Array = [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N]

# 0e 完整对战字段
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

# 0e 巡数 / 第一巡
var turn_count: int = 0
var first_round_active: bool = true

# 共享
var event_chain_depth: int = 0

# 里程碑 1 技能框架字段（SkillScheduler/SkillCtx 用）
var scores: Array[int] = [STARTING_SCORE, STARTING_SCORE, STARTING_SCORE, STARTING_SCORE]
var furiten_flags: Array[bool] = [false, false, false, false]
var ron_cancelled: Array[bool] = [false, false, false, false]
var revealed_tiles: Array = []
var haitei_forced_seat: int = -1
# M7 ctx B2 — Dora 系：per-seat 额外 dora / red dora 计数（hook 通过
# mark_extra_dora_for_seat / mark_red_dora_for_seat 累加，BattleController
# 在 ScoreCalc 之前把对应 seat 的额外 count 加到 yaku_list.dora_count 上）
var extra_dora_count: Array[int] = [0, 0, 0, 0]
var extra_red_dora_count: Array[int] = [0, 0, 0, 0]

static func for_east_round(rng_seed: int, p_dealer: int, hand_number_arg: int, honba_arg: int, riichi_sticks_arg: int, round_wind_arg: int = TileId.E) -> BattleState:
	# round_wind_arg: M8 半庄战支持。默认东（兼容 M7）；半庄战南场由 GameDriver
	# 在 hand_index >= hands_per_round 时传 TileId.S_WIND。函数名仍叫 for_east_round
	# 是历史命名（实际是"为某局风圈实例化 state"），保持名字避免大改 API surface。
	var s := BattleState.new()
	s.hand_number = hand_number_arg
	s.honba = honba_arg
	s.riichi_sticks = riichi_sticks_arg
	s.dealer_seat = p_dealer
	s.current_seat = p_dealer
	s.round_wind = round_wind_arg

	# 4 seat：自风按 dealer 旋转（dealer 是 E）
	for i in range(4):
		var relative: int = (i - p_dealer + 4) % 4
		var seat_wind: int = _SEAT_WINDS[relative]
		s.seats.append(Seat.new(i, seat_wind))
		s.discards_per_seat.append([])

	# 牌墙：洗 + 切 dead wall
	s.wall = Wall.new_full_set()
	s.wall.shuffle(rng_seed)
	s.wall.reserve_dead_wall(14)

	# 翻初始 dora indicator
	s.dora_indicators = DoraIndicators.new()
	s.dora_indicators.add_visible(s.wall.peek_dora_indicator(0))

	# 发 13 张 × 4
	for _i in range(13):
		for seat_id in range(4):
			s.seats[seat_id].add_to_hand(s.wall.draw())

	return s
