class_name FourPlayerTable extends Control

# 麻将王 — 里程碑 3 第 2 步：4 人桌主场景（plan-3 D4）
#
# 职责（v1，第 2 步骨架版）：
#   - 实例化 4 个 SeatPanel + CenterInfoPanel + AbilityPanel
#   - 4 个 SeatPanel 按 seat_id 自动旋转 0/-90/180/+90 度，摆 4 方位
#   - 暴露 setter API 让外部驱动（GameDriver / SmokeScene）注入数据
#
# 不在第 2 步范围：
#   - 真实牌纹理（→ 第 3 步 card_tile_back.gd）
#   - 与 GameDriver 集成（→ 第 4 步 four_player_table_smoke.tscn）
#   - 印章 + tooltip + 透明牌（→ 第 3 步）

# 4 人桌默认尺寸（spec §14 v1 默认）；右侧 200px 给 AbilityPanel
const TABLE_WIDTH: float = 1080.0
const TABLE_HEIGHT: float = 720.0
const ABILITY_PANEL_WIDTH: float = 200.0

const SEAT_PANEL_SCENE := preload("res://ui/four_player_table/seat_panel.tscn")
const CENTER_INFO_SCENE := preload("res://ui/four_player_table/center_info_panel.tscn")
const ABILITY_PANEL_SCENE := preload("res://ui/four_player_table/ability_panel.tscn")

# 4 个 seat_panel 实例（索引 = seat_id）
var seat_panels: Array[SeatPanel] = []
var center_info: CenterInfoPanel = null
var ability_panel: AbilityPanel = null

func _ready() -> void:
	custom_minimum_size = Vector2(TABLE_WIDTH + ABILITY_PANEL_WIDTH, TABLE_HEIGHT)
	_build_layout()

# ---- public setters ----

# 把当前 hand 的 BattleState 喂给 4 个 seat panel + center
# M8: hands_per_round_arg 默认 4 兼容 M7；半庄战调用方仍传 4 但 hand_index
# 从 0..7 表示东 1..南 4
func bind_battle_state(state: BattleState, hand_index: int, hands_per_round_arg: int = 4) -> void:
	if center_info:
		center_info.bind_state(state, hand_index, hands_per_round_arg)
	for i in range(seat_panels.size()):
		var sp: SeatPanel = seat_panels[i]
		var seat: Seat = state.seats[i]
		sp.bind_seat(seat)
		sp.set_discards_count(state.discards_per_seat[i].size())

# 整场累计分（来自 GameDriver.cumulative_scores）
func bind_cumulative_scores(scores: Array) -> void:
	for i in range(seat_panels.size()):
		seat_panels[i].set_score(int(scores[i]))

# ---- helpers ----

# 静态：seat_id → 桌面坐标（相对 Table 区域）。
# 0=下、1=右、2=上、3=左；中央为 (TABLE_WIDTH/2, TABLE_HEIGHT/2)。
static func seat_position(seat_id: int) -> Vector2:
	var cx := TABLE_WIDTH / 2.0
	var cy := TABLE_HEIGHT / 2.0
	var margin := 110.0
	match seat_id:
		0:
			return Vector2(cx, TABLE_HEIGHT - margin)
		1:
			return Vector2(TABLE_WIDTH - margin, cy)
		2:
			return Vector2(cx, margin)
		3:
			return Vector2(margin, cy)
	return Vector2(cx, cy)

# 默认风牌：dealer 是 E，按 seat_id 与 dealer 偏移决定。
# 但本面板暂不持 dealer 信息；调用方在 bind_battle_state 时由 Seat.seat_wind 直接喂。

# ---- internal ----

func _build_layout() -> void:
	# Bg 已在 .tscn 中；此处只放子节点。
	var table := Node2D.new()
	table.name = "Table"
	table.position = Vector2(0, 0)
	add_child(table)

	# 4 个 SeatPanel
	for i in range(4):
		var sp: SeatPanel = SEAT_PANEL_SCENE.instantiate()
		sp.position = seat_position(i)
		sp.set_seat_id(i)  # 自动旋转
		table.add_child(sp)
		seat_panels.append(sp)

	# CenterInfoPanel
	center_info = CENTER_INFO_SCENE.instantiate()
	center_info.position = Vector2(TABLE_WIDTH / 2.0, TABLE_HEIGHT / 2.0)
	table.add_child(center_info)

	# AbilityPanel（右侧外延）
	ability_panel = ABILITY_PANEL_SCENE.instantiate()
	ability_panel.position = Vector2(TABLE_WIDTH, 0)
	add_child(ability_panel)
