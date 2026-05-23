class_name SeatPanel extends Node2D

# seat 0 (玩家) 自家手牌被点击时转发给上层（PlayerActionPanel / PlayableTable）。
# 其它 seat 永不 emit（手牌色块本身不 clickable）。
signal player_card_clicked(tile_id: int)

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
const HAND_TILE_W: float = 30.0
const HAND_TILE_H: float = 45.0
const HAND_TILE_GAP: float = 3.0
const HAND_ROW_OFFSET_X: float = -220.0  # 相对 panel 中心
const HAND_ROW_OFFSET_Y: float = 30.0
# 玩家自己 (seat 0) 手牌用真实 atlas 牌面，需要稍大尺寸才看清
const PLAYER_HAND_TILE_W: float = 40.0
const PLAYER_HAND_TILE_H: float = 60.0
const PLAYER_HAND_ROW_OFFSET_X: float = -240.0
# 刚摸的牌与其他 13 张之间的间距（spec 2026-05-08 bug 2 fix；日麻 UI 标准）
const PLAYER_HAND_DRAWN_GAP: float = 16.0
var _hand_tile_row: Node2D = null

# 玩家手牌当前是否接受点击（轮到玩家出牌时切 true）
var _hand_clickable: bool = false

var _seat_id: int = 0
var _seat_wind: int = TileId.E
var _score: int = 25000
var _hand_size: int = 13
var _meld_count: int = 0
var _discards_count: int = 0
var _riichi: bool = false
var _furiten: bool = false

func _ready() -> void:
	_hand_tile_row = Node2D.new()
	# 偏移在 _rebuild_*_row 之前会按 seat_id 调整（seat 0 用更宽的偏移给真实牌面留位）
	_hand_tile_row.position = Vector2(HAND_ROW_OFFSET_X, HAND_ROW_OFFSET_Y)
	add_child(_hand_tile_row)
	_refresh_labels()

# 切换 seat 0 / 其它 seat 时切换 hand_tile_row 的水平偏移。
# seat 0 用真实 atlas 牌面（40x60）需要更宽 ~560 px；其它 seat 用色块（30x45）~450 px。
func _apply_hand_row_offset() -> void:
	if _hand_tile_row == null:
		return
	if _seat_id == 0:
		_hand_tile_row.position = Vector2(PLAYER_HAND_ROW_OFFSET_X, HAND_ROW_OFFSET_Y)
	else:
		_hand_tile_row.position = Vector2(HAND_ROW_OFFSET_X, HAND_ROW_OFFSET_Y)

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


# 当前回合高亮:把 Bg ColorRect 包一个金色描边,玩家从 4 家中立刻识别出
# "现在该谁出牌"。false 时清除 override 回到主题。
func set_active(b: bool) -> void:
	if _active == b:
		return
	_active = b
	if is_inside_tree():
		_apply_active_visual()


var _active: bool = false

func _apply_active_visual() -> void:
	var bg := get_node_or_null("Bg") as ColorRect
	if bg == null:
		return
	if _active:
		# 金色描边浮出来,Bg 本身保留底色,不破坏既有视觉
		var glow := StyleBoxFlat.new()
		glow.bg_color = bg.color  # 保持原底色
		glow.border_color = Color(1, 0.85, 0.25)
		glow.border_width_left = 3
		glow.border_width_top = 3
		glow.border_width_right = 3
		glow.border_width_bottom = 3
		glow.corner_radius_top_left = 4
		glow.corner_radius_top_right = 4
		glow.corner_radius_bottom_left = 4
		glow.corner_radius_bottom_right = 4
		# ColorRect 没有 stylebox,改用 Panel 覆盖:在 Bg 旁加金边 Panel 仅做边框
		if get_node_or_null("ActiveGlow") == null:
			var glow_panel := Panel.new()
			glow_panel.name = "ActiveGlow"
			glow_panel.position = bg.position
			glow_panel.size = bg.size
			glow_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0)  # 透明,仅显边
			sb.border_color = Color(1, 0.85, 0.25)
			sb.border_width_left = 3
			sb.border_width_top = 3
			sb.border_width_right = 3
			sb.border_width_bottom = 3
			glow_panel.add_theme_stylebox_override("panel", sb)
			add_child(glow_panel)
	else:
		var existing := get_node_or_null("ActiveGlow")
		if existing:
			existing.queue_free()

# 手牌色块归属可视化（M3 收尾）：传入 owners 数组（每张牌的 owner_seat），
# 重建 _hand_tile_row 子节点。owners.size() 也作为 hand_size 同步更新文字 Label。
func set_hand_tile_owners(owners: Array) -> void:
	_hand_size = owners.size()
	if is_inside_tree():
		_rebuild_hand_tile_row(owners)
		_refresh_labels()

# 一次注入 Seat 全部状态（含手牌色块归属）
# seat 0 时若传入 hand 则同时渲染真实 atlas 牌面（玩家自家可见），
# 其它 seat 仍用 owner 着色色块（对手牌不可见，符合规则）。
func bind_seat(seat: Seat) -> void:
	_seat_wind = seat.seat_wind
	_score = seat.points
	_hand_size = seat.hand.size()
	_meld_count = seat.melds.size()
	_riichi = seat.riichi.declared
	_furiten = seat.furiten.is_furiten() if seat.furiten else false
	# discards 数量需外部传入（Seat 自身不持，BattleState.discards_per_seat[i] 持）
	if is_inside_tree():
		if _seat_id == 0:
			# spec 2026-05-08 bug 2 fix：把刚摸的牌单独显示在最右
			_rebuild_player_hand_row_with_drawn(seat.hand, seat.last_drawn_tile_id)
		else:
			_rebuild_hand_tile_row(seat.hand.to_owner_array())
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
	# 雀魂式简洁：名字·风(·庄 if dealer)·状态。
	# 庄家用 seat_wind=东 判定(日麻规则:庄永远是东家)。
	var status: String = ""
	if _seat_wind == TileId.E:
		status += " · 庄"
	if _riichi:
		status += " · 立直"
	elif _furiten:
		status += " · 振"
	_label_seat_info.text = "%s · %s%s" % [seat_display_name(_seat_id), wind_name(_seat_wind), status]
	_label_score.text = "%d" % _score
	# spec 2026-05-08 MeldArea：副露已用 MeldArea 视觉化，弃用文字 Label
	# 手牌张数 / 弃牌河张数也弃用：MeldArea + DiscardRiver 视觉自身已传达
	_label_melds.text = ""
	_label_melds.visible = false
	_label_hand.text = ""
	_label_hand.visible = false
	_label_discards.text = ""
	_label_discards.visible = false

# 重建非玩家 seat 的手牌行：按 owners 数组生成 TextureRect 显示 back.png，
# 用 owner_seat 颜色作 modulate 保留归属可视化（plan-3 D2/D5）。
# 比纯 ColorRect 更接近真实牌背视觉，玩家立刻能识别"这是牌背"。
func _rebuild_hand_tile_row(owners: Array) -> void:
	if _hand_tile_row == null:
		return
	_apply_hand_row_offset()
	for child in _hand_tile_row.get_children():
		child.queue_free()
	var back_tex: Texture2D = _resolve_back_texture()
	var x := 0.0
	for owner_seat in owners:
		var rect := TextureRect.new()
		rect.position = Vector2(x, 0)
		rect.size = Vector2(HAND_TILE_W, HAND_TILE_H)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		if back_tex != null:
			rect.texture = back_tex
			# 用 seat 颜色 modulate 保留归属（淡化 seat 颜色避免完全盖住牌背图案）
			rect.modulate = CardTileBack.tile_back_color(int(owner_seat)).lerp(Color.WHITE, 0.3)
		else:
			# back.png 缺失 fall-back：仍用纯色块
			rect.modulate = CardTileBack.tile_back_color(int(owner_seat))
		_hand_tile_row.add_child(rect)
		x += HAND_TILE_W + HAND_TILE_GAP

# 取牌背图（autoload TextureExtractor）。autoload 不在或缺图时返 null。
func _resolve_back_texture() -> Texture2D:
	if not is_inside_tree():
		return null
	var extractor: Node = get_tree().root.get_node_or_null("TextureExtractor")
	if extractor == null or not extractor.has_method("get_tile_texture"):
		return null
	return extractor.get_tile_texture("back")

# 玩家手牌（seat 0）真实 atlas 渲染：CardTileBack.set_face_up + 缩放到 40x60。
# 复用 CardTileBack 是为了一致样式（边框、modulate=WHITE、tile_id_to_atlas_key
# 映射），不用为玩家手牌再造一个 TextureRect 包装。
func _rebuild_player_hand_row(tile_ids: Array) -> void:
	# 兼容旧 caller（无 drawn 信息）：全部按一行渲染，无分隔
	_rebuild_player_hand_row_internal(tile_ids, [])

# spec 2026-05-08 bug 2 fix：把刚摸的牌单独显示在最右（与其他 13 张间留 PLAYER_HAND_DRAWN_GAP 间距）
# hand：当前手牌 Hand；drawn_tile_id：刚摸的牌 id（-1 = 不在 post-draw 状态，全 sorted 渲染）
# 算法：
#   - drawn_tile_id < 0：全部 sorted 渲染（同 _rebuild_player_hand_row 旧行为）
#   - drawn_tile_id >= 0：从 hand 中 pop 1 张匹配 id 的牌作"刚摸"；剩下 sorted；
#     渲染顺序 = sorted 13 张 + 间距 + 1 张刚摸的牌（最右）
func _rebuild_player_hand_row_with_drawn(hand: Hand, drawn_tile_id: int) -> void:
	var split: Dictionary = split_hand_for_display(hand, drawn_tile_id)
	_rebuild_player_hand_row_internal(split.sorted_ids, split.drawn_ids)

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
	var all_ids: Array = []
	for t in hand._tiles:
		all_ids.append(t.id)
	if drawn_tile_id < 0:
		all_ids.sort()
		return {"sorted_ids": all_ids, "drawn_ids": []}
	var drawn_idx: int = all_ids.find(drawn_tile_id)
	if drawn_idx < 0:
		# 异常 fallback：drawn id 在 hand 中找不到（如刚 chi/pon 后未及时清 -1）
		all_ids.sort()
		return {"sorted_ids": all_ids, "drawn_ids": []}
	all_ids.remove_at(drawn_idx)
	all_ids.sort()
	return {"sorted_ids": all_ids, "drawn_ids": [drawn_tile_id]}

# 内部统一渲染：sorted_ids 在左，drawn_ids 在右（与 sorted 之间留 PLAYER_HAND_DRAWN_GAP 间距）
func _rebuild_player_hand_row_internal(sorted_ids: Array, drawn_ids: Array) -> void:
	if _hand_tile_row == null:
		return
	_apply_hand_row_offset()
	for child in _hand_tile_row.get_children():
		child.queue_free()
	var scale_x: float = PLAYER_HAND_TILE_W / float(CardTileBack.TILE_WIDTH)
	var scale_y: float = PLAYER_HAND_TILE_H / float(CardTileBack.TILE_HEIGHT)
	var x := 0.0
	for tid in sorted_ids:
		_spawn_player_tile(tid, x, scale_x, scale_y)
		x += PLAYER_HAND_TILE_W + HAND_TILE_GAP
	if not drawn_ids.is_empty():
		# 让间距更明显：把现在的 x 上加 DRAWN_GAP - HAND_TILE_GAP
		x += PLAYER_HAND_DRAWN_GAP - HAND_TILE_GAP
		for tid in drawn_ids:
			_spawn_player_tile(tid, x, scale_x, scale_y)
			x += PLAYER_HAND_TILE_W + HAND_TILE_GAP

func _spawn_player_tile(tile_id: int, x: float, scale_x: float, scale_y: float) -> void:
	var tile := CardTileBack.new()
	tile.position = Vector2(x, 0)
	tile.scale = Vector2(scale_x, scale_y)
	_hand_tile_row.add_child(tile)
	tile.set_face_up(int(tile_id))
	tile.set_clickable(_hand_clickable)
	tile.card_clicked.connect(_on_player_tile_clicked)

# 切换玩家手牌点击响应。轮到玩家出牌时调 true，AI 回合或鸣牌响应窗口外调 false。
# 仅 seat==0 有效；其它 seat 调用本方法无效（手牌行只有色块不 emit click）。
func set_hand_clickable(b: bool) -> void:
	_hand_clickable = b
	if _hand_tile_row == null:
		return
	for child in _hand_tile_row.get_children():
		if child is CardTileBack:
			child.set_clickable(b)

func _on_player_tile_clicked(tile_id: int) -> void:
	if _seat_id != 0:
		return  # 防御：只有玩家自家手牌行 emit
	player_card_clicked.emit(tile_id)
