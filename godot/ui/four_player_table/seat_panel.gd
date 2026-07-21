class_name SeatPanel extends Node2D

# seat 0 (玩家) 自家手牌被点击时转发给上层（PlayerActionPanel / PlayableTable）。
# 其它 seat 永不 emit（手牌色块本身不 clickable）。
signal player_card_clicked(tile_id: int)
# 雀魂式：悬停手牌时通知桌面做全桌同名高亮
signal hand_tile_hover(tile_id: int, entered: bool)

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
@onready var _label_melds: Label = $Melds
@onready var _label_hand: Label = $Hand
@onready var _label_discards: Label = $Discards

# 手牌色块行：M3 收尾 — 13 个 (或 ≤13) 小 ColorRect 显示 owner_seat 着色，
# 实现 plan-3 D2/D5 归属可视化（看一家手牌区的"色块拼盘"知道牌从哪 4 家来）。
# 公开参考 CSS 的对手牌尺寸：上家是正向立牌背，左右家是窄侧视牌背。
const TOP_HAND_TILE_W: float = 38.0
const TOP_HAND_TILE_H: float = 55.0
# bundle Q3():axisA[0,-30],axisB[27.5,0],axisC[-15.21,32.63] 的外包围盒。
const SIDE_HAND_TILE_W: float = 46.71
const SIDE_HAND_TILE_H: float = 66.63
const SIDE_HAND_STACK_STEP: float = 32.0
const HAND_TILE_GAP: float = 4.0
const TOP_HAND_TILE_GAP: float = 3.0
const TOP_HAND_DRAWN_GAP: float = 22.0
const SIDE_HAND_TILE_GAP: float = 0.0
const CUBE_RAW_POINTS_META := &"reference_raw_points"
const SIDE_INFO_WIDTH: float = 170.0
const TOP_HAND_ROW_OFFSET_X: float = -265.0
const HAND_ROW_OFFSET_Y: float = 28.0
# 自家手牌直接对应参考 .tile--xl；13 张宽 882px，以 seat anchor 居中。
const PLAYER_HAND_TILE_W: float = 66.0
const PLAYER_HAND_TILE_H: float = 92.0
const PLAYER_HAND_ROW_OFFSET_X: float = -498.0
# 1600×900 下全局 y=700+78=778，底边 870，保留 30px 桌底间距。
const PLAYER_HAND_ROW_OFFSET_Y: float = 78.0
# 刚摸的牌与其他 13 张之间的间距（spec 2026-05-08 bug 2 fix；日麻 UI 标准）
const PLAYER_HAND_DRAWN_GAP: float = 24.0
const BOTTOM_NAME_COLUMN_SIZE := Vector2(200.0, 34.0)
const BOTTOM_SCORE_SIZE := Vector2(78.0, 21.0)
const PORTRAIT_BORDER_COLOR := Color("d9b65b66")
const PORTRAIT_ACTIVE_BORDER_COLOR := Color("ffd97a")
var _hand_tile_row: Node2D = null
# 发牌动画只读取当前真实 slot 的几何；玩家/对手共用，不生成静态猜测坐标。
var _deal_slots: Array[Control] = []
# 当前实际可见牌槽；摸牌后的第14槽属于视觉布局，但不属于4/4/4/1发牌目标。
var _visual_hand_slots: Array[Control] = []

# 玩家手牌当前是否接受点击（轮到玩家出牌时切 true）
var _hand_clickable: bool = false

var _seat_id: int = 0
var _seat_wind: int = TileId.E
var _score: int = 25000
# AI 性格化:替代默认"AI 1/2/3"用具体人物名+打法风格,让玩家从一眼看出
# 对面 3 家不是一团抽象的 AI,而是"赤木·激进 / 开司·速胡 / 鹫巢·防守"。
# seat_display_name 优先用 _persona_name (非空时);_persona_style 显示在
# seat_info 行做后缀(如 "赤木·东·激进")。
var _persona_name: String = ""
var _persona_style: String = ""
# AI 立绘:set_ai_persona 时设;_emote_state 控制 modulate 调色情绪。
# 1 张立绘 + 色调表达 4 种情绪,比录制台词便宜,比静态肖像有感染力。
const EMOTE_NORMAL: Color = Color(1, 1, 1, 1)            # 默认白
const EMOTE_RIICHI: Color = Color(0.6, 0.85, 1.0, 1.0)   # 蓝调:决意立直
const EMOTE_WINNING: Color = Color(1.3, 1.15, 0.7, 1.0)  # 金调:胡牌喜悦(略过曝)
const EMOTE_UPSET: Color = Color(0.5, 0.45, 0.45, 0.75)  # 灰调:被胡失落
var _portrait_rect: TextureRect = null
var _portrait_path: String = ""
# 气泡台词:say(text) 临时创建 Label 显示 1.5s 后淡出 queue_free。
# AI 在 RIICHI/WIN/被胡 时根据 persona_name 从台词池随机选一句,让 3 家
# AI 有"性格的声音"。比录配音便宜,比静态文字鲜活。
var _speech_label: Label = null

# 各 persona 的台词池。key = persona_name(set_ai_persona 时设),value =
# Dictionary{event → Array[String]}。无对应 persona 用 GENERIC fallback。
const SPEECH_POOL: Dictionary = {
	"凌夜": {
		"riichi": ["立直。", "看你怎么躲。", "无路可退了。"],
		"winning": ["自摸。", "如我所料。", "这就是差距。"],
		"upset": ["啧。", "下一把。", "意料之中。"],
	},
	"阿烈": {
		"riichi": ["立直——！", "全押了！", "命运的一手！"],
		"winning": ["胡了——！", "成功了!", "再赢一把!"],
		"upset": ["啊啊啊不!", "怎么会！", "再来再来！"],
	},
	"金老": {
		"riichi": ["立直。可笑。", "回响吧, 我的牌。", "看清了。"],
		"winning": ["和。", "不过尔尔。", "随便玩玩。"],
		"upset": ["哼。", "运气罢了。", "无趣。"],
	},
}
const SPEECH_GENERIC: Dictionary = {
	"riichi": ["立直！"],
	"winning": ["胡！"],
	"upset": ["唉。"],
}
var _hand_size: int = 13
var _hand_base_count: int = 13
var _hand_has_drawn: bool = false
var _meld_count: int = 0
var _discards_count: int = 0
var _riichi: bool = false
var _furiten: bool = false

# 听牌候补条（仅 seat 0）：小牌面横排显示 wait tiles
const WAIT_TILE_W: float = 28.0
const WAIT_TILE_H: float = 40.0
const WAIT_TILE_GAP: float = 3.0
var _wait_row: Node2D = null
var _wait_ids: Array = []  # Array[int]


func _ready() -> void:
	_apply_bottom_seat_label_layout()
	_hand_tile_row = Node2D.new()
	# 偏移在 _rebuild_*_row 之前会按 seat_id 调整（seat 0 用更宽的偏移给真实牌面留位）
	_hand_tile_row.position = Vector2(TOP_HAND_ROW_OFFSET_X, HAND_ROW_OFFSET_Y)
	add_child(_hand_tile_row)
	_wait_row = Node2D.new()
	_wait_row.name = "WaitRow"
	# 贴在自家手牌上方（PLAYER_HAND_ROW_OFFSET 上方约 48px）
	_wait_row.position = Vector2(PLAYER_HAND_ROW_OFFSET_X, PLAYER_HAND_ROW_OFFSET_Y - 48.0)
	_wait_row.visible = false
	add_child(_wait_row)
	_refresh_labels()


# 参考 .hand--top / .hand--left / .hand--right 的可观察尺寸。
static func opponent_hand_tile_size(seat_id: int) -> Vector2:
	if seat_id == 2:
		return Vector2(TOP_HAND_TILE_W, TOP_HAND_TILE_H)
	return Vector2(SIDE_HAND_TILE_W, SIDE_HAND_TILE_H)


static func _opponent_hand_layout_size(seat_id: int) -> Vector2:
	var screen_size := opponent_hand_tile_size(seat_id)
	if seat_id == 1 or seat_id == 3:
		return Vector2(screen_size.y, screen_size.x)
	return screen_size


static func _opponent_hand_gap(seat_id: int) -> float:
	return TOP_HAND_TILE_GAP if seat_id == 2 else SIDE_HAND_TILE_GAP

# 切换 seat 0 / 上家 / 左右家时，按各自真实牌宽居中 hand row。
func _apply_hand_row_offset() -> void:
	if _hand_tile_row == null:
		return
	if _seat_id == 0:
		_hand_tile_row.position = Vector2(PLAYER_HAND_ROW_OFFSET_X, PLAYER_HAND_ROW_OFFSET_Y)
	elif _seat_id == 2:
		_hand_tile_row.position = Vector2(TOP_HAND_ROW_OFFSET_X, HAND_ROW_OFFSET_Y)
	elif _seat_id == 1:
		# 13 个 cube 以 -32 本地步进；抵消整体旋转后在屏幕向下堆叠。
		_hand_tile_row.position = Vector2(
			(SIDE_HAND_STACK_STEP * 12.0 - SIDE_HAND_TILE_H) / 2.0,
			HAND_ROW_OFFSET_Y)
	else:
		_hand_tile_row.position = Vector2(
			-(SIDE_HAND_STACK_STEP * 12.0 + SIDE_HAND_TILE_H) / 2.0,
			HAND_ROW_OFFSET_Y)

# ---- public setters ----

func set_seat_id(id: int) -> void:
	assert(id >= 0 and id <= 3, "seat_id 必须 ∈ [0,3]")
	_seat_id = id
	rotation_degrees = SEAT_ROTATION_DEGREES[id]
	# T3c(spec 2026-06-11 G3-c):瘦身 — 240×100 板条隐藏,桌面让给牌;
	# 分数移中心盘;信息元素(文字/立绘/徽章/气泡)反向旋转保持正立,
	# 修掉"对面分数倒置 / 左右立绘横躺"的老问题。
	var bg := get_node_or_null("Bg") as ColorRect
	if bg:
		bg.visible = false
	# 对手仍沿用桌外信息列；自家在 _ready 后拆成参考 avatar-col + main。
	var vbox := get_node_or_null("VBox") as Control
	if vbox:
		if id == 1 or id == 3:
			vbox.size = Vector2(SIDE_INFO_WIDTH, vbox.size.y)
		_pin_info_node(vbox, _info_top_left(vbox.size.x, 92.0))
	_ensure_info_chip()
	if is_inside_tree():
		_apply_bottom_seat_label_layout()
		_refresh_labels()

# 侧家沿用的名字行底条；参考 bottom seat-label 没有这层胶囊。
func _ensure_info_chip() -> void:
	if _seat_id == 0:
		return
	if get_node_or_null("InfoChip") != null:
		return
	var chip := Panel.new()
	chip.name = "InfoChip"
	var chip_width := SIDE_INFO_WIDTH if _seat_id == 1 or _seat_id == 3 else 200.0
	var chip_height := 22.0 if _seat_id == 0 else 27.0
	chip.size = Vector2(chip_width, chip_height)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.05, 0.62)
	sb.border_color = Color(0.85, 0.71, 0.36, 0.28)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(13)
	chip.add_theme_stylebox_override("panel", sb)
	add_child(chip)
	_pin_info_node(chip, _info_top_left(chip_width, 89.0))
	# 垫在 VBox(文字)之下
	var vbox := get_node_or_null("VBox")
	if vbox:
		move_child(chip, vbox.get_index())


# 参考 bottom seat-label：avatar-col 内头像下方 3px 放分数，main 在右侧
# 5px；头像和手牌锚点保持 (322,644) / (302,778) 不变。
func _apply_bottom_seat_label_layout() -> void:
	if _seat_id != 0 or _label_score == null or _label_seat_info == null:
		return
	var vbox := get_node_or_null("VBox") as Control
	if vbox == null:
		return
	if _label_score.get_parent() != self:
		_label_score.reparent(self)
	vbox.size = BOTTOM_NAME_COLUMN_SIZE
	_pin_info_node(vbox, cluster_anchor() + Vector2(83.0, 34.0))
	_label_seat_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label_seat_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_seat_info.add_theme_font_size_override("font_size", 12)
	_label_score.size = BOTTOM_SCORE_SIZE
	_label_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pin_info_node(_label_score, cluster_anchor() + Vector2(0.0, 81.0))

# 把信息类 Control 绕自身中心反向旋转,抵消 SeatPanel 整体旋转 → 文字恒正立。
# 牌(手牌行/河/副露)不在此列 — 牌的旋转是方位语义,必须保留。
func _counter_rotate_info_node(node: Node) -> void:
	if node == null or not (node is Control) or not is_instance_valid(node):
		return
	var ctrl := node as Control
	ctrl.pivot_offset = ctrl.size / 2.0
	ctrl.rotation_degrees = -SEAT_ROTATION_DEGREES[_seat_id]

# ---- 头像卡群锚位(布局完全对齐参考截图) ----
#
# 每家的「头像卡 + 名字条 + 分数」按参考截图比例钉在**屏幕坐标**:
#   对面 = 其手牌右侧;左右家 = 手牌旁中部;自家 = 手牌左侧。
# SeatPanel 整体被旋转,信息件又反向旋转 — _pin_info_node 做坐标换算:
# 给定屏幕 top-left,反推出旋转空间里的 local position。
const CLUSTER_ANCHORS: Dictionary = {
	0: Vector2(322, 644),
	1: Vector2(1417, 370),
	2: Vector2(1110, 85),
	3: Vector2(105, 370),
}

func cluster_anchor() -> Vector2:
	return CLUSTER_ANCHORS.get(_seat_id, Vector2.ZERO)


# 自家压缩头像下信息的垂直间距；左右家信息条只向桌外展开。
func _info_top_left(width: float, offset_y: float) -> Vector2:
	var anchor := cluster_anchor()
	if _seat_id == 0:
		return anchor + Vector2(36.0 - width / 2.0, 78.0)
	if _seat_id == 1:
		return anchor + Vector2(0.0, offset_y)
	if _seat_id == 3:
		return anchor + Vector2(78.0 - width, offset_y)
	return anchor + Vector2(36.0 - width / 2.0, offset_y)

# 把 node 的**视觉 top-left** 钉到桌面屏幕坐标(node 同时被反向旋转恒正立)。
func _pin_info_node(node: Control, screen_top_left: Vector2) -> void:
	if node == null or not is_instance_valid(node):
		return
	var rot: float = deg_to_rad(SEAT_ROTATION_DEGREES[_seat_id])
	var center_screen: Vector2 = screen_top_left + node.size / 2.0
	node.position = (center_screen - position).rotated(-rot) - node.size / 2.0
	node.pivot_offset = node.size / 2.0
	node.rotation_degrees = -SEAT_ROTATION_DEGREES[_seat_id]

func set_seat_wind(wind_id: int) -> void:
	_seat_wind = wind_id
	if is_inside_tree():
		_refresh_labels()


# AI 性格化入口。four_player_table 在 _build_layout 给 seat 1/2/3 各调一次,
# 玩家 seat 0 可选(传角色名让玩家自己也"有名字")。
# portrait_path 为空时跳过立绘渲染;不为空时挂一个小肖像在分数框上方。
func set_ai_persona(name_: String, style: String, portrait_path: String = "") -> void:
	_persona_name = name_
	_persona_style = style
	_portrait_path = portrait_path
	if is_inside_tree():
		_refresh_labels()
		_ensure_portrait()


# AI 气泡台词:event_kind ∈ riichi/winning/upset,从 persona 池随机选一句
# 显示 1.5s 后淡出。无 persona/无文案 fallback 到 SPEECH_GENERIC。playable
# _table 在 RIICHI/WIN/被胡时调。
func say_for_event(event_kind: String) -> void:
	var pool: Dictionary = SPEECH_POOL.get(_persona_name, SPEECH_GENERIC)
	var lines: Array = pool.get(event_kind, [])
	if lines.is_empty():
		lines = SPEECH_GENERIC.get(event_kind, [])
	if lines.is_empty():
		return
	var text: String = String(lines[randi() % lines.size()])
	say(text)


# 直接说一句指定文字(供未来玩家选预设台词复用)。1.5s 淡出 queue_free。
# 重复调用:旧 label 先 fade 掉再创建新的,避免叠字。
func say(text: String) -> void:
	if text == "":
		return
	if _speech_label and is_instance_valid(_speech_label):
		_speech_label.queue_free()
	_speech_label = Label.new()
	_speech_label.text = text
	_speech_label.add_theme_font_size_override("font_size", 16)
	_speech_label.add_theme_color_override("font_color", DT.TEXT_TITLE)
	_speech_label.add_theme_constant_override("shadow_offset_x", 1)
	_speech_label.add_theme_constant_override("shadow_offset_y", 1)
	_speech_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_speech_label.size = Vector2(120, 30)
	_speech_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speech_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_speech_label)
	# 台词气泡钉在头像卡上方
	_pin_info_node(_speech_label, cluster_anchor() + Vector2(-24, -36))
	# fade in 0.15 → hold 1.2 → fade out 0.4 → free
	_speech_label.modulate.a = 0.0
	var captured := _speech_label
	var tw := create_tween()
	tw.tween_property(captured, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.2)
	tw.tween_property(captured, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		if is_instance_valid(captured):
			captured.queue_free())


# 切 AI 情绪 → 调 portrait modulate 色。RIICHI/WIN/被胡时由 playable_table 调用,
# 局间 reset_emote 回 normal。无立绘时本方法 no-op,不会崩。
func set_emote(emote: String) -> void:
	if _portrait_rect == null or not is_instance_valid(_portrait_rect):
		return
	var target: Color = EMOTE_NORMAL
	match emote:
		"riichi": target = EMOTE_RIICHI
		"winning": target = EMOTE_WINNING
		"upset": target = EMOTE_UPSET
		_: target = EMOTE_NORMAL
	# 用 tween 0.3s 过渡比硬切更顺眼
	var tw := create_tween()
	tw.tween_property(_portrait_rect, "modulate", target, 0.3)


# 当前立绘纹理(CallAnnounce 宣告演出取头像用);无立绘返 null。
func get_portrait_texture() -> Texture2D:
	if _portrait_rect and is_instance_valid(_portrait_rect):
		return _portrait_rect.texture
	return null


# 立绘节点懒创建。参考 seat-avatar 固定 78×78、cover 裁切、金软边。
# seat 0 玩家自家也可有立绘(玩家自定义角色),传 portrait_path 触发。
func _ensure_portrait() -> void:
	if _portrait_path == "":
		return
	if _portrait_rect and is_instance_valid(_portrait_rect):
		return
	if not ResourceLoader.exists(_portrait_path):
		return
	var tex: Texture2D = load(_portrait_path) as Texture2D
	if tex == null:
		return
	var anchor: Vector2 = cluster_anchor()
	_portrait_rect = TextureRect.new()
	_portrait_rect.texture = tex
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.size = Vector2(78, 78)
	_portrait_rect.clip_contents = true
	_portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait_rect)
	_pin_info_node(_portrait_rect, anchor)
	var border := Panel.new()
	border.name = "PortraitBorder"
	border.size = Vector2(78, 78)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color.TRANSPARENT
	border_style.border_color = PORTRAIT_ACTIVE_BORDER_COLOR \
		if _active else PORTRAIT_BORDER_COLOR
	border_style.set_border_width_all(2)
	border_style.set_corner_radius_all(6)
	border_style.shadow_color = Color(0, 0, 0, 0.35)
	border_style.shadow_size = 3
	border_style.shadow_offset = Vector2(0, 1)
	border.add_theme_stylebox_override("panel", border_style)
	add_child(border)
	_pin_info_node(border, anchor)

func set_score(s: int) -> void:
	var prev := _score
	_score = s
	if is_inside_tree():
		_refresh_labels()
		# 分数变化 → 0.55s 脉冲反馈:涨绿、跌红。第一次 bind 时 prev=0 不闪。
		if prev > 0 and s != prev and _label_score != null:
			_pulse_score(s > prev)
			# 商业级 game-feel:在 score label 上方飘 "+N" / "-N" 1.5s 渐隐
			_spawn_score_delta(s - prev)


func _pulse_score(positive: bool) -> void:
	if _score_pulse_tween and _score_pulse_tween.is_valid():
		_score_pulse_tween.kill()
	var flash: Color = DT.TEXT_SUCCESS if positive else DT.TEXT_DANGER
	var base: Color = DT.TEXT_PRIMARY
	_label_score.add_theme_color_override("font_color", flash)
	_score_pulse_tween = create_tween()
	_score_pulse_tween.tween_property(_label_score, "theme_override_colors/font_color",
		base, 0.55).set_ease(Tween.EASE_OUT)


# Score label 上方飘 "+5200" / "-1500" 文本 1.5s,边向上飞边渐隐。
# 给玩家一秒一瞥就知道这局赢/输多少的精确数字。
func _spawn_score_delta(delta: int) -> void:
	if _label_score == null or _label_score.get_parent() == null:
		return
	var lbl := Label.new()
	var sign_text: String = "+" if delta > 0 else ""  # 负数本身含 "-"
	lbl.text = "%s%d" % [sign_text, delta]
	lbl.add_theme_font_size_override("font_size", DT.FONT_SUBTITLE)
	var color: Color = DT.TEXT_SUCCESS if delta > 0 else DT.TEXT_DANGER
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.92))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 起始位置:score label 顶部上方 4px
	var sl_pos: Vector2 = _label_score.position
	var sl_size: Vector2 = _label_score.size
	var float_width := maxf(sl_size.x, 96.0)
	lbl.position = sl_pos + Vector2((sl_size.x - float_width) * 0.5, -34)
	lbl.size = Vector2(float_width, 32)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.z_index = 50
	_label_score.get_parent().add_child(lbl)
	# 向上飘 40px + 渐隐
	var tween := create_tween().set_parallel(true)
	tween.tween_property(lbl, "position", lbl.position + Vector2(0, -40), 1.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.5)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 等动画完了再 free
	get_tree().create_timer(1.55).timeout.connect(func():
		if is_instance_valid(lbl):
			lbl.queue_free())


var _score_pulse_tween: Tween = null

# 状态徽章:振听=红、听牌=金,小色块 + 单字 Label。挂在 seat 名旁。
# 这些走视觉(而非文字后缀)让玩家从 4 家快速扫描状态。
var _tenpai: bool = false
var _ippatsu: bool = false
var _badge_furiten: Control = null
var _badge_tenpai: Control = null
var _badge_ippatsu: Control = null

func set_tenpai(b: bool) -> void:
	_tenpai = b
	if is_inside_tree():
		_apply_status_badges()
		# 非听时清候补；听时重刷（可能已有 wait ids）
		if not b:
			set_wait_tiles([])
		else:
			_rebuild_wait_row()


# 听牌候补张（日麻 wait tiles）。仅 seat 0 渲染；空数组隐藏。
func set_wait_tiles(ids: Array) -> void:
	_wait_ids = ids.duplicate() if ids != null else []
	if is_inside_tree():
		_rebuild_wait_row()


func clear_wait_tiles() -> void:
	set_wait_tiles([])


func count_wait_tiles_shown() -> int:
	if _wait_row == null or not _wait_row.visible:
		return 0
	var n := 0
	for child in _wait_row.get_children():
		if child is CardTileBack and not child.is_queued_for_deletion():
			n += 1
	return n


func _rebuild_wait_row() -> void:
	if _wait_row == null:
		return
	for child in _wait_row.get_children():
		child.queue_free()
	# 仅自家、且确有候补时显示
	if _seat_id != 0 or _wait_ids.is_empty() or not _tenpai:
		_wait_row.visible = false
		return
	_wait_row.visible = true
	_wait_row.position = Vector2(PLAYER_HAND_ROW_OFFSET_X, PLAYER_HAND_ROW_OFFSET_Y - 48.0)
	# 「听」小标签
	var tag := Label.new()
	tag.text = "听"
	tag.position = Vector2(0, 8)
	tag.add_theme_font_size_override("font_size", 16)
	tag.add_theme_color_override("font_color", Color(1.0, 0.88, 0.40))
	tag.add_theme_constant_override("outline_size", 3)
	tag.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02, 0.9))
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wait_row.add_child(tag)
	var scale_x: float = WAIT_TILE_W / float(CardTileBack.TILE_WIDTH)
	var scale_y: float = WAIT_TILE_H / float(CardTileBack.TILE_HEIGHT)
	var x: float = 28.0
	for tid in _wait_ids:
		var tile := CardTileBack.new()
		tile.position = Vector2(x, 0)
		tile.scale = Vector2(scale_x, scale_y)
		_wait_row.add_child(tile)
		tile.set_face_up(int(tid), false)
		tile.set_clickable(false)
		x += WAIT_TILE_W + WAIT_TILE_GAP


func set_ippatsu(b: bool) -> void:
	_ippatsu = b
	if is_inside_tree():
		_apply_status_badges()


func _apply_status_badges() -> void:
	# 自家按参考 name-row 横排在名字列尾；对手保留头像右侧竖排。
	var anchor: Vector2 = cluster_anchor()
	var bottom_origin := Vector2(
		83.0 + BOTTOM_NAME_COLUMN_SIZE.x + 5.0,
		34.0 + (BOTTOM_NAME_COLUMN_SIZE.y - 20.0) * 0.5)
	var furiten_offset := bottom_origin if _seat_id == 0 else Vector2(78, 4)
	var tenpai_offset := bottom_origin + Vector2(32, 0) \
		if _seat_id == 0 else Vector2(78, 28)
	var ippatsu_offset := bottom_origin + Vector2(64, 0) \
		if _seat_id == 0 else Vector2(78, 52)
	_badge_furiten = _set_badge(_badge_furiten, _furiten, "振",
		Color(0.85, 0.18, 0.18), anchor + furiten_offset)
	# 听牌 — 仅玩家自家 seat 0 + 非立直时显示。
	var show_tenpai: bool = _tenpai and _seat_id == 0 and not _riichi
	_badge_tenpai = _set_badge(_badge_tenpai, show_tenpai, "听",
		DT.TEXT_TITLE, anchor + tenpai_offset)
	# 一発(刚立直未轮回一圈)— 青底,所有 seat 都显(玩家需要算别家一发风险)。
	_badge_ippatsu = _set_badge(_badge_ippatsu, _ippatsu, "発",
		Color(0.30, 0.70, 0.90), anchor + ippatsu_offset)


# 创建/销毁徽章。返回当前 badge node 实例(下次 _apply 复用判断)。
func _set_badge(existing: Control, visible_: bool, text: String, color: Color,
		pos: Vector2) -> Control:
	if not visible_:
		if existing != null and is_instance_valid(existing):
			existing.queue_free()
		return null
	if existing != null and is_instance_valid(existing):
		return existing
	var p := Panel.new()
	p.size = Vector2(28, 20)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	p.add_theme_stylebox_override("panel", sb)
	_pin_info_node(p, pos)  # 钉屏幕锚位 + 恒正立(pos 是屏幕 top-left)
	var lbl := Label.new()
	lbl.text = text
	lbl.size = Vector2(28, 20)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.05, 0.05, 0.05))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(lbl)
	add_child(p)
	return p

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


# 当前回合高亮：只增强参考 78×78 头像自身边框与名字颜色。
func set_active(b: bool) -> void:
	if _active == b:
		return
	_active = b
	if is_inside_tree():
		_apply_active_visual()


var _active: bool = false

func _apply_active_visual() -> void:
	# T3c:Bg 板条已隐藏 — 当前回合改为「头像自身金边 + 名字行金字」。
	# 中心盘四方分数也会同步金色(CenterInfoPanel.set_seats_summary)。
	if _label_seat_info:
		_label_seat_info.add_theme_color_override("font_color",
			DT.TEXT_TITLE if _active else Color(0.91, 0.88, 0.81))
	var border := get_node_or_null("PortraitBorder") as Panel
	if border == null:
		return
	var border_style := border.get_theme_stylebox("panel") as StyleBoxFlat
	if border_style != null:
		border_style.border_color = PORTRAIT_ACTIVE_BORDER_COLOR \
			if _active else PORTRAIT_BORDER_COLOR
		border.queue_redraw()

# 手牌色块归属可视化（M3 收尾）：传入 owners 数组（每张牌的 owner_seat），
# 重建 _hand_tile_row 子节点。owners.size() 也作为 hand_size 同步更新文字 Label。
func set_hand_tile_owners(owners: Array) -> void:
	_hand_size = owners.size()
	_hand_base_count = owners.size()
	_hand_has_drawn = false
	if is_inside_tree():
		_rebuild_hand_tile_row(owners)
		_refresh_labels()

# 胡牌结算前：强制显示该 seat 手牌正面（雀魂翻牌）
var _force_reveal_hand: bool = false
var _revealed_hand: Hand = null


# 一次注入 Seat 全部状态（含手牌色块归属）
# seat 0 时若传入 hand 则同时渲染真实 atlas 牌面（玩家自家可见），
# 其它 seat 仍用 owner 着色色块（对手牌不可见，符合规则）。
func bind_seat(seat: Seat) -> void:
	_seat_wind = seat.seat_wind
	_score = seat.points
	_hand_size = seat.hand.size()
	_hand_has_drawn = seat.last_drawn_tile_id >= 0 and seat.hand.size() > 0
	_hand_base_count = seat.hand.size() - 1 if _hand_has_drawn else seat.hand.size()
	_meld_count = seat.melds.size()
	_riichi = seat.riichi.declared
	_furiten = seat.furiten.is_furiten() if seat.furiten else false
	# discards 数量需外部传入（Seat 自身不持，BattleState.discards_per_seat[i] 持）
	if is_inside_tree():
		if _force_reveal_hand and _revealed_hand != null:
			_rebuild_revealed_hand_row(_revealed_hand)
		elif _seat_id == 0:
			# spec 2026-05-08 bug 2 fix：把刚摸的牌单独显示在最右
			_rebuild_player_hand_row_with_drawn(seat.hand, seat.last_drawn_tile_id)
		else:
			_rebuild_hand_tile_row(seat.hand.to_owner_array(),
				seat.last_drawn_tile_id >= 0)
		_refresh_labels()


# 雀魂式：结算前翻开对手手牌（face-up 小牌横排 + 错峰入场）
func reveal_hand_face_up(hand: Hand, animate: bool = true) -> void:
	_force_reveal_hand = true
	_revealed_hand = hand
	if not is_inside_tree() or hand == null:
		return
	_rebuild_revealed_hand_row(hand, animate)


func clear_hand_reveal() -> void:
	_force_reveal_hand = false
	_revealed_hand = null


func _rebuild_revealed_hand_row(hand: Hand, animate: bool = false) -> void:
	if _hand_tile_row == null or hand == null:
		return
	_apply_hand_row_offset()
	for child in _hand_tile_row.get_children():
		child.queue_free()
	_hand_slots.clear()
	_deal_slots.clear()
	_visual_hand_slots.clear()
	var ids: Array = hand.to_id_array()
	ids.sort()
	# 自家用大牌尺寸，对手用小牌（与日常手牌行一致）
	var opponent_size := opponent_hand_tile_size(_seat_id)
	var tw: float = PLAYER_HAND_TILE_W if _seat_id == 0 else opponent_size.x
	var th: float = PLAYER_HAND_TILE_H if _seat_id == 0 else opponent_size.y
	# 结算翻牌沿用既有对手 2px 间距；HAND_TILE_GAP 是自家参考行的 4px。
	var gap: float = 4.0 if _seat_id == 0 else 2.0
	var scale_x: float = tw / float(CardTileBack.TILE_WIDTH)
	var scale_y: float = th / float(CardTileBack.TILE_HEIGHT)
	var x := 0.0
	var i := 0
	for tid in ids:
		var is_red := false
		for t in hand._tiles:
			if t.id == int(tid) and t.is_red_dora:
				is_red = true
				break
		var tile := CardTileBack.new()
		tile.position = Vector2(x, 0)
		tile.scale = Vector2(scale_x, scale_y)
		_hand_tile_row.add_child(tile)
		tile.set_face_up(int(tid), is_red)
		tile.set_clickable(false)
		if animate and is_inside_tree():
			tile.modulate.a = 0.0
			tile.scale = Vector2(scale_x * 0.7, scale_y * 0.7)
			var twen := create_tween().set_parallel(true)
			twen.tween_property(tile, "modulate:a", 1.0, 0.18).set_delay(i * 0.04)
			twen.tween_property(tile, "scale", Vector2(scale_x, scale_y), 0.2)\
				.set_delay(i * 0.04).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		x += tw + gap
		i += 1


# 测试/调试：翻开后手牌正面张数
func count_revealed_face_up() -> int:
	if not _force_reveal_hand or _hand_tile_row == null:
		return 0
	var n := 0
	for child in _hand_tile_row.get_children():
		if child is CardTileBack:
			n += 1
	return n

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
	# 雀魂式简洁:名字·风(·庄 if dealer)·立直状态。
	# 振听 / 听牌 走单独彩色徽章(_apply_status_badges),不挤进 seat_info 文本。
	var status: String = ""
	if _seat_wind == TileId.E:
		status += " · 庄"
	if _riichi:
		status += " · 立直"
	# 优先用 persona_name (set_ai_persona 注入),fallback 到 "你"/"AI N"
	var who: String = _persona_name if _persona_name != "" else seat_display_name(_seat_id)
	var style_tag: String = " · %s" % _persona_style if _persona_style != "" else ""
	_label_seat_info.text = "%s · %s%s%s" % [who, wind_name(_seat_wind), status, style_tag]
	# 布局对齐:分数回到头像卡下(参考截图「50 分」位),金色
	_label_score.text = "%d 分" % _score
	_label_score.visible = true
	_label_score.add_theme_color_override("font_color", Color(0.94, 0.84, 0.42))
	_label_score.add_theme_font_size_override("font_size", 14 if _seat_id == 0 else 15)
	_apply_status_badges()
	# spec 2026-05-08 MeldArea：副露已用 MeldArea 视觉化，弃用文字 Label
	# 手牌张数 / 弃牌河张数也弃用：MeldArea + DiscardRiver 视觉自身已传达
	_label_melds.text = ""
	_label_melds.visible = false
	_label_hand.text = ""
	_label_hand.visible = false
	_label_discards.text = ""
	_label_discards.visible = false
	_apply_bottom_seat_label_layout()

# 对家手牌行：直接翻译参考 .hand--top / .hand--left / .hand--right 的尺寸。
func _rebuild_hand_tile_row(owners: Array, has_drawn: bool = false) -> void:
	if _hand_tile_row == null:
		return
	_apply_hand_row_offset()
	for child in _hand_tile_row.get_children():
		child.queue_free()
	_deal_slots.clear()
	_visual_hand_slots.clear()
	if _seat_id == 1 or _seat_id == 3:
		_rebuild_side_cube_hand(owners, has_drawn)
		return
	var has_visual_drawn := has_drawn and not owners.is_empty()
	var base_count := owners.size() - 1 if has_visual_drawn else owners.size()
	var screen_size := opponent_hand_tile_size(_seat_id)
	var layout_size := _opponent_hand_layout_size(_seat_id)
	var gap := _opponent_hand_gap(_seat_id)
	var back_tex: Texture2D = _resolve_back_texture()
	if owners.size() > 0:
		var row_w: float = owners.size() * layout_size.x + maxi(owners.size() - 1, 0) * gap
		_hand_tile_row.add_child(_make_row_shadow(Vector2(row_w + 8, layout_size.y + 4)))
	var x := 0.0
	for owner_index in range(owners.size()):
		var is_drawn := has_visual_drawn and owner_index == base_count
		if is_drawn and _seat_id == 2:
			# top row-reverse：13槽 raw union=530，摸牌另留22px视觉间距。
			x = base_count * TOP_HAND_TILE_W \
				+ maxi(base_count - 1, 0) * TOP_HAND_TILE_GAP \
				+ TOP_HAND_DRAWN_GAP
		var slot := Control.new()
		slot.name = "DealSlot"
		slot.position = Vector2(x, 0)
		slot.size = layout_size
		slot.custom_minimum_size = layout_size
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.set_meta("is_drawn", is_drawn)
		_hand_tile_row.add_child(slot)
		# 单牌投影
		var sh := Panel.new()
		var ssb := StyleBoxFlat.new()
		ssb.bg_color = Color(0, 0, 0, 0)
		ssb.shadow_color = Color(0, 0, 0, 0.40)
		ssb.shadow_size = 5
		ssb.shadow_offset = _opponent_shadow_offset(_seat_id)
		sh.add_theme_stylebox_override("panel", ssb)
		sh.position = Vector2(-1, 2)
		sh.size = Vector2(layout_size.x + 2, layout_size.y)
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(sh)
		var rect := TextureRect.new()
		rect.name = "Back"
		rect.position = (layout_size - screen_size) / 2.0
		rect.size = screen_size
		rect.pivot_offset = screen_size / 2.0
		# 抵消 SeatPanel 方位旋转，让烘焙在贴图顶部的白棱始终朝屏幕上方。
		rect.rotation_degrees = -SEAT_ROTATION_DEGREES[_seat_id]
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if back_tex != null:
			rect.texture = back_tex
			rect.modulate = Color.WHITE
		else:
			rect.modulate = Color(0.15, 0.35, 0.22)
		slot.add_child(rect)
		_visual_hand_slots.append(slot)
		if not is_drawn:
			_deal_slots.append(slot)
		x += layout_size.x + gap


# 正常左右家直接翻译 bundle q0 → aw 的 SVG 立方体堆叠。SeatPanel 自身仍按
# 方位旋转，单个 CubeVisual 反向旋转保持屏幕正立；左家再做 scaleX(-1)。
func _rebuild_side_cube_hand(owners: Array, has_drawn: bool) -> void:
	var has_visual_drawn := has_drawn and not owners.is_empty()
	var base_count := owners.size() - 1 if has_visual_drawn \
		else owners.size()
	var slot_count := base_count + 1
	var host_height := SIDE_HAND_TILE_H \
		+ (slot_count - 1) * SIDE_HAND_STACK_STEP + 12.0
	_hand_tile_row.set_meta("r3d_host_size", Vector2(SIDE_HAND_TILE_W, host_height))
	# q0 host 在 seat body 中居中；左右 CSS 都另向桌内 translateX(15px)。
	_hand_tile_row.position = Vector2(
		host_height / 2.0 if _seat_id == 1 else -host_height / 2.0,
		13.0)
	var layout_size := Vector2(SIDE_HAND_TILE_H, SIDE_HAND_TILE_W)
	# 右家把摸牌预留在 index 0；左家把预留放在最后并由外层镜像。
	if has_visual_drawn and _seat_id == 1:
		_add_side_cube_slot(layout_size, 0.0, 0, true, true, false, true, -1)
	for i in range(base_count):
		var host_index := i + 1 if _seat_id == 1 else i
		var host_y := host_index * SIDE_HAND_STACK_STEP
		if _seat_id == 1:
			host_y += 12.0
		_add_side_cube_slot(layout_size, host_y, host_index,
			i == 0, i == base_count - 1, true, false, i)
	if has_visual_drawn and _seat_id == 3:
		var drawn_y := base_count * SIDE_HAND_STACK_STEP + 12.0
		_add_side_cube_slot(layout_size, drawn_y, base_count, true, true, false,
			true, base_count)


func _add_side_cube_slot(layout_size: Vector2, host_y: float, stack_index: int,
		is_top: bool, is_bottom: bool, is_deal_slot: bool,
		is_drawn: bool = false, reference_slot_index: int = -1) -> void:
	var slot := Control.new()
	slot.name = "DealSlot"
	slot.position = Vector2(-host_y if _seat_id == 1 else host_y, 0)
	slot.size = layout_size
	slot.custom_minimum_size = layout_size
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.z_index = stack_index
	slot.set_meta("is_drawn", is_drawn)
	slot.set_meta("reference_slot_index", reference_slot_index)
	_hand_tile_row.add_child(slot)
	var cube := make_reference_side_cube(_seat_id == 3, is_top, is_bottom)
	cube.position = (layout_size - cube.size) / 2.0
	cube.pivot_offset = cube.size / 2.0
	cube.rotation_degrees = -SEAT_ROTATION_DEGREES[_seat_id]
	slot.add_child(cube)
	_visual_hand_slots.append(slot)
	if is_deal_slot:
		_deal_slots.append(slot)


static func make_reference_side_cube(mirror_x: bool = false,
		is_top: bool = false, is_bottom: bool = false) -> Control:
	var cube := Control.new()
	cube.name = "CubeVisual"
	cube.size = Vector2(SIDE_HAND_TILE_W, SIDE_HAND_TILE_H)
	cube.custom_minimum_size = cube.size
	cube.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cube.pivot_offset = cube.size / 2.0
	cube.scale.x = -1.0 if mirror_x else 1.0
	cube.set_meta("is_top", is_top)
	cube.set_meta("is_bottom", is_bottom)
	# aw() 将所有 axis 点平移到 Q3() 的 2px 外边距内。
	var o := Vector2(17.21, 32.0)
	var a := Vector2(17.21, 2.0)
	var ab := Vector2(44.71, 2.0)
	var b := Vector2(44.71, 32.0)
	var bc := Vector2(29.50, 64.63)
	var c := Vector2(2.0, 64.63)
	var ac := Vector2(2.0, 34.63)
	var corner_radius := 6.0 if is_bottom else 0.0
	var back_points := _rounded_cube_polygon([a, o, c, ac],
		[0.0, 0.0, corner_radius, 0.0])
	var top_points := _rounded_cube_polygon([a, ab, b, o],
		[0.0, 6.0, 0.0, 0.0])
	var side_points := _rounded_cube_polygon([b, bc, c, o],
		[0.0, 6.0, corner_radius, 0.0])
	# aw(): 接触影允许越过 46.71×66.63 viewBox，等价 SVG overflow:visible。
	_add_cube_gradient_face(cube, "ContactLeft",
		[ac, ac + Vector2(-6, 0), c + Vector2(-6, 0), c],
		[Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.0)], [0.0, 1.0],
		c, c + Vector2(-6, 0), Rect2(Vector2(-4, 34.63), Vector2(6, 30)))
	if is_bottom:
		_add_cube_gradient_face(cube, "ContactBottom",
			[c, bc, bc + Vector2(0, 6), c + Vector2(0, 6)],
			[Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.0)], [0.0, 1.0],
			c, c + Vector2(0, 6), Rect2(c, Vector2(bc.x - c.x, 6)))
	_add_cube_hard_split_face(cube, "CubeTop", top_points, o, b)
	_add_cube_face(cube, "CubeBack", back_points, Color("2c5e3f"))
	_add_cube_hard_split_face(cube, "CubeSide", side_points, o,
		Vector2(39.801309, 42.530610))
	_add_cube_gradient_face(cube, "CubeSideShadow", side_points,
		[Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.7)],
		[0.0, 0.3, 1.0], o, c)
	if not is_top:
		_add_cube_stack_seam(cube, a, ab, ac)
	_add_cube_outline_and_bevels(cube, o, a, ab, b, bc, c, ac,
		is_top, is_bottom, corner_radius)
	return cube


static func _add_cube_face(parent: Control, node_name: String,
		points: Array, color: Color) -> void:
	var face := Polygon2D.new()
	face.name = node_name
	var raw_points := PackedVector2Array(points)
	face.polygon = raw_points
	face.set_meta(CUBE_RAW_POINTS_META, raw_points)
	face.color = color
	face.antialiased = true
	parent.add_child(face)


# 参考 SVG 的 49.9/50.1 渐变是视觉硬分色。Polygon2D 在逐点透视后若继续
# 依赖 UV，会按三角形分别插值，分界就会折成梯形；这里改为共享 50% 边的
# 绿底 + 白色裁切面，等价保留 bundle 的硬分色语义。
static func _add_cube_hard_split_face(parent: Control, node_name: String,
		points: Array, fill_from: Vector2, fill_to: Vector2) -> void:
	_add_cube_face(parent, node_name, points, Color("2c5e3f"))
	var white_points := _clip_polygon_after_gradient(
		points, fill_from, fill_to, 0.5)
	_add_cube_face(parent, node_name + "White", white_points, Color.WHITE)


static func _clip_polygon_after_gradient(points: Array, fill_from: Vector2,
		fill_to: Vector2, threshold: float) -> Array:
	var result: Array = []
	if points.is_empty():
		return result
	var axis := fill_to - fill_from
	var axis_length_squared := axis.length_squared()
	for index in range(points.size()):
		var current: Vector2 = points[index]
		var following: Vector2 = points[(index + 1) % points.size()]
		var current_t := (current - fill_from).dot(axis) / axis_length_squared
		var following_t := (following - fill_from).dot(axis) / axis_length_squared
		var current_inside := current_t >= threshold
		var following_inside := following_t >= threshold
		if current_inside:
			_append_unique_polygon_point(result, current)
		if current_inside != following_inside:
			var ratio := (threshold - current_t) / (following_t - current_t)
			_append_unique_polygon_point(result, current.lerp(following, ratio))
	if result.size() > 1 \
			and (result[0] as Vector2).distance_to(result[-1] as Vector2) <= 0.001:
		result.pop_back()
	return result


static func _append_unique_polygon_point(points: Array, point: Vector2) -> void:
	if points.is_empty() or (points[-1] as Vector2).distance_to(point) > 0.001:
		points.append(point)


# bundle 的 rounded polygon helper：每个顶点按相邻边各退/进 radius，再以顶点作
# quadratic control point。SVG 用连续 Q；Godot Polygon2D 用 4 段采样同一曲线。
static func _rounded_cube_polygon(points: Array, radii: Array) -> Array:
	var corners: Array = []
	for i in range(points.size()):
		var previous: Vector2 = points[(i - 1 + points.size()) % points.size()]
		var current: Vector2 = points[i]
		var following: Vector2 = points[(i + 1) % points.size()]
		var incoming := current - previous
		var outgoing := following - current
		var radius := minf(float(radii[i]),
			minf(incoming.length() / 2.0, outgoing.length() / 2.0))
		corners.append({
			"start": current - incoming.normalized() * radius,
			"corner": current,
			"end": current + outgoing.normalized() * radius,
		})
	var result: Array = []
	_append_unique_polygon_point(result, corners[0]["start"])
	for i in range(corners.size()):
		var item: Dictionary = corners[i]
		for step in range(1, 5):
			var t := float(step) / 4.0
			var inv := 1.0 - t
			_append_unique_polygon_point(result, inv * inv * item["start"] \
				+ 2.0 * inv * t * item["corner"] + t * t * item["end"])
		var next_start: Vector2 = corners[(i + 1) % corners.size()]["start"]
		if i < corners.size() - 1:
			_append_unique_polygon_point(result, next_start)
	return result


static func _add_cube_gradient_face(parent: Control, node_name: String,
		points: Array, colors: Array, offsets: Array, fill_from: Vector2,
		fill_to: Vector2, texture_rect: Rect2 = Rect2()) -> void:
	if texture_rect.size == Vector2.ZERO:
		texture_rect = Rect2(Vector2.ZERO, Vector2(SIDE_HAND_TILE_W, SIDE_HAND_TILE_H))
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array(offsets)
	gradient.colors = PackedColorArray(colors)
	var texture := GradientTexture2D.new()
	texture.width = maxi(1, ceili(texture_rect.size.x))
	texture.height = maxi(1, ceili(texture_rect.size.y))
	texture.fill_from = (fill_from - texture_rect.position) / texture_rect.size
	texture.fill_to = (fill_to - texture_rect.position) / texture_rect.size
	texture.gradient = gradient
	var face := Polygon2D.new()
	face.name = node_name
	var raw_points := PackedVector2Array(points)
	face.polygon = raw_points
	face.set_meta(CUBE_RAW_POINTS_META, raw_points)
	var uv_points: Array = []
	var texture_size := Vector2(texture.width, texture.height)
	for point in points:
		uv_points.append(((point as Vector2) - texture_rect.position)
			/ texture_rect.size * texture_size)
	face.uv = PackedVector2Array(uv_points)
	face.texture = texture
	face.color = Color.WHITE
	face.antialiased = true
	parent.add_child(face)


static func _cube_outward_normal(direction: Vector2) -> Vector2:
	var candidate := Vector2(direction.y, -direction.x)
	if candidate.y < 0:
		return candidate
	return -candidate


static func _add_cube_stack_seam(parent: Control, a: Vector2, ab: Vector2,
		ac: Vector2) -> void:
	var left_dir := (a - ac).normalized()
	var right_dir := (ab - a).normalized()
	var left_normal := _cube_outward_normal(left_dir)
	var right_normal := _cube_outward_normal(right_dir)
	var gap := 2.0
	var left_outer := ac + left_normal * gap
	var right_outer := ab + right_normal * gap
	var summed := left_normal + right_normal
	var corner_normal := summed.normalized()
	var divisor := left_normal.dot(corner_normal)
	var corner_outer := a + corner_normal * gap / divisor
	_add_cube_face(parent, "StackSeam",
		[left_outer, corner_outer, right_outer, ab, a, ac],
		Color(12.0 / 255.0, 35.0 / 255.0, 22.0 / 255.0, 0.5))
	_add_cube_gradient_face(parent, "SeamShadow",
		[ac, a, ab, ab + Vector2(0, 1.5), a + Vector2(0, 1.5),
			ac + Vector2(0, 1.5)],
		[Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.0)], [0.0, 1.0],
		a, a + Vector2(0, 1.5))


static func _add_cube_line(parent: Control, node_name: String, points: Array,
		color: Color, width: float, closed: bool = false) -> void:
	var line := Line2D.new()
	line.name = node_name
	var raw_points := PackedVector2Array(points)
	line.points = raw_points
	line.set_meta(CUBE_RAW_POINTS_META, raw_points)
	line.default_color = color
	line.width = width
	line.closed = closed
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.antialiased = true
	parent.add_child(line)


static func _quadratic_segment(start: Vector2, control: Vector2,
		end: Vector2) -> Array:
	var points: Array = []
	for step in range(1, 5):
		var t := float(step) / 4.0
		var inv := 1.0 - t
		points.append(inv * inv * start + 2.0 * inv * t * control + t * t * end)
	return points


static func _add_cube_outline_and_bevels(parent: Control, o: Vector2, a: Vector2,
		ab: Vector2, b: Vector2, bc: Vector2, c: Vector2, ac: Vector2,
		is_top: bool, is_bottom: bool, corner_radius: float) -> void:
	var outline_color := Color(12.0 / 255.0, 35.0 / 255.0, 22.0 / 255.0, 0.32)
	var edge_color := Color(12.0 / 255.0, 35.0 / 255.0, 22.0 / 255.0, 0.28)
	_add_cube_line(parent, "CubeOutline",
		[a, ab, b, bc, c, ac] if is_top else [ab, b, bc, c, ac],
		outline_color, 0.7, is_top)
	var axis_a := Vector2(0, -30).normalized()
	var axis_b := Vector2(27.5, 0).normalized()
	var axis_c := Vector2(-15.21, 32.63).normalized()
	var inset := 1.8
	var a_normal := Vector2(axis_a.y, -axis_a.x)
	var bevel_a_points := [o + a_normal * inset, a + a_normal * inset]
	var bevel_a_color := Color(1.0, 245.0 / 255.0, 215.0 / 255.0, 0.15)
	if not is_bottom:
		_add_cube_line(parent, "EdgeMV0", [a, o], edge_color, 0.5)
		_add_cube_line(parent, "BevelA", bevel_a_points, bevel_a_color, 0.9)
		return
	var trim := 4.0
	var along_a := o + axis_a * trim
	var along_b := o + axis_b * trim
	var along_c := o + axis_c * trim
	var c_end := c - axis_c * corner_radius
	var edge_ab: Array = [a, along_a]
	edge_ab.append_array(_quadratic_segment(along_a, o, along_b))
	edge_ab.append(b)
	var edge_bc: Array = [b, along_b]
	edge_bc.append_array(_quadratic_segment(along_b, o, along_c))
	edge_bc.append(c_end)
	var edge_ca: Array = [c_end, along_c]
	edge_ca.append_array(_quadratic_segment(along_c, o, along_a))
	edge_ca.append(a)
	_add_cube_line(parent, "EdgeAB", edge_ab, edge_color, 0.5)
	_add_cube_line(parent, "EdgeBC", edge_bc, edge_color, 0.5)
	_add_cube_line(parent, "EdgeCA", edge_ca, edge_color, 0.5)
	_add_cube_line(parent, "BevelA", bevel_a_points, bevel_a_color, 0.9)
	var b_normal := Vector2(axis_b.y, -axis_b.x)
	_add_cube_line(parent, "BevelB", [along_b + b_normal * inset, b + b_normal * inset],
		Color(1.0, 245.0 / 255.0, 215.0 / 255.0, 0.15), 0.9)
	var c_normal := Vector2(-axis_c.y, axis_c.x)
	_add_cube_line(parent, "BevelC", [along_c + c_normal * inset,
		c_end + c_normal * inset],
		Color(1.0, 245.0 / 255.0, 215.0 / 255.0, 0.7), 0.9)


static func _opponent_shadow_offset(seat_id: int) -> Vector2:
	match seat_id:
		1: return Vector2(-4, 6) # .hand--right
		3: return Vector2(4, 6)  # .hand--left
	return Vector2(0, 4)      # .hand--top

# 取牌背图（autoload TextureExtractor）。autoload 不在或缺图时返 null。
# T3d:对手手牌优先用「站立牌」贴图(bake_standing_back.py),视角语义正确;
# 缺图 fallback 到平面 back.png。
# 对面(seat 2)看到的是牌背(绿背+白棱);左右家(seat 1/3)看到的是
# 牌的侧面体块(白厚身+绿顶,绿顶朝桌心)— 参考截图确认的真实立牌视角。
const STANDING_BACK_PATH := "res://assets/tile_back_standing.png"

func _resolve_back_texture() -> Texture2D:
	var path: String = STANDING_BACK_PATH
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path) as Texture2D
		if tex != null:
			return tex
	if not is_inside_tree():
		return null
	var extractor: Node = get_tree().root.get_node_or_null("TextureExtractor")
	if extractor == null or not extractor.has_method("get_tile_texture"):
		return null
	return extractor.get_tile_texture("back")

# 玩家手牌（seat 0）真实 atlas 渲染：CardTileBack.set_face_up + 缩放到 66×92。
# 复用 CardTileBack 是为了一致样式（边框、modulate=WHITE、tile_id_to_atlas_key
# 映射），不用为玩家手牌再造一个 TextureRect 包装。
func _rebuild_player_hand_row(tile_ids: Array) -> void:
	# 兼容旧 caller（无 drawn 信息）：全部按一行渲染，无分隔
	_rebuild_player_hand_row_internal(tile_ids, [], [], [])

# spec 2026-05-08 bug 2 fix：把刚摸的牌单独显示在最右（与其他 13 张间留 PLAYER_HAND_DRAWN_GAP 间距）
# hand：当前手牌 Hand；drawn_tile_id：刚摸的牌 id（-1 = 不在 post-draw 状态，全 sorted 渲染）
# 算法：
#   - drawn_tile_id < 0：全部 sorted 渲染（同 _rebuild_player_hand_row 旧行为）
#   - drawn_tile_id >= 0：从 hand 中 pop 1 张匹配 id 的牌作"刚摸"；剩下 sorted；
#     渲染顺序 = sorted 13 张 + 间距 + 1 张刚摸的牌（最右）
func _rebuild_player_hand_row_with_drawn(hand: Hand, drawn_tile_id: int) -> void:
	var split: Dictionary = split_hand_for_display(hand, drawn_tile_id)
	_rebuild_player_hand_row_internal(
		split.sorted_ids, split.drawn_ids,
		split.get("sorted_reds", []), split.get("drawn_reds", []))

# spec 2026-05-08 bug 2 fix：把"hand + 刚摸的牌 id"拆成 sorted + drawn 两部分。
# 提为 static func 便于 GUT 单测（不依赖 SceneTree / TextureExtractor）。
# 算法：
#   drawn_tile_id < 0 / 不在手牌内 → 全 sorted（13 张），drawn_ids = []
#   drawn_tile_id 在手牌内 → 从手牌弹 1 张匹配 drawn 的；剩下升序 sort；
#     返 {sorted_ids: [13 张升序], drawn_ids: [drawn_id]}
# 注意：手牌中可能含多张同 drawn id（如刚摸的牌恰好凑成 pair/triplet）；本函数
# 仅 pop 第 1 张，保留其余按 sorted 渲染。这与日麻 UI 实现一致：刚摸的牌物理
# 上是末尾插入的那张，UI 显示在右侧。
static func split_hand_for_display(hand: Hand, drawn_tile_id: int) -> Dictionary:
	# 返回 ids 与平行 is_red_dora 数组，保证赤宝真图接线不丢标记。
	# 摸牌分离：从末尾往前找 drawn id（刚摸的通常是最后插入的那张）。
	var entries: Array = []  # Array[{id, red}]
	for t in hand._tiles:
		entries.append({"id": t.id, "red": t.is_red_dora})
	if drawn_tile_id < 0:
		entries.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
		return _split_entries_to_dict(entries, [])
	var drawn_idx: int = -1
	for i in range(entries.size() - 1, -1, -1):
		if int(entries[i]["id"]) == drawn_tile_id:
			drawn_idx = i
			break
	if drawn_idx < 0:
		entries.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
		return _split_entries_to_dict(entries, [])
	var drawn_entry: Dictionary = entries[drawn_idx]
	entries.remove_at(drawn_idx)
	entries.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	return _split_entries_to_dict(entries, [drawn_entry])


static func _split_entries_to_dict(sorted_entries: Array, drawn_entries: Array) -> Dictionary:
	var sorted_ids: Array = []
	var sorted_reds: Array = []
	for e in sorted_entries:
		sorted_ids.append(int(e["id"]))
		sorted_reds.append(bool(e["red"]))
	var drawn_ids: Array = []
	var drawn_reds: Array = []
	for e in drawn_entries:
		drawn_ids.append(int(e["id"]))
		drawn_reds.append(bool(e["red"]))
	return {
		"sorted_ids": sorted_ids,
		"drawn_ids": drawn_ids,
		"sorted_reds": sorted_reds,
		"drawn_reds": drawn_reds,
	}


# 手牌增量匹配（纯函数，可单测）。
# prev/next: Array[{id:int, red:bool}]
# 返回 Array[int]，与 next 等长：reuse 的 prev 下标，或 -1 表示新建。
# 匹配键严格为 (id, red)；每个 prev 槽最多用一次。
static func assign_hand_reuse(prev: Array, next: Array) -> Array:
	var used: Dictionary = {}
	var assignments: Array = []
	for n in next:
		var nid: int = int(n.get("id", -1))
		var nred: bool = bool(n.get("red", false))
		var found: int = -1
		for pi in range(prev.size()):
			if used.has(pi):
				continue
			var p: Dictionary = prev[pi]
			if int(p.get("id", -2)) == nid and bool(p.get("red", false)) == nred:
				found = pi
				break
		if found >= 0:
			used[found] = true
		assignments.append(found)
	return assignments

# 整行投影 helper(质感层):透明底 + 仅 shadow 的 Panel 垫在行底。
static func _make_row_shadow(size_: Vector2) -> Panel:
	var p := Panel.new()
	p.position = Vector2.ZERO
	p.size = size_
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 4)
	p.add_theme_stylebox_override("panel", sb)
	return p


# 手牌槽：每张牌一个 Control 容器（棱 + CardTileBack），便于增量 reuse。
# meta: hand_id, hand_red, is_drawn
var _hand_slots: Array = []  # Array[Control]


# 内部统一渲染：sorted 在左，drawn 在右；增量 reuse 同 (id,red) 节点，避免整行闪。
func _rebuild_player_hand_row_internal(sorted_ids: Array, drawn_ids: Array,
		sorted_reds: Array = [], drawn_reds: Array = []) -> void:
	if _hand_tile_row == null:
		return
	_apply_hand_row_offset()
	var targets: Array = []
	for i in range(sorted_ids.size()):
		targets.append({
			"id": int(sorted_ids[i]),
			"red": i < sorted_reds.size() and bool(sorted_reds[i]),
			"drawn": false,
		})
	for i in range(drawn_ids.size()):
		targets.append({
			"id": int(drawn_ids[i]),
			"red": i < drawn_reds.size() and bool(drawn_reds[i]),
			"drawn": true,
		})
	_sync_player_hand_slots(targets)


func _sync_player_hand_slots(targets: Array) -> void:
	# 清掉旧 shadow（每次按总宽重建）
	for child in _hand_tile_row.get_children():
		if child is Panel and child.name == "HandRowShadow":
			child.queue_free()

	var prev_meta: Array = []
	for slot in _hand_slots:
		if slot == null or not is_instance_valid(slot):
			prev_meta.append({"id": -999, "red": false})
			continue
		prev_meta.append({
			"id": int(slot.get_meta("hand_id", -1)),
			"red": bool(slot.get_meta("hand_red", false)),
		})
	var assignments: Array = assign_hand_reuse(prev_meta, targets)
	var reused_prev: Dictionary = {}
	var new_slots: Array = []
	var scale_x: float = PLAYER_HAND_TILE_W / float(CardTileBack.TILE_WIDTH)
	var scale_y: float = PLAYER_HAND_TILE_H / float(CardTileBack.TILE_HEIGHT)

	for ti in range(targets.size()):
		var t: Dictionary = targets[ti]
		var prev_i: int = int(assignments[ti])
		var slot: Control = null
		var is_new: bool = false
		if prev_i >= 0 and prev_i < _hand_slots.size():
			var cand: Control = _hand_slots[prev_i]
			if cand != null and is_instance_valid(cand) and not reused_prev.has(prev_i):
				slot = cand
				reused_prev[prev_i] = true
		if slot == null:
			slot = _make_hand_slot(int(t["id"]), bool(t["red"]), scale_x, scale_y)
			is_new = true
		else:
			_refresh_hand_slot(slot, int(t["id"]), bool(t["red"]))
		slot.set_meta("is_drawn", bool(t["drawn"]))
		new_slots.append({"slot": slot, "drawn": bool(t["drawn"]), "is_new": is_new})

	# 释放未 reuse 的旧槽
	for pi in range(_hand_slots.size()):
		if reused_prev.has(pi):
			continue
		var dead: Control = _hand_slots[pi]
		if dead != null and is_instance_valid(dead):
			dead.queue_free()

	var n_sorted: int = 0
	for item in new_slots:
		if not bool(item["drawn"]):
			n_sorted += 1

	_hand_slots.clear()
	var x := 0.0
	var seen_drawn := false
	for item in new_slots:
		var slot2: Control = item["slot"]
		if bool(item["drawn"]) and not seen_drawn:
			if n_sorted > 0:
				x += PLAYER_HAND_DRAWN_GAP - HAND_TILE_GAP
			seen_drawn = true
		var target_pos := Vector2(x, 0)
		if not slot2.get_parent():
			_hand_tile_row.add_child(slot2)
		if bool(item["is_new"]) and bool(item["drawn"]) and is_inside_tree():
			slot2.position = Vector2(x, -28)
			slot2.modulate.a = 0.0
			var tw := create_tween().set_parallel(true)
			tw.tween_property(slot2, "position", target_pos, 0.18)\
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_property(slot2, "modulate:a", 1.0, 0.16)
		elif is_inside_tree() and slot2.position.distance_to(target_pos) > 0.5:
			slot2.modulate.a = 1.0
			var tw2 := create_tween()
			tw2.tween_property(slot2, "position", target_pos, 0.12)\
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		else:
			slot2.position = target_pos
			slot2.modulate.a = 1.0
		_hand_slots.append(slot2)
		x += PLAYER_HAND_TILE_W + HAND_TILE_GAP
	_deal_slots.clear()
	for hand_slot in _hand_slots:
		if hand_slot != null and is_instance_valid(hand_slot):
			_deal_slots.append(hand_slot)

	# 行投影
	var row_w: float = x - HAND_TILE_GAP if x > 0 else 0.0
	if row_w > 0:
		var shadow := _make_row_shadow(Vector2(row_w, PLAYER_HAND_TILE_H))
		shadow.name = "HandRowShadow"
		_hand_tile_row.add_child(shadow)
		_hand_tile_row.move_child(shadow, 0)

	# 重标 dora / clickable / dim 清
	for slot3 in _hand_slots:
		var tile: CardTileBack = slot3.get_node_or_null("Tile") as CardTileBack
		if tile == null:
			continue
		tile.set_clickable(_hand_clickable)
		tile.set_dora(_dora_ids.has(int(slot3.get_meta("hand_id", -1))))
		tile.set_dim(false)
		tile.set_hover_match(false)


func _make_hand_slot(tile_id: int, is_red: bool, scale_x: float, scale_y: float) -> Control:
	var slot := Control.new()
	slot.name = "HandSlot"
	slot.custom_minimum_size = Vector2(PLAYER_HAND_TILE_W, PLAYER_HAND_TILE_H)
	slot.size = Vector2(PLAYER_HAND_TILE_W, PLAYER_HAND_TILE_H)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.set_meta("hand_id", tile_id)
	slot.set_meta("hand_red", is_red)
	var edge_back := Panel.new()
	edge_back.name = "EdgeBack"
	edge_back.position = Vector2(0, -10)
	edge_back.size = Vector2(PLAYER_HAND_TILE_W, 10)
	edge_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge_back_style := StyleBoxFlat.new()
	edge_back_style.bg_color = Color("2c5b3e")
	edge_back_style.corner_radius_top_left = 5
	edge_back_style.corner_radius_top_right = 5
	edge_back.add_theme_stylebox_override("panel", edge_back_style)
	slot.add_child(edge_back)
	var edge_face := Panel.new()
	edge_face.name = "EdgeFace"
	edge_face.position = Vector2(0, -5)
	edge_face.size = Vector2(PLAYER_HAND_TILE_W, 10)
	edge_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge_face_style := StyleBoxFlat.new()
	edge_face_style.bg_color = Color("b9babc")
	edge_face_style.corner_radius_top_left = 5
	edge_face_style.corner_radius_top_right = 5
	edge_face.add_theme_stylebox_override("panel", edge_face_style)
	slot.add_child(edge_face)
	var tile := CardTileBack.new()
	tile.name = "Tile"
	tile.position = Vector2.ZERO
	tile.scale = Vector2(scale_x, scale_y)
	slot.add_child(tile)
	# hover / lifted 变换整张 DOM 等价物（含 before/after 棱），不只移动牌面。
	tile.set_motion_target(slot)
	tile.set_face_up(tile_id, is_red)
	tile.set_clickable(_hand_clickable)
	tile.card_clicked.connect(_on_player_tile_clicked)
	tile.mouse_entered.connect(_on_hand_tile_hover_slot.bind(slot, true))
	tile.mouse_exited.connect(_on_hand_tile_hover_slot.bind(slot, false))
	return slot


func _refresh_hand_slot(slot: Control, tile_id: int, is_red: bool) -> void:
	slot.set_meta("hand_id", tile_id)
	slot.set_meta("hand_red", is_red)
	var tile: CardTileBack = slot.get_node_or_null("Tile") as CardTileBack
	if tile == null:
		return
	# 仅当 id/red 变化时刷新贴图（reuse 命中时通常不变）
	if tile._tile_id != tile_id or tile._is_red_dora != is_red:
		tile.set_face_up(tile_id, is_red)


func _on_hand_tile_hover_slot(slot: Control, entered: bool) -> void:
	if _seat_id != 0 or slot == null:
		return
	var tid: int = int(slot.get_meta("hand_id", -1))
	highlight_hand_tile_id(tid if entered else -1)
	hand_tile_hover.emit(tid, entered)


# tid < 0 清除手牌同名高亮
func highlight_hand_tile_id(tid: int) -> void:
	for s in _hand_slots:
		if s == null or not is_instance_valid(s):
			continue
		var tile: CardTileBack = s.get_node_or_null("Tile") as CardTileBack
		if tile == null:
			continue
		var on: bool = tid >= 0 and int(s.get_meta("hand_id", -2)) == tid
		tile.set_hover_match(on)


func get_hand_slot_global_center(tile_id: int) -> Vector2:
	for s in _hand_slots:
		if s == null or not is_instance_valid(s):
			continue
		if int(s.get_meta("hand_id", -2)) == tile_id:
			return s.get_global_rect().get_center()
	return Vector2.ZERO

# ---- T2 单牌状态接线(spec 2026-06-11 G2) ----

var _dora_ids: Array = []

# FourPlayerTable.bind_battle_state 注入当前局实宝牌 id 集合(指示牌的下一张)。
# 在 bind_seat 重建手牌行之前调用。
func set_dora_ids(ids: Array) -> void:
	_dora_ids = ids

# 悬停同名联动:同 id 的其它手牌叠蓝色蒙版。仅自家手牌行内生效(v1)。
func _on_hand_tile_hover(tile_id: int, entered: bool) -> void:
	# 兼容旧调用；槽结构下转 slot 版
	if _seat_id != 0:
		return
	for s in _hand_slots:
		if s == null or not is_instance_valid(s):
			continue
		if int(s.get_meta("hand_id", -2)) == tile_id:
			var tile: CardTileBack = s.get_node_or_null("Tile") as CardTileBack
			if tile:
				tile.set_hover_match(entered)

# 吃牌选搭子模式:候选之外的手牌压暗。allowed 为可选搭子 tile_id 列表。
func dim_hand_except(allowed: Array) -> void:
	for s in _hand_slots:
		if s == null or not is_instance_valid(s):
			continue
		var tile: CardTileBack = s.get_node_or_null("Tile") as CardTileBack
		if tile:
			tile.set_dim(not allowed.has(int(s.get_meta("hand_id", -1))))

func clear_hand_dim() -> void:
	for s in _hand_slots:
		if s == null or not is_instance_valid(s):
			continue
		var tile: CardTileBack = s.get_node_or_null("Tile") as CardTileBack
		if tile:
			tile.set_dim(false)

# 和牌张脉冲:标记手牌行中第一张匹配 id 的牌(自摸/荣和宣告后、结算前)。
func mark_win_tile(tile_id: int) -> void:
	for s in _hand_slots:
		if s == null or not is_instance_valid(s):
			continue
		if int(s.get_meta("hand_id", -2)) == tile_id:
			var tile: CardTileBack = s.get_node_or_null("Tile") as CardTileBack
			if tile:
				tile.set_win_tile(true)
				return

# T5:发牌演出期间整行隐藏/恢复。
func set_hand_row_visible(b: bool) -> void:
	if _hand_tile_row:
		_hand_tile_row.visible = b


# 把已生成的真实 hand slot 套到公开 bundle 的 1600×900 flex/perspective
# 几何。上下家可由一个仿射变换表达；左右家必须逐槽投影，禁止整列统一缩放。
func apply_reference_hand_layout(meld_main_extent: float = 0.0) -> void:
	if _hand_tile_row == null:
		return
	var host_rect := TableLayout.hand_host_rect_for_state(
		_seat_id, _hand_base_count, meld_main_extent, _hand_has_drawn)
	set_meta("reference_hand_host_rect", host_rect)
	if _seat_id == 0:
		_hand_tile_row.scale = Vector2.ONE
		_hand_tile_row.position = host_rect.position - position
		return
	if _seat_id == 2:
		var raw_extent := TableLayout.hand_main_extent(2, _hand_base_count)
		_hand_tile_row.scale = Vector2(
			host_rect.size.x / raw_extent,
			host_rect.size.y / TOP_HAND_TILE_H,
		)
		# 根旋转 180°，local (0,0) 对应 hand host 的屏幕右下角。
		_hand_tile_row.position = (host_rect.end - position).rotated(
			-deg_to_rad(SEAT_ROTATION_DEGREES[_seat_id]))
		return
	_hand_tile_row.scale = Vector2.ONE
	_hand_tile_row.position = Vector2.ZERO
	for slot in _visual_hand_slots:
		if slot == null or not is_instance_valid(slot):
			continue
		var is_drawn := bool(slot.get_meta("is_drawn", false))
		var target := TableLayout.side_hand_drawn_slot_rect_for_state(
			_seat_id, _hand_base_count, meld_main_extent) if is_drawn else \
			TableLayout.side_hand_slot_rect_for_state(_seat_id,
				int(slot.get_meta("reference_slot_index", -1)), _hand_base_count,
				meld_main_extent, _hand_has_drawn)
		var raw_origin := TableLayout.side_hand_drawn_slot_raw_origin_for_state(
			_seat_id, _hand_base_count, meld_main_extent) if is_drawn else \
			TableLayout.side_hand_slot_raw_origin_for_state(_seat_id,
				int(slot.get_meta("reference_slot_index", -1)), _hand_base_count,
				meld_main_extent, _hand_has_drawn)
		# Slot 本地 66.63×46.71；根节点 ±90° 后屏幕宽对应 local y，
		# 屏幕高对应 local x。
		slot.scale = Vector2(
			target.size.y / SIDE_HAND_TILE_H,
			target.size.x / SIDE_HAND_TILE_W,
		)
		var screen_origin := Vector2(target.position.x, target.end.y) \
			if _seat_id == 1 else Vector2(target.end.x, target.position.y)
		slot.position = (screen_origin - position).rotated(
			-deg_to_rad(SEAT_ROTATION_DEGREES[_seat_id]))
		var cube := slot.get_node_or_null("CubeVisual") as Control
		if cube != null:
			_warp_side_cube_to_table_projection(cube, raw_origin)


func _warp_side_cube_to_table_projection(cube: Control,
		raw_origin: Vector2) -> void:
	var local_from_screen := cube.get_global_transform().affine_inverse()
	for layer in cube.get_children():
		if not layer.has_meta(CUBE_RAW_POINTS_META):
			continue
		var raw_points: PackedVector2Array = layer.get_meta(CUBE_RAW_POINTS_META)
		var projected_points := PackedVector2Array()
		for raw_point in raw_points:
			var table_point: Vector2 = raw_point
			if _seat_id == 3:
				table_point.x = SIDE_HAND_TILE_W - table_point.x
			projected_points.append(local_from_screen \
				* TableLayout.project_table_point(raw_origin + table_point))
		if layer is Polygon2D:
			(layer as Polygon2D).polygon = projected_points
		elif layer is Line2D:
			(layer as Line2D).points = projected_points


func get_reference_hand_metrics() -> Dictionary:
	return {
		"base_count": _hand_base_count,
		"has_drawn": _hand_has_drawn,
		"main_extent": TableLayout.hand_main_extent(_seat_id, _hand_base_count),
	}


func get_reference_hand_host_rect() -> Rect2:
	# FourPlayerTable bind 后 row 已按当前 meld extent 放置；由实际 row/host参数返回。
	var host_extent := TableLayout.hand_main_extent(_seat_id, _hand_base_count)
	if _seat_id == 0:
		return Rect2(position + _hand_tile_row.position, Vector2(host_extent, 92.0))
	if _seat_id == 2:
		var origin := get_global_transform() * _hand_tile_row.position
		return Rect2(origin.x - host_extent * _hand_tile_row.scale.x,
			origin.y - TOP_HAND_TILE_H * _hand_tile_row.scale.y,
			host_extent * _hand_tile_row.scale.x,
			TOP_HAND_TILE_H * _hand_tile_row.scale.y)
	# side host 使用 apply 后第一个视觉槽无法代表 placeholder；保存由 bind 注入的值。
	return Rect2(get_meta("reference_hand_host_rect", Rect2()))


func get_visual_hand_rects() -> Array[Rect2]:
	var slots: Array = _hand_slots if _seat_id == 0 else _visual_hand_slots
	var result: Array[Rect2] = []
	for slot in slots:
		if slot == null or not is_instance_valid(slot):
			continue
		result.append(_control_global_aabb(slot as Control))
	return result


# 对标线上 getBoundingClientRect()：只返回当前真实的 13 个 slot 全局 AABB。
# 发牌期间 hand row 只是 visible=false，节点几何仍存在，故无需静态魔法坐标。
func get_deal_target_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	if _deal_slots.size() != 13:
		return result
	for slot in _deal_slots:
		if slot == null or not is_instance_valid(slot):
			return []
		result.append(_control_global_aabb(slot))
	return result


static func _control_global_aabb(control: Control) -> Rect2:
	var xf := control.get_global_transform()
	var p0 := xf * Vector2.ZERO
	var p1 := xf * Vector2(control.size.x, 0)
	var p2 := xf * Vector2(0, control.size.y)
	var p3 := xf * control.size
	var min_x := minf(minf(p0.x, p1.x), minf(p2.x, p3.x))
	var min_y := minf(minf(p0.y, p1.y), minf(p2.y, p3.y))
	var max_x := maxf(maxf(p0.x, p1.x), maxf(p2.x, p3.x))
	var max_y := maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y))
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


# 切换玩家手牌点击响应。轮到玩家出牌时调 true，AI 回合或鸣牌响应窗口外调 false。
# 仅 seat==0 有效；其它 seat 调用本方法无效（手牌行只有色块不 emit click）。
func set_hand_clickable(b: bool) -> void:
	_hand_clickable = b
	for s in _hand_slots:
		if s == null or not is_instance_valid(s):
			continue
		var tile: CardTileBack = s.get_node_or_null("Tile") as CardTileBack
		if tile:
			tile.set_clickable(b)

func _on_player_tile_clicked(tile_id: int) -> void:
	if _seat_id != 0:
		return  # 防御：只有玩家自家手牌行 emit
	player_card_clicked.emit(tile_id)
