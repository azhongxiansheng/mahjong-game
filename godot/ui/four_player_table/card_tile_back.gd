class_name CardTileBack extends Panel

# 麻将王 — 里程碑 3 第 3 步：牌背 + 透明牌可视化（plan-3 D2/D5）
#
# 80×120 px 牌背色块 by `owner_seat`；透明牌路径（被 §8.5 类技能 reveal）
# 在 owner=seat 0（玩家）端把渲染换成"正面 Label + alpha=0.5"半透明效果。
#
# 数据流（单向）：调用方 set_tile_instance / set_revealed → 内部刷新视觉。
# 不依赖 BattleState 引用，组合性强（SeatPanel / smoke / F6 都能复用）。

const TILE_WIDTH: int = 80
const TILE_HEIGHT: int = 120
const BORDER_WIDTH: int = 2

# spec §10：4 套牌背贴图 v1 用程序化色块（D2 方案 A）
# seat 0 玩家金色固定，1-3 AI 主题色（M7 引入 AIProfile 后会改读 ai_profiles[i].tile_back_color）
const SEAT_TILE_BACK_COLORS: Array[Color] = [
	Color(0.90, 0.75, 0.20),  # 0 玩家 GOLD
	Color(0.75, 0.25, 0.25),  # 1 RED
	Color(0.25, 0.60, 0.30),  # 2 GREEN
	Color(0.25, 0.40, 0.75),  # 3 BLUE
]

const UNKNOWN_OWNER_COLOR: Color = Color(0.40, 0.40, 0.40)
const REVEALED_FACE_COLOR: Color = Color(0.95, 0.95, 0.92)
const REVEALED_ALPHA: float = 0.5

signal card_clicked(tile_id: int)

var _owner_seat: int = 0
var _tile_id: int = -1
var _is_revealed: bool = false
# face_up 与 revealed 的区分：
#   face_up=true  → 玩家自己的手牌 / 弃牌河 / 宝牌指示牌，完全不透明 atlas 纹理正面
#   revealed=true → 被技能(§8.5)穿透的对手手牌，alpha=0.5 半透明 atlas 纹理正面
# 同时为 false 时 → 牌背色块（按 owner_seat 上色）
var _is_face_up: bool = false
# 是否响应点击（仅玩家手牌且轮到玩家时 = true）。
# 不响应时鼠标 hover / 点击都不发 signal，按钮状态由 set_clickable 调用方控制。
var _is_clickable: bool = false

var _face_label: Label = null
# 当前要画的 atlas 纹理（_refresh 解析后赋值；_draw 直接 draw_texture_rect）
var _face_atlas_tex: Texture2D = null
# 牌背模式下要画的 back.png 纹理（默认色块 fall-back 给 _back_tint）
var _back_tex: Texture2D = null
# 牌背着色（按 owner_seat；保留 plan-3 D2/D5 的归属可视化）
var _back_tint: Color = Color.WHITE

func _init() -> void:
	custom_minimum_size = Vector2(TILE_WIDTH, TILE_HEIGHT)
	size = Vector2(TILE_WIDTH, TILE_HEIGHT)

func _ready() -> void:
	# 子节点 Label 作为 atlas 缺失时的降级显示
	_face_label = Label.new()
	_face_label.size = Vector2(TILE_WIDTH, TILE_HEIGHT)
	_face_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_face_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_face_label.add_theme_font_size_override("font_size", 22)
	_face_label.add_theme_color_override("font_color", Color(0.10, 0.10, 0.10))
	_face_label.visible = false
	# Label 不挡 click
	_face_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_face_label)
	# 接 gui_input 实现 click 检测;mouse_entered/exited 做 hover lift
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_enter)
	mouse_exited.connect(_on_mouse_exit)
	_refresh()


# Hover lift:可点击牌(玩家自家手牌)鼠标 hover 时上抬,提供"可选"反馈。
# 玩家手牌在 SeatPanel 内 scale=0.5,所以 local 16 px ≈ 视觉 8 px lift。
# Tween 60ms 缓动比硬切自然得多。不可点击时跳过(AI 牌背不响应)。
const HOVER_LIFT_PX: float = 16.0
const HOVER_TWEEN_S: float = 0.06
var _hover_base_y: float = 0.0
var _hover_tween: Tween = null
var _hover_active: bool = false

func _on_mouse_enter() -> void:
	if not _is_clickable or _hover_active:
		return
	_hover_active = true
	_hover_base_y = position.y
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "position:y", _hover_base_y - HOVER_LIFT_PX, HOVER_TWEEN_S)


func _on_mouse_exit() -> void:
	if not _hover_active:
		return
	_hover_active = false
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "position:y", _hover_base_y, HOVER_TWEEN_S)

# 直接 draw_texture_rect 画 atlas，避免 TextureRect 嵌套渲染的诡异问题。
# Panel.draw_style_box 在 NOTIFICATION_DRAW 已画了 stylebox；这里在子 _draw
# 中追加 atlas 牌面图（face_up / revealed）或 back 牌背图。
func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(TILE_WIDTH, TILE_HEIGHT))
	if _face_atlas_tex != null:
		draw_texture_rect(_face_atlas_tex, rect, false, Color.WHITE)
	elif _back_tex != null:
		draw_texture_rect(_back_tex, rect, false, _back_tint)

func _on_gui_input(event: InputEvent) -> void:
	if not _is_clickable:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not mb.canceled:
			_play_click_pulse()
			card_clicked.emit(_tile_id)


# 点击瞬间反馈:缩到 0.94 倍再弹回,告知玩家"点已生效"。
# 60ms 总长不阻塞 emit;视觉反馈与逻辑解耦。
func _play_click_pulse() -> void:
	var orig: Vector2 = scale
	var t := create_tween()
	t.tween_property(self, "scale", orig * 0.94, 0.04)
	t.tween_property(self, "scale", orig, 0.06)

func set_clickable(b: bool) -> void:
	_is_clickable = b
	# 视觉反馈：可点击时鼠标悬停手指，不可点击时默认箭头
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if b else Control.CURSOR_ARROW

# ---- public setters ----

func set_tile_instance(ti: TileInstance) -> void:
	if ti == null:
		_owner_seat = -1
		_tile_id = -1
	else:
		_owner_seat = ti.owner_seat
		_tile_id = ti.tile.id if ti.tile else -1
	if is_inside_tree():
		_refresh()

func set_owner_seat(seat: int) -> void:
	_owner_seat = seat
	if is_inside_tree():
		_refresh()

func set_tile_id(tid: int) -> void:
	_tile_id = tid
	if is_inside_tree():
		_refresh()

func set_revealed(b: bool) -> void:
	_is_revealed = b
	if b:
		_is_face_up = false  # 互斥：reveal 优先于普通 face_up
	if is_inside_tree():
		_refresh()

# face_up：玩家自己手牌 / 弃牌河 / 宝牌指示牌的不透明正面渲染。
# 调用此方法等价于 set_tile_id(tid) + 启用 face_up 模式。
func set_face_up(tile_id: int) -> void:
	_tile_id = tile_id
	_is_face_up = true
	_is_revealed = false
	if is_inside_tree():
		_refresh()

# ---- helpers (static, 测试可用) ----

# TileId → TextureExtractor atlas key 映射（v2：标准日麻 riichi notation）。
#   万 W1..W9 → 1m..9m
#   筒 T1..T9 → 1p..9p
#   条 S1..S9 → 1s..9s
#   字   E/S_WIND/W_WIND/N/HAKU/HATSU/CHUN → 1z..7z
static func tile_id_to_atlas_key(tile_id: int) -> String:
	if tile_id < 0:
		return ""
	if tile_id <= TileId.W9:
		return "%dm" % (tile_id + 1)
	if tile_id <= TileId.T9:
		return "%dp" % (tile_id - 8)
	if tile_id <= TileId.S9:
		return "%ds" % (tile_id - 17)
	match tile_id:
		TileId.E: return "1z"
		TileId.S_WIND: return "2z"
		TileId.W_WIND: return "3z"
		TileId.N: return "4z"
		TileId.HAKU: return "5z"
		TileId.HATSU: return "6z"
		TileId.CHUN: return "7z"
	return ""

static func tile_back_color(owner_seat: int) -> Color:
	if owner_seat < 0 or owner_seat >= SEAT_TILE_BACK_COLORS.size():
		return UNKNOWN_OWNER_COLOR
	return SEAT_TILE_BACK_COLORS[owner_seat]

# 牌简短名（共用入口，CenterInfoPanel.dora_summary 路由到此,避免重复）
static func tile_short_name(tile_id: int) -> String:
	if tile_id < 0:
		return "?"
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

func _refresh() -> void:
	var sb := StyleBoxFlat.new()
	sb.border_width_top = BORDER_WIDTH
	sb.border_width_bottom = BORDER_WIDTH
	sb.border_width_left = BORDER_WIDTH
	sb.border_width_right = BORDER_WIDTH
	sb.border_color = Color.BLACK

	var atlas_tex: Texture2D = _resolve_atlas_texture(_tile_id)

	if _is_face_up:
		# face_up：白底（atlas 透明区 fall-back）+ atlas 牌面（在 _draw 直接画）
		sb.bg_color = Color(1, 1, 1, 1)
		modulate.a = 1.0
		if atlas_tex:
			_face_atlas_tex = atlas_tex
			if _face_label:
				_face_label.visible = false
		else:
			_face_atlas_tex = null
			if _face_label:
				_face_label.text = tile_short_name(_tile_id)
				_face_label.visible = true
	elif _is_revealed:
		# 透明牌（被 §8.5 类技能 reveal）：atlas 正面 + alpha=0.5
		sb.bg_color = REVEALED_FACE_COLOR
		modulate.a = REVEALED_ALPHA
		if atlas_tex:
			_face_atlas_tex = atlas_tex
			if _face_label:
				_face_label.visible = false
		else:
			_face_atlas_tex = null
			if _face_label:
				_face_label.text = tile_short_name(_tile_id)
				_face_label.visible = true
	else:
		# 牌背：用 back.png + 按 owner_seat 着色保留归属可视化（plan-3 D2/D5）。
		# StyleBox bg 用一个跟 back 颜色协调的深底，避免 back 透明区透出突兀。
		sb.bg_color = Color(0.07, 0.10, 0.18, 1.0)
		modulate.a = 1.0
		_face_atlas_tex = null
		_back_tex = _resolve_back_texture()
		_back_tint = _compute_back_tint(_owner_seat)
		if _face_label:
			_face_label.visible = false

	add_theme_stylebox_override("panel", sb)
	queue_redraw()  # 触发 _draw 用最新 _face_atlas_tex

# 通过 TextureExtractor autoload 查 atlas 纹理。autoload 不在或缺牌时返回 null
# 让 _refresh 走 Label 降级。仅 inside_tree 时可用（autoload 通过 SceneTree 拿）。
func _resolve_atlas_texture(tile_id: int) -> Texture2D:
	if tile_id < 0:
		return null
	if not is_inside_tree():
		return null
	var key: String = tile_id_to_atlas_key(tile_id)
	if key == "":
		return null
	var extractor: Node = get_tree().root.get_node_or_null("TextureExtractor")
	if extractor == null or not extractor.has_method("get_tile_texture"):
		return null
	return extractor.get_tile_texture(key)

# 取牌背图（back.png）。autoload 不在或缺图时返 null（_draw 走 stylebox bg fall-back）。
func _resolve_back_texture() -> Texture2D:
	if not is_inside_tree():
		return null
	var extractor: Node = get_tree().root.get_node_or_null("TextureExtractor")
	if extractor == null or not extractor.has_method("get_tile_texture"):
		return null
	return extractor.get_tile_texture("back")

# 牌背着色：在 back.png 上叠 owner_seat 主题色作 modulate（保留归属可视化）。
# back.png 是深蓝主体；用 0.7 强度的 seat 颜色 multiply 让色调偏向 owner，
# 但仍保留牌背图案。owner_seat=0（玩家自家）不染色，纯 back.png。
func _compute_back_tint(owner_seat: int) -> Color:
	if owner_seat <= 0 or owner_seat > 3:
		return Color.WHITE
	var seat_color: Color = tile_back_color(owner_seat)
	# 把 seat 颜色拉淡一些（与深蓝 back 混合后不至于掩盖图案）
	return seat_color.lerp(Color.WHITE, 0.3)
