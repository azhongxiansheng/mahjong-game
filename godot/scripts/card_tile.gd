class_name CardTile
extends Control

# 属性
var card_data: CardData
var is_selected: bool = false
var is_highlighted: bool = false

# UI引用 (不使用 @onready，改为在 _ready() 中初始化)
var card_label: Label = null
var suit_label: Label = null

# 信号
signal card_pressed(card_data: CardData)
signal card_selected(card_data: CardData)

# 麻将牌设计常数
const TILE_WIDTH = 80
const TILE_HEIGHT = 120
const BORDER_COLOR = Color(0.2, 0.2, 0.2, 1.0)
const BORDER_WIDTH = 3
const SHADOW_COLOR = Color(0.0, 0.0, 0.0, 0.3)

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	custom_minimum_size = Vector2(TILE_WIDTH, TILE_HEIGHT)
	size = Vector2(TILE_WIDTH, TILE_HEIGHT)

	# 设置默认样式
	modulate = Color.WHITE
	visible = true
	z_index = 10

	# ✓ 如果标签不存在，动态创建它们
	if not has_node("Label"):
		card_label = Label.new()
		card_label.name = "Label"
		add_child(card_label)
		card_label.anchor_left = 0.5
		card_label.anchor_top = 0.5
		card_label.offset_left = -40
		card_label.offset_top = -70
		card_label.size = Vector2(80, 50)
		card_label.theme_override_font_sizes/font_size = 32
		card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		print("[CardTile] 动态创建 Label 节点")
	else:
		card_label = $Label

	if not has_node("SuitLabel"):
		suit_label = Label.new()
		suit_label.name = "SuitLabel"
		add_child(suit_label)
		suit_label.anchor_left = 0.5
		suit_label.anchor_top = 0.5
		suit_label.offset_left = -40
		suit_label.offset_top = 0
		suit_label.size = Vector2(80, 50)
		suit_label.theme_override_font_sizes/font_size = 18
		suit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		print("[CardTile] 动态创建 SuitLabel 节点")
	else:
		suit_label = $SuitLabel

	print("[CardTile] _ready完成, 位置:", position, " 大小:", size, " 可见:", visible)

	# 如果已经设置了卡牌数据，更新显示
	if card_data:
		update_display()

func set_card(card: CardData) -> void:
	"""设置卡牌数据并更新显示"""
	card_data = card
	if is_node_ready():
		update_display()
	else:
		await ready
		update_display()

func update_display() -> void:
	"""更新卡牌显示内容"""
	if not card_data:
		print("[CardTile] update_display: 没有card_data")
		return

	if card_label == null or suit_label == null:
		print("[CardTile] update_display: label为null")
		return

	card_label.text = str(card_data.number)
	suit_label.text = _get_suit_name(card_data.suit)
	
	# ✅ 新增: 设置文字颜色和背景颜色
	var bg_color = _get_suit_color(card_data.suit)
	self_modulate = Color.WHITE
	
	# 根据背景颜色设置文字颜色
	var text_color = Color.WHITE if bg_color.get_luminance() < 0.5 else Color.BLACK
	card_label.theme_override_colors/font_color = text_color
	suit_label.theme_override_colors/font_color = text_color

	print("[CardTile] 更新显示: ", card_data.get_card_name(), " 文本:", card_label.text, "/", suit_label.text)

func _get_suit_name(suit: int) -> String:
	"""根据花色返回花色名称"""
	match suit:
		0: return "万"
		1: return "筒"
		2: return "条"
		3: return "字"
	return ""

func _get_suit_color(suit: int) -> Color:
	"""根据花色返回颜色"""
	match suit:
		0: return Color(0.95, 0.85, 0.85, 1.0)  # 万-浅红
		1: return Color(0.85, 0.90, 0.95, 1.0)  # 筒-浅蓝
		2: return Color(0.85, 0.95, 0.85, 1.0)  # 条-浅绿
		3: return Color(0.95, 0.95, 0.85, 1.0)  # 字-浅黄
	return Color.WHITE

func highlight() -> void:
	"""高亮显示卡牌（鼠标悬停）"""
	is_highlighted = true
	scale = Vector2(1.05, 1.05)

func unhighlight() -> void:
	"""取消高亮显示"""
	is_highlighted = false
	if not is_selected:
		scale = Vector2(1.0, 1.0)

func select() -> void:
	"""选中卡牌"""
	is_selected = true
	scale = Vector2(1.1, 1.1)
	card_selected.emit(card_data)

func deselect() -> void:
	"""取消选中卡牌"""
	is_selected = false
	scale = Vector2(1.0, 1.0)

func animate_to_position(target_pos: Vector2, duration: float = 0.5) -> void:
	"""动画移动到目标位置"""
	var tween = create_tween()
	tween.tween_property(self, "position", target_pos, duration)

func animate_discard() -> void:
	"""出牌动画"""
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(0.1, 0.1), 0.3)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)

func animate_win() -> void:
	"""胡牌特效动画"""
	var tween = create_tween()
	for i in range(3):
		tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.1)
		tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)

func _draw() -> void:
	"""绘制麻将牌外观"""
	# ✅ 新增: 绘制3D效果的麻将牌
	var rect = Rect2(0, 0, TILE_WIDTH, TILE_HEIGHT)
	
	# 阴影
	draw_rect(Rect2(2, 2, TILE_WIDTH - 2, TILE_HEIGHT - 2), SHADOW_COLOR)
	
	# 主体背景 - 根据选中状态改变颜色
	var bg_color = _get_suit_color(card_data.suit) if card_data else Color.WHITE
	draw_rect(rect, bg_color)
	
	# 外边框
	draw_rect(rect, BORDER_COLOR, false, BORDER_WIDTH)
	
	# 内边框（装饰）
	var inner_rect = Rect2(BORDER_WIDTH, BORDER_WIDTH, TILE_WIDTH - 2 * BORDER_WIDTH, TILE_HEIGHT - 2 * BORDER_WIDTH)
	draw_rect(inner_rect, Color.TRANSPARENT, false, 1)

func _on_gui_input(event: InputEvent) -> void:
	"""处理鼠标点击事件"""
	if event is InputEventMouseButton and event.pressed:
		card_pressed.emit(card_data)

func _on_mouse_entered() -> void:
	"""鼠标进入卡牌"""
	if not is_selected:
		highlight()

func _on_mouse_exited() -> void:
	"""鼠标离开卡牌"""
	if not is_selected:
		unhighlight()
