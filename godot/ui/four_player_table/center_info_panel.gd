class_name CenterInfoPanel extends Node2D

# 麻将王 — 里程碑 3 第 2 步：中心信息板
#
# 显示：局（东 N 局）/ 本场 / Dora 指示牌列 / 牌墙剩余张数
# 数据通过 setter 注入，本身不持 BattleState 引用。

@onready var _label_round: Label = $VBox/Round
@onready var _label_dora: Label = $VBox/Dora
@onready var _label_wall: Label = $VBox/Wall
@onready var _label_riichi: Label = $VBox/RiichiSticks

# Dora 指示牌真实牌图区(略加大,从 32x48 → 40x58 让海底/振听时更易快速识别)
const DORA_TILE_W: float = 40.0
const DORA_TILE_H: float = 58.0
const DORA_TILE_GAP: float = 3.0
var _dora_row: Node2D = null

# 立直棒视觉:每棒 24x6 白底中央红点;最多并排显示 5 根,N>5 时尾部加 "+N" 标签
const STICK_W: float = 24.0
const STICK_H: float = 6.0
const STICK_MAX_SHOW: int = 5
var _riichi_sticks_row: HBoxContainer = null
# 本场棒视觉:每棒 20x5 红底(真实 100-pt 棒比 1000-pt 立直棒略短)
const HONBA_STICK_W: float = 20.0
const HONBA_STICK_H: float = 5.0
var _honba_sticks_row: HBoxContainer = null

var _hand_index: int = 0  # 0..3 表东 1..东 4；M8 半庄战 4..7 表南 1..南 4
var _hands_per_round: int = 4  # M8: 一风圈局数（东/南各 4）
var _honba: int = 0
var _dora_indicators: Array = []  # Array[int] of TileId
var _wall_remaining: int = 70  # 一局起手 70 张 live wall
var _riichi_sticks: int = 0

func _ready() -> void:
	_dora_row = Node2D.new()
	# 放在 panel 中心稍下，让"Dora:"label 上面，牌图在下面
	_dora_row.position = Vector2(-60, 30)
	add_child(_dora_row)
	# 立直棒 / 本场棒 视觉行(VBox 末追加,与文字 label 呼应)
	var vbox: VBoxContainer = $VBox
	if vbox:
		_riichi_sticks_row = HBoxContainer.new()
		_riichi_sticks_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_riichi_sticks_row.add_theme_constant_override("separation", 3)
		vbox.add_child(_riichi_sticks_row)
		_honba_sticks_row = HBoxContainer.new()
		_honba_sticks_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_honba_sticks_row.add_theme_constant_override("separation", 3)
		vbox.add_child(_honba_sticks_row)
	_refresh_labels()
	_rebuild_dora_tiles()
	_rebuild_riichi_sticks()
	_rebuild_honba_sticks()

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
		_rebuild_honba_sticks()

func set_dora_indicators(ids: Array) -> void:
	_dora_indicators = ids
	if is_inside_tree():
		_refresh_labels()
		_rebuild_dora_tiles()

func set_wall_remaining(n: int) -> void:
	var prev: int = _wall_remaining
	_wall_remaining = n
	if is_inside_tree():
		_refresh_labels()
		# 牌墙跌入终盘警戒区(≤10)时启脉冲,玩家不会错过"快流局了"。
		# 升回 >10(刚开新局)关脉冲。
		_apply_wall_pulse(prev, n)

func set_riichi_sticks(n: int) -> void:
	_riichi_sticks = n
	if is_inside_tree():
		_refresh_labels()
		_rebuild_riichi_sticks()

# 一次注入 BattleState 摘要（供 GameDriver / SmokeScene 用）
# M8: hands_per_round_arg 默认 4 兼容 M7；半庄战调用方传 4（不变）但
# 要求传足够大的 hand_index_arg（4..7 表南 1..南 4）
func bind_state(state: BattleState, hand_index_arg: int, hands_per_round_arg: int = 4) -> void:
	_hand_index = hand_index_arg
	_hands_per_round = hands_per_round_arg
	_honba = state.honba
	_riichi_sticks = state.riichi_sticks
	var prev_wall: int = _wall_remaining
	_wall_remaining = state.wall.live_wall_size()
	_dora_indicators = []
	for ti in state.dora_indicators.visible:
		_dora_indicators.append(ti.id)
	if is_inside_tree():
		_refresh_labels()
		_rebuild_dora_tiles()
		_rebuild_riichi_sticks()
		_apply_wall_pulse(prev_wall, _wall_remaining)

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
		parts.append(CardTileBack.tile_short_name(int(id)))
	return "Dora: " + ", ".join(parts)

# ---- internal ----

func _refresh_labels() -> void:
	if _label_round == null:
		return
	var honba_str := " %d 本场" % _honba if _honba > 0 else ""
	_label_round.text = "%s%s" % [round_name(_hand_index, _hands_per_round), honba_str]
	_label_dora.text = "Dora 指示牌:"
	_label_wall.text = "牌墙: %d / 70" % _wall_remaining
	# 牌墙剩余分级配色:海底警戒(≤4 红) / 终盘(≤10 橙) / 中盘(≤30 黄) / 早盘(白)
	_label_wall.add_theme_color_override("font_color", wall_color(_wall_remaining))
	_label_riichi.text = "立直棒: %d" % _riichi_sticks
	# 池里有立直棒时高亮金色,强调"赢家可独吞"。
	if _riichi_sticks > 0:
		_label_riichi.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	else:
		_label_riichi.remove_theme_color_override("font_color")


# 牌墙剩余张数颜色分级(公开供单测)。
static func wall_color(remaining: int) -> Color:
	if remaining <= 4:
		return Color(1.0, 0.30, 0.30)   # 海底/河底警戒 红
	if remaining <= 10:
		return Color(1.0, 0.55, 0.20)   # 终盘 橙
	if remaining <= 30:
		return Color(0.95, 0.85, 0.30)  # 中盘 黄
	return Color(0.92, 0.90, 0.82)      # 早盘 骨白


# 牌墙进入终盘(≤10)启动脉冲;升回 >10 停。tween 用 set_loops 永久循环
# alpha 1.0 ↔ 0.55,周期 0.6s。
const WALL_WARNING_THRESHOLD: int = 10
var _wall_pulse_tween: Tween = null

func _apply_wall_pulse(prev: int, new_n: int) -> void:
	if _label_wall == null:
		return
	var should_pulse: bool = (new_n <= WALL_WARNING_THRESHOLD)
	# 已 active 且仍应继续 — 不重启 tween,避免抖。
	if should_pulse:
		if _wall_pulse_tween != null and _wall_pulse_tween.is_valid():
			return
		_wall_pulse_tween = create_tween().set_loops()
		_wall_pulse_tween.tween_property(_label_wall, "modulate:a", 0.55, 0.3)\
			.set_trans(Tween.TRANS_SINE)
		_wall_pulse_tween.tween_property(_label_wall, "modulate:a", 1.0, 0.3)\
			.set_trans(Tween.TRANS_SINE)
	else:
		# 出警戒区(刚开新局 wall 70 ← prev 0)→ 停脉冲恢复 alpha
		if _wall_pulse_tween != null and _wall_pulse_tween.is_valid():
			_wall_pulse_tween.kill()
		_wall_pulse_tween = null
		_label_wall.modulate.a = 1.0

# 重建立直棒视觉行(N 根白底红点的迷你棒;N>STICK_MAX_SHOW 时尾部 "+N" 文字)。
func _rebuild_riichi_sticks() -> void:
	if _riichi_sticks_row == null:
		return
	for child in _riichi_sticks_row.get_children():
		child.queue_free()
	var shown: int = mini(_riichi_sticks, STICK_MAX_SHOW)
	for i in range(shown):
		_riichi_sticks_row.add_child(_make_riichi_stick())
	if _riichi_sticks > STICK_MAX_SHOW:
		var extra := Label.new()
		extra.text = "+%d" % (_riichi_sticks - STICK_MAX_SHOW)
		extra.add_theme_font_size_override("font_size", 11)
		extra.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		_riichi_sticks_row.add_child(extra)


# 1 根迷你立直棒:24x6 骨白底 + 中央 8x6 红点(模拟真实棒上的红色识别条)。
static func _make_riichi_stick() -> Control:
	var stick := ColorRect.new()
	stick.color = Color(0.95, 0.93, 0.85)
	stick.custom_minimum_size = Vector2(STICK_W, STICK_H)
	stick.size = Vector2(STICK_W, STICK_H)
	stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := ColorRect.new()
	dot.color = Color(0.85, 0.18, 0.18)
	dot.size = Vector2(8, STICK_H)
	dot.position = Vector2((STICK_W - 8) / 2, 0)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stick.add_child(dot)
	return stick


# 重建本场棒行:连庄棒(100-pt 棒,日麻视觉上比立直棒略短的红色棒)。
# 每局 dealer 连庄 / 流局都 +1,N=0 时整行不渲染。
func _rebuild_honba_sticks() -> void:
	if _honba_sticks_row == null:
		return
	for child in _honba_sticks_row.get_children():
		child.queue_free()
	var shown: int = mini(_honba, STICK_MAX_SHOW)
	for i in range(shown):
		_honba_sticks_row.add_child(_make_honba_stick())
	if _honba > STICK_MAX_SHOW:
		var extra := Label.new()
		extra.text = "+%d" % (_honba - STICK_MAX_SHOW)
		extra.add_theme_font_size_override("font_size", 11)
		extra.add_theme_color_override("font_color", Color(1, 0.55, 0.45))
		_honba_sticks_row.add_child(extra)


# 1 根迷你本场棒:20x5 全红(无白色识别条,与立直棒区分)。
static func _make_honba_stick() -> Control:
	var stick := ColorRect.new()
	stick.color = Color(0.85, 0.20, 0.20)
	stick.custom_minimum_size = Vector2(HONBA_STICK_W, HONBA_STICK_H)
	stick.size = Vector2(HONBA_STICK_W, HONBA_STICK_H)
	stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return stick


# 重建 Dora 指示牌真实图（每张 32x48 小尺寸 face_up CardTileBack）。
func _rebuild_dora_tiles() -> void:
	if _dora_row == null:
		return
	for child in _dora_row.get_children():
		child.queue_free()
	var sx: float = DORA_TILE_W / float(CardTileBack.TILE_WIDTH)
	var sy: float = DORA_TILE_H / float(CardTileBack.TILE_HEIGHT)
	var x := 0.0
	for tid in _dora_indicators:
		var card := CardTileBack.new()
		card.position = Vector2(x, 0)
		card.scale = Vector2(sx, sy)
		_dora_row.add_child(card)
		card.set_face_up(int(tid))
		x += DORA_TILE_W + DORA_TILE_GAP
