class_name ScoreContext

# 胡牌瞬时上下文。区别于持续的 BattleState，本对象只携带一次胡牌结算所需的全部入参。
# 所有 seat 字段取值 0..3；不适用时用 NO_SEAT 哨兵。

const NO_SEAT: int = -1

var winning_tile: Tile

var is_tsumo: bool = false           # 自摸 vs 荣胡

# 立直相关
var is_riichi: bool = false
var is_double_riichi: bool = false   # 第一巡立直（蕴含 is_riichi=true）
var is_ippatsu: bool = false         # 一发窗口内胡牌

# 4 种特殊和牌时机
var is_haitei: bool = false          # 海底捞月（自摸）
var is_houtei: bool = false          # 河底捞鱼（荣胡）
var is_rinshan: bool = false         # 岭上开花（自摸）
var is_chankan: bool = false         # 抢杠

# 风
var round_wind: int = TileId.E       # 场风（东风战恒为东）
var seat_wind: int = TileId.E        # 自风

# 结算
var honba: int = 0                   # 本场数
var riichi_sticks: int = 0           # 桌上立直棒数（含本局）

# Seat 标识
var dealer_seat: int = 0             # 庄家
var winner_seat: int = 0             # 胡牌者
var loser_seat: int = NO_SEAT        # 放铳者（仅荣胡有效）
var pao_seat: int = NO_SEAT          # 包牌责任者（不触发时为 NO_SEAT）

static func tsumo(p_winning_tile: Tile, p_round_wind: int, p_seat_wind: int, p_dealer_seat: int, p_winner_seat: int) -> ScoreContext:
	var ctx := ScoreContext.new()
	ctx.winning_tile = p_winning_tile
	ctx.is_tsumo = true
	ctx.round_wind = p_round_wind
	ctx.seat_wind = p_seat_wind
	ctx.dealer_seat = p_dealer_seat
	ctx.winner_seat = p_winner_seat
	ctx.loser_seat = NO_SEAT
	return ctx

static func ron(p_winning_tile: Tile, p_round_wind: int, p_seat_wind: int, p_dealer_seat: int, p_winner_seat: int, p_loser_seat: int) -> ScoreContext:
	var ctx := ScoreContext.new()
	ctx.winning_tile = p_winning_tile
	ctx.is_tsumo = false
	ctx.round_wind = p_round_wind
	ctx.seat_wind = p_seat_wind
	ctx.dealer_seat = p_dealer_seat
	ctx.winner_seat = p_winner_seat
	ctx.loser_seat = p_loser_seat
	return ctx

func winner_is_dealer() -> bool:
	return winner_seat == dealer_seat

func has_pao() -> bool:
	return pao_seat != NO_SEAT
