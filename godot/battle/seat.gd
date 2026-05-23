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
# 刚摸到的牌 id（含正常摸牌 + 杠后岭上摸）。-1 = 当前不在 post-draw 状态（弃牌后 / 鸣牌后）。
# 日麻 UI 用于：(a) 立直后自动 tsumogiri 弃刚摸的牌；(b) 手牌渲染时把刚摸的牌单独显示
# 在最右（让玩家看清楚摸到了什么）。状态由 TurnEngine 维护：
#   - draw_for_current()         → 设为摸到的 id
#   - apply_minkan/ankan/added_kan + _take_rinshan_to → 设为岭上的 id
#   - discard()                  → 设回 -1
#   - apply_chi/pon              → 设回 -1（claimant 没真摸牌，是吃/碰别人的）
var last_drawn_tile_id: int = -1
# 刚摸的那张牌是否来自岭上(杠后岭上摸)。true 时 BattleController 在 _step_discard
# 开头检 tsumo,允许岭上开花(rinshan kaihou,+1 han 役)。draw_for_current 摸正常
# 牌时回 false;_take_rinshan_to 摸岭上时设 true。修复前:is_rinshan dead code,
# 玩家明杠后即使胡也不算岭上开花。
var last_draw_is_rinshan: bool = false

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
