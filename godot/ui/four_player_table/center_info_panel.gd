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
	_restyle_plate()
	_build_seat_sides()
	_label_riichi.visible = false
	_dora_row = Node2D.new()
	# 放在 panel 中心稍下，让"Dora:"label 上面，牌图在下面
	_dora_row.position = Vector2(-60, 30)
	add_child(_dora_row)
	# 立直棒已移至左上宝牌区；中央盘只保留本场棒视觉行。
	var vbox: VBoxContainer = $VBox
	if vbox:
		_honba_sticks_row = HBoxContainer.new()
		_honba_sticks_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_honba_sticks_row.add_theme_constant_override("separation", DT.GAP_TIGHT)
		vbox.add_child(_honba_sticks_row)
	_refresh_labels()
	_rebuild_dora_tiles()
	_rebuild_riichi_sticks()
	_rebuild_honba_sticks()

# ---- T3b 中心盘四方分数 + 立直指示灯(spec 2026-06-11 G3-b) ----
#
# 对标参考作 .center:220×220 圆角深蓝盘 + 金边;四边各家 风位+分数
# (全部正立文字,可读性优先于"面向各家"的旋转惯例);该家立直时其边
# 亮金条+发光红点(对标 .center-stick--on)。分数从 SeatPanel 移此处后,
# 桌面四角的黑板条即可瘦身(T3c)。

# 公开 bundle `.center` 的基础盒保持 220×220；透视与 CSS `scale(1.04)`
# 由 TableLayout 统一换算后施加到 CenterInfoPanel 节点，不污染基础盘尺寸。
const PLATE_HALF: float = 110.0

# 每边一组节点:{wind: Label, score: Label, stick: Control}
var _side_nodes: Array = []
# 最近一次 bind 的座位摘要(测试可注入):[{wind, score, riichi, active}]
var _seats_summary: Array = []

func _restyle_plate() -> void:
	# 深蓝盘严格使用 TableLayout 的桌面四角投影，不再以屏幕矩形冒充桌面物件。
	var bg := get_node_or_null("Bg")
	if bg:
		bg.visible = false
	var quad := TableLayout.center_plate()["local_quad"] as PackedVector2Array
	var shadow := Polygon2D.new()
	shadow.name = "CenterPlateShadow"
	shadow.polygon = TableLayout.offset_polygon(quad, Vector2(0, 5))
	shadow.color = Color(0, 0, 0, 0.48)
	add_child(shadow)
	var plate := Polygon2D.new()
	plate.name = "CenterPlate"
	plate.polygon = quad
	plate.color = Color(0.07, 0.09, 0.16, 0.96)
	add_child(plate)
	var border := Line2D.new()
	border.name = "CenterPlateBorder"
	border.points = PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]])
	border.width = 3.0
	border.default_color = Color(0.92, 0.78, 0.40, 0.65)
	border.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(border)
	move_child(shadow, 0)
	move_child(plate, 1)
	move_child(border, 2)
	var vbox := get_node_or_null("VBox") as Control
	if vbox:
		vbox.offset_left = -78
		vbox.offset_right = 78
		vbox.offset_top = -56
		vbox.offset_bottom = 60

func _build_seat_sides() -> void:
	_side_nodes = []
	# 布局对齐参考截图:四边各一个**风字章**(26×26 暗底圆角小章,
	# 旋转朝向各自玩家),当前回合家的章亮红底。分数不再显示在盘内。
	# [锚点(章中心), 旋转角(朝向该家)]
	var layouts: Array = [
		[Vector2(0, PLATE_HALF - 20), 0.0],
		[Vector2(PLATE_HALF - 20, 0), -90.0],
		[Vector2(0, -PLATE_HALF + 20), 180.0],
		[Vector2(-PLATE_HALF + 20, 0), 90.0],
	]
	for i in range(4):
		var anchor: Vector2 = layouts[i][0]
		var rot: float = layouts[i][1]
		var badge := Panel.new()
		badge.size = Vector2(26, 26)
		badge.position = anchor - Vector2(13, 13)
		badge.pivot_offset = Vector2(13, 13)
		badge.rotation_degrees = rot
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_stylebox_override("panel", _badge_style(false))
		add_child(badge)
		var lbl := Label.new()
		lbl.size = Vector2(26, 26)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.add_theme_color_override("font_color", Color(0.92, 0.90, 0.82))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(lbl)
		# 立直指示灯:金条 + 红点,declared 时亮(对标 center-stick--on)。
		var stick := _make_riichi_indicator()
		stick.pivot_offset = Vector2(21, 2.5)
		stick.position = anchor + anchor.normalized() * -20 + Vector2(-21, -2.5)
		stick.rotation_degrees = rot
		stick.visible = false
		add_child(stick)
		_side_nodes.append({"badge": badge, "label": lbl, "stick": stick})

static func _badge_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.72, 0.16, 0.14, 0.95) if active else Color(0.03, 0.05, 0.10, 0.8)
	sb.border_color = Color(0.85, 0.71, 0.36, 0.6 if active else 0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(5)
	return sb

static func _make_riichi_indicator() -> Control:
	var bar := ColorRect.new()
	bar.color = Color(0.95, 0.88, 0.66)
	bar.size = Vector2(42, 5)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := ColorRect.new()
	dot.color = Color(0.91, 0.31, 0.31)
	dot.size = Vector2(6, 5)
	dot.position = Vector2(18, 0)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(dot)
	return bar

var _turn_name: String = ""
var _turn_label: Label = null

# 当前回合家显示名(FourPlayerTable.bind 注入;"你"/AI persona 名)
func set_turn_name(name_: String) -> void:
	_turn_name = name_
	if is_inside_tree():
		_refresh_labels()


## #377：权威 phase 只读展示（与 turn 名并列）
var _public_phase: String = ""


func set_public_phase(phase: String) -> void:
	_public_phase = str(phase)
	if is_inside_tree():
		_refresh_labels()

func _ensure_turn_label() -> void:
	if _turn_label and is_instance_valid(_turn_label):
		return
	var vbox := get_node_or_null("VBox")
	if vbox == null:
		return
	_turn_label = Label.new()
	_turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_turn_label.add_theme_font_size_override("font_size", 13)
	_turn_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vbox.add_child(_turn_label)
	vbox.move_child(_turn_label, 1)  # 局数行之后

# 四方摘要注入(bind_state 内部调;测试可直接调)。
# seats_summary: [{wind: int, score: int, riichi: bool, active: bool}] × 4
func set_seats_summary(seats_summary: Array) -> void:
	_seats_summary = seats_summary
	if not is_inside_tree() or _side_nodes.is_empty():
		return
	for i in range(mini(4, seats_summary.size())):
		var info: Dictionary = seats_summary[i]
		var nodes: Dictionary = _side_nodes[i]
		(nodes.label as Label).text = SeatPanel.wind_name(int(info.get("wind", -1)))
		(nodes.stick as Control).visible = bool(info.get("riichi", false))
		# 当前回合家:风字章红底(对标参考截图)
		var active: bool = bool(info.get("active", false))
		(nodes.badge as Panel).add_theme_stylebox_override("panel", _badge_style(active))

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
	for ti in state.dora_indicators.visible_tiles():
		_dora_indicators.append(ti.id)
	# T3b:四方分数/风位/立直灯摘要
	var summary: Array = []
	for i in range(4):
		var seat: Seat = state.seats[i]
		# #375：权威分 BattleState.scores（Seat.points 可能漂移）
		var score_i: int = int(state.scores[i]) if i < state.scores.size() else seat.points
		summary.append({
			"wind": seat.seat_wind,
			"score": score_i,
			"riichi": seat.riichi.declared,
			"active": i == state.current_seat,
		})
	if is_inside_tree():
		_refresh_labels()
		_rebuild_dora_tiles()
		_rebuild_riichi_sticks()
		_apply_wall_pulse(prev_wall, _wall_remaining)
		set_seats_summary(summary)

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
	# dora 已移交左上 DoraWidget(对标参考截图),中心盘只留局数/余张/棒;
	# label/牌行保留更新(测试断言用)但不显示。
	_label_dora.visible = false
	if _dora_row:
		_dora_row.visible = false
	_label_wall.text = "余 %d 张" % _wall_remaining
	# 牌墙剩余分级配色:海底警戒(≤4 红) / 终盘(≤10 橙) / 中盘(≤30 黄) / 早盘(白)
	_label_wall.add_theme_color_override("font_color", wall_color(_wall_remaining))
	_label_riichi.text = "立直棒: %d" % _riichi_sticks
	# 当前回合家名(参考截图「北原 回合」行)
	_ensure_turn_label()
	if _turn_label:
		if _turn_name != "":
			_turn_label.text = "%s 回合" % _turn_name
		elif not _public_phase.is_empty():
			_turn_label.text = "阶段 %s" % _public_phase
		else:
			_turn_label.text = ""
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

# 立直棒行脉冲（桌上有棒时金光呼吸，强调"赢家可独吞"）
var _riichi_glow_tween: Tween = null


# 重建立直棒视觉行(N 根白底红点的迷你棒;N>STICK_MAX_SHOW 时尾部 "+N" 文字)。
func _rebuild_riichi_sticks() -> void:
	if _riichi_sticks_row == null:
		return
	for child in _riichi_sticks_row.get_children():
		child.queue_free()
	var shown: int = mini(_riichi_sticks, STICK_MAX_SHOW)
	for i in range(shown):
		_riichi_sticks_row.add_child(_make_riichi_stick(true))
	if _riichi_sticks > STICK_MAX_SHOW:
		var extra := Label.new()
		extra.text = "+%d" % (_riichi_sticks - STICK_MAX_SHOW)
		extra.add_theme_font_size_override("font_size", 11)
		extra.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		_riichi_sticks_row.add_child(extra)
	_apply_riichi_stick_glow(_riichi_sticks > 0)


# 测试用：当前视觉棒节点数（不含 "+N" 标签；跳过 queue_free 中的节点）
func count_riichi_stick_visuals() -> int:
	if _riichi_sticks_row == null:
		return 0
	var n := 0
	for child in _riichi_sticks_row.get_children():
		if child is Control and child.has_meta("riichi_stick") \
				and not child.is_queued_for_deletion():
			n += 1
	return n


func is_riichi_stick_glow_active() -> bool:
	return _riichi_glow_tween != null and _riichi_glow_tween.is_valid()


func _apply_riichi_stick_glow(on: bool) -> void:
	if _riichi_sticks_row == null:
		return
	if _riichi_glow_tween != null and _riichi_glow_tween.is_valid():
		_riichi_glow_tween.kill()
	_riichi_glow_tween = null
	_riichi_sticks_row.modulate = Color.WHITE
	if not on:
		return
	# 金白呼吸：alpha 1.0 ↔ 0.72，周期约 0.9s
	_riichi_glow_tween = create_tween().set_loops()
	_riichi_glow_tween.tween_property(_riichi_sticks_row, "modulate",
		Color(1.15, 1.05, 0.75, 1.0), 0.45).set_trans(Tween.TRANS_SINE)
	_riichi_glow_tween.tween_property(_riichi_sticks_row, "modulate",
		Color(1.0, 0.95, 0.8, 0.85), 0.45).set_trans(Tween.TRANS_SINE)


# 1 根迷你立直棒:骨白底 + 中央红点 + 可选金边外发光(桌上有棒时更醒目)。
static func _make_riichi_stick(with_glow: bool = false) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(STICK_W + 4, STICK_H + 4)
	wrap.size = Vector2(STICK_W + 4, STICK_H + 4)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.set_meta("riichi_stick", true)
	if with_glow:
		var glow := Panel.new()
		var gsb := StyleBoxFlat.new()
		gsb.bg_color = Color(0, 0, 0, 0)
		gsb.shadow_color = Color(1.0, 0.85, 0.35, 0.55)
		gsb.shadow_size = 6
		gsb.shadow_offset = Vector2.ZERO
		gsb.set_corner_radius_all(2)
		glow.add_theme_stylebox_override("panel", gsb)
		glow.position = Vector2(2, 2)
		glow.size = Vector2(STICK_W, STICK_H)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(glow)
	var stick := ColorRect.new()
	stick.color = Color(0.98, 0.95, 0.82)
	stick.position = Vector2(2, 2)
	stick.size = Vector2(STICK_W, STICK_H)
	stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(stick)
	var dot := ColorRect.new()
	dot.color = Color(0.90, 0.16, 0.16)
	dot.size = Vector2(8, STICK_H)
	dot.position = Vector2(2 + (STICK_W - 8) / 2.0, 2)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(dot)
	return wrap


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
	# T3b:按张数水平居中(_dora_row 挂在 (-60,30),补偿到盘中心)
	var total_w: float = _dora_indicators.size() * (DORA_TILE_W + DORA_TILE_GAP) - DORA_TILE_GAP
	var x: float = 60.0 - total_w / 2.0
	for tid in _dora_indicators:
		var card := CardTileBack.new()
		card.position = Vector2(x, 0)
		card.scale = Vector2(sx, sy)
		_dora_row.add_child(card)
		card.set_face_up(int(tid))
		x += DORA_TILE_W + DORA_TILE_GAP
