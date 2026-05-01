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

var _owner_seat: int = 0
var _tile_id: int = -1
var _is_revealed: bool = false

var _face_label: Label = null

func _init() -> void:
	custom_minimum_size = Vector2(TILE_WIDTH, TILE_HEIGHT)
	size = Vector2(TILE_WIDTH, TILE_HEIGHT)

func _ready() -> void:
	# 子节点 Label 用于"正面"模式
	_face_label = Label.new()
	_face_label.size = Vector2(TILE_WIDTH, TILE_HEIGHT)
	_face_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_face_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_face_label.add_theme_font_size_override("font_size", 22)
	_face_label.add_theme_color_override("font_color", Color(0.10, 0.10, 0.10))
	_face_label.visible = false
	add_child(_face_label)
	_refresh()

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
	if is_inside_tree():
		_refresh()

# ---- helpers (static, 测试可用) ----

static func tile_back_color(owner_seat: int) -> Color:
	if owner_seat < 0 or owner_seat >= SEAT_TILE_BACK_COLORS.size():
		return UNKNOWN_OWNER_COLOR
	return SEAT_TILE_BACK_COLORS[owner_seat]

# 牌简短名（与 CenterInfoPanel._tile_short_name 保持一致；这里独立避免跨模块依赖）
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

	if _is_revealed:
		# 透明牌：显示正面占位（白底 + tile name），整体 alpha=0.5
		sb.bg_color = REVEALED_FACE_COLOR
		modulate.a = REVEALED_ALPHA
		if _face_label:
			_face_label.text = tile_short_name(_tile_id)
			_face_label.visible = true
	else:
		# 牌背：纯色块 by owner_seat，完全不透明
		sb.bg_color = tile_back_color(_owner_seat)
		modulate.a = 1.0
		if _face_label:
			_face_label.visible = false

	add_theme_stylebox_override("panel", sb)
