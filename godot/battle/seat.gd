class_name Seat

# 一座位的数据 + 简单 helper（spec §5）。
# Seat 是席位聚合根，统一持有手牌、牌河与副露。
# deck_owner 字段（卡组系统）属里程碑 4，0e 不实装。

const DEFAULT_STARTING_POINTS: int = 25000

var seat_id: int
var seat_wind: int
var hand: Hand
var river: DiscardRiver
var melds: MeldCollection
var points: int
var riichi: RiichiState
var furiten: FuritenState
# E2-02 / #232：刚摸实体 identity；INVALID_INSTANCE_ID = 当前不在 post-draw。
var last_drawn_instance_id: int = Tile.INVALID_INSTANCE_ID
# 刚摸的那张牌是否来自岭上(杠后岭上摸)。true 时 BattleController 在 _step_discard
# 开头检 tsumo,允许岭上开花(rinshan kaihou,+1 han 役)。draw_for_current 摸正常
# 牌时回 false;_take_rinshan_to 摸岭上时设 true。修复前:is_rinshan dead code,
# 玩家明杠后即使胡也不算岭上开花。
var last_draw_is_rinshan: bool = false
# E2-02 / #232：本座位本局副露序号；公开 meld_id 以四席交错编码，
# `local_index * 4 + seat_id`，从而无需共享可变分配器也能保证同局全局唯一。

func _init(p_seat_id: int, p_seat_wind: int, p_points: int = DEFAULT_STARTING_POINTS) -> void:
	seat_id = p_seat_id
	seat_wind = p_seat_wind
	points = p_points
	hand = Hand.new()
	river = DiscardRiver.new()
	melds = MeldCollection.new(seat_id)
	riichi = RiichiState.new()
	furiten = FuritenState.new()
	last_drawn_instance_id = Tile.INVALID_INSTANCE_ID

func add_to_hand(t: Tile) -> void:
	hand.add(t)

# E2-02 / #232：按实体 instance_id 精确弃牌；无 tile_id fallback；fail-closed。
func discard_from_hand(instance_id: Variant) -> bool:
	return hand.take_by_instance_id(instance_id) != null

func is_concealed_hand() -> bool:
	# 门清：melds 中只允许 ANKAN
	for m in melds.all():
		if m.kind != Meld.Kind.ANKAN:
			return false
	return true

func adjust_points(delta: int) -> void:
	points += delta
