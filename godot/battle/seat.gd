class_name Seat

# 一座位的数据 + 简单 helper（spec §5）。
# 弃牌河由 BattleState.discards_per_seat 单独维护，本对象不存。
# deck_owner 字段（卡组系统）属里程碑 4，0e 不实装。

const DEFAULT_STARTING_POINTS: int = 25000

var seat_id: int
var seat_wind: int
var hand: Hand
var melds: Array = []
var points: int
var riichi: RiichiState
var furiten: FuritenState

func _init(p_seat_id: int, p_seat_wind: int, p_points: int = DEFAULT_STARTING_POINTS) -> void:
	seat_id = p_seat_id
	seat_wind = p_seat_wind
	points = p_points
	hand = Hand.new()
	riichi = RiichiState.new()
	furiten = FuritenState.new()

func add_to_hand(t: Tile) -> void:
	hand.add(t)

func discard_from_hand(tile_id: int) -> bool:
	return hand.remove_by_id(tile_id)

func is_concealed_hand() -> bool:
	# 门清：melds 中只允许 ANKAN
	for m in melds:
		if m.kind != Meld.Kind.ANKAN:
			return false
	return true

func adjust_points(delta: int) -> void:
	points += delta
