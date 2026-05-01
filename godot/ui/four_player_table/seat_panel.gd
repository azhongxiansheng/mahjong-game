class_name SeatPanel extends Node2D

# 麻将王 — 里程碑 3 第 2 步：单 seat 面板（plan-3 D4）
#
# 职责（v1，第 2 步占位版）：
#   - 按 seat_id ∈ {0,1,2,3} 自动旋转 0/-90/180/+90 度
#   - 文字占位显示：seat 名称、风牌、立直/振听、点数、副露/手牌/弃牌河 张数
#   - 不渲染真实牌纹理（第 3 步 card_tile_back.gd 才接入）
#
# 数据流：外部调 set_xxx setter 注入；面板自己刷新文本 Label。
# Setter 风格让 GameDriver / SmokeScene 都可同样驱动，无需直接持 BattleState。

# Seat 0=玩家(下方)，1=右家，2=对家(上方)，3=左家。
# 旋转角让"AI 在镜头里看着是斜过来的"
const SEAT_ROTATION_DEGREES := [0.0, -90.0, 180.0, 90.0]

@onready var _label_seat_info: Label = $VBox/SeatInfo
@onready var _label_score: Label = $VBox/Score
@onready var _label_melds: Label = $VBox/Melds
@onready var _label_hand: Label = $VBox/Hand
@onready var _label_discards: Label = $VBox/Discards

var _seat_id: int = 0
var _seat_wind: int = TileId.E
var _score: int = 25000
var _hand_size: int = 13
var _meld_count: int = 0
var _discards_count: int = 0
var _riichi: bool = false
var _furiten: bool = false

func _ready() -> void:
	_refresh_labels()

# ---- public setters ----

func set_seat_id(id: int) -> void:
	assert(id >= 0 and id <= 3, "seat_id 必须 ∈ [0,3]")
	_seat_id = id
	rotation_degrees = SEAT_ROTATION_DEGREES[id]
	if is_inside_tree():
		_refresh_labels()

func set_seat_wind(wind_id: int) -> void:
	_seat_wind = wind_id
	if is_inside_tree():
		_refresh_labels()

func set_score(s: int) -> void:
	_score = s
	if is_inside_tree():
		_refresh_labels()

func set_hand_size(n: int) -> void:
	_hand_size = n
	if is_inside_tree():
		_refresh_labels()

func set_meld_count(n: int) -> void:
	_meld_count = n
	if is_inside_tree():
		_refresh_labels()

func set_discards_count(n: int) -> void:
	_discards_count = n
	if is_inside_tree():
		_refresh_labels()

func set_riichi(b: bool) -> void:
	_riichi = b
	if is_inside_tree():
		_refresh_labels()

func set_furiten(b: bool) -> void:
	_furiten = b
	if is_inside_tree():
		_refresh_labels()

# 一次注入 Seat 全部状态
func bind_seat(seat: Seat) -> void:
	_seat_wind = seat.seat_wind
	_score = seat.points
	_hand_size = seat.hand.size()
	_meld_count = seat.melds.size()
	_riichi = seat.riichi.declared
	_furiten = seat.furiten.is_furiten() if seat.furiten else false
	# discards 数量需外部传入（Seat 自身不持，BattleState.discards_per_seat[i] 持）
	if is_inside_tree():
		_refresh_labels()

# ---- helpers ----

# 静态 lookup：测试 / 外部布局算法用。
static func rotation_for_seat(seat_id: int) -> float:
	assert(seat_id >= 0 and seat_id <= 3)
	return SEAT_ROTATION_DEGREES[seat_id]

# Seat name 显示：seat 0 = "你"，其它 = "AI N"
static func seat_display_name(seat_id: int) -> String:
	if seat_id == 0:
		return "你"
	return "AI %d" % seat_id

static func wind_name(wind_id: int) -> String:
	match wind_id:
		TileId.E: return "东"
		TileId.S_WIND: return "南"
		TileId.W_WIND: return "西"
		TileId.N: return "北"
	return "?"

# ---- internal ----

func _refresh_labels() -> void:
	if _label_seat_info == null:
		return
	var status_parts: Array[String] = []
	if _riichi:
		status_parts.append("立直")
	if _furiten:
		status_parts.append("振听")
	var status_str: String = " | ".join(status_parts) if status_parts.size() > 0 else "—"

	_label_seat_info.text = "Seat %d (%s) | 风: %s | %s" % [
		_seat_id, seat_display_name(_seat_id), wind_name(_seat_wind), status_str
	]
	_label_score.text = "点数: %d" % _score
	_label_melds.text = "副露: [m×%d]" % _meld_count
	_label_hand.text = "手牌: [●×%d]" % _hand_size
	_label_discards.text = "弃牌河: [●×%d]" % _discards_count
