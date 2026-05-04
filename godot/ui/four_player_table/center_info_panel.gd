class_name CenterInfoPanel extends Node2D

# 麻将王 — 里程碑 3 第 2 步：中心信息板
#
# 显示：局（东 N 局）/ 本场 / Dora 指示牌列 / 牌墙剩余张数
# 数据通过 setter 注入，本身不持 BattleState 引用。

@onready var _label_round: Label = $VBox/Round
@onready var _label_dora: Label = $VBox/Dora
@onready var _label_wall: Label = $VBox/Wall
@onready var _label_riichi: Label = $VBox/RiichiSticks

var _hand_index: int = 0  # 0..3 表东 1..东 4；M8 半庄战 4..7 表南 1..南 4
var _hands_per_round: int = 4  # M8: 一风圈局数（东/南各 4）
var _honba: int = 0
var _dora_indicators: Array = []  # Array[int] of TileId
var _wall_remaining: int = 70  # 一局起手 70 张 live wall
var _riichi_sticks: int = 0

func _ready() -> void:
	_refresh_labels()

# ---- public setters ----

func set_hand_index(idx: int) -> void:
	_hand_index = idx
	if is_inside_tree():
		_refresh_labels()

# M8: 半庄战调用方需 set 此值为 4（一风圈 4 局），让 round_name 推进到南场
func set_hands_per_round(n: int) -> void:
	_hands_per_round = n
	if is_inside_tree():
		_refresh_labels()

func set_honba(n: int) -> void:
	_honba = n
	if is_inside_tree():
		_refresh_labels()

func set_dora_indicators(ids: Array) -> void:
	_dora_indicators = ids
	if is_inside_tree():
		_refresh_labels()

func set_wall_remaining(n: int) -> void:
	_wall_remaining = n
	if is_inside_tree():
		_refresh_labels()

func set_riichi_sticks(n: int) -> void:
	_riichi_sticks = n
	if is_inside_tree():
		_refresh_labels()

# 一次注入 BattleState 摘要（供 GameDriver / SmokeScene 用）
# M8: hands_per_round_arg 默认 4 兼容 M7；半庄战调用方传 4（不变）但
# 要求传足够大的 hand_index_arg（4..7 表南 1..南 4）
func bind_state(state: BattleState, hand_index_arg: int, hands_per_round_arg: int = 4) -> void:
	_hand_index = hand_index_arg
	_hands_per_round = hands_per_round_arg
	_honba = state.honba
	_riichi_sticks = state.riichi_sticks
	_wall_remaining = state.wall.live_wall_size()
	_dora_indicators = []
	for ti in state.dora_indicators.visible:
		_dora_indicators.append(ti.id)
	if is_inside_tree():
		_refresh_labels()

# ---- helpers ----

# 局数显示 "东 N 局" / "南 N 局"
# M8: hands_per_round 决定一风圈几局（默认 4）；hand_index 0..hands_per_round-1
# 是东，hands_per_round..2*hands_per_round-1 是南，超出走 fallback "局 N"
static func round_name(hand_index: int, hands_per_round: int = 4) -> String:
	if hand_index < 0:
		return "局 %d" % (hand_index + 1)
	var local: int = hand_index % hands_per_round
	var round_index: int = hand_index / hands_per_round
	match round_index:
		0: return "东 %d 局" % (local + 1)
		1: return "南 %d 局" % (local + 1)
		_: return "局 %d" % (hand_index + 1)

# Dora 列简短显示
static func dora_summary(ids: Array) -> String:
	if ids.size() == 0:
		return "Dora: -"
	var parts: Array[String] = []
	for id in ids:
		parts.append(_tile_short_name(int(id)))
	return "Dora: " + ", ".join(parts)

static func _tile_short_name(tile_id: int) -> String:
	if tile_id < 9:
		return "%d万" % (tile_id + 1)
	if tile_id < 18:
		return "%d筒" % (tile_id - 8)
	if tile_id < 27:
		return "%d条" % (tile_id - 17)
	match tile_id:
		TileId.E: return "东"
		TileId.S_WIND: return "南"
		TileId.W_WIND: return "西"
		TileId.N: return "北"
		TileId.HAKU: return "白"
		TileId.HATSU: return "发"
		TileId.CHUN: return "中"
	return "?"

# ---- internal ----

func _refresh_labels() -> void:
	if _label_round == null:
		return
	var honba_str := " %d 本场" % _honba if _honba > 0 else ""
	_label_round.text = "%s%s" % [round_name(_hand_index, _hands_per_round), honba_str]
	_label_dora.text = dora_summary(_dora_indicators)
	_label_wall.text = "牌墙: %d / 70" % _wall_remaining
	_label_riichi.text = "立直棒: %d" % _riichi_sticks
