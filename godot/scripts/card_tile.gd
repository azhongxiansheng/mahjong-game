class_name CardTile
extends Control

# 属性
var card_data: CardData
var is_selected: bool = false
var is_highlighted: bool = false

# UI引用
@onready var card_label = $Label
@onready var suit_label = $SuitLabel

# 信号
signal card_pressed(card_data: CardData)
signal card_selected(card_data: CardData)

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	custom_minimum_size = Vector2(80, 120)

	# 设置默认样式
	modulate = Color.WHITE

func set_card(card: CardData) -> void:
	"""设置卡牌数据并更新显示"""
	card_data = card
	update_display()

func update_display() -> void:
	"""更新卡牌显示内容"""
	if not card_data:
		return
	card_label.text = str(card_data.number)
	suit_label.text = _get_suit_name(card_data.suit)
	modulate = _get_suit_color(card_data.suit)

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
		0: return Color(0.8, 0.2, 0.2, 1.0)  # 万-红色
		1: return Color(0.2, 0.4, 0.8, 1.0)  # 筒-蓝色
		2: return Color(0.2, 0.7, 0.2, 1.0)  # 条-绿色
		3: return Color(0.8, 0.8, 0.0, 1.0)  # 字-黄色
	return Color.WHITE

func highlight() -> void:
	"""高亮显示卡牌（鼠标悬停）"""
	is_highlighted = true
	self_modulate = Color.WHITE
	scale = Vector2(1.05, 1.05)

func unhighlight() -> void:
	"""取消高亮显示"""
	is_highlighted = false
	if not is_selected:
		self_modulate = Color(0.8, 0.8, 0.8)
	scale = Vector2(1.0, 1.0)

func select() -> void:
	"""选中卡牌"""
	is_selected = true
	scale = Vector2(1.1, 1.1)
	self_modulate = Color.YELLOW
	card_selected.emit(card_data)

func deselect() -> void:
	"""取消选中卡牌"""
	is_selected = false
	self_modulate = Color(0.8, 0.8, 0.8)
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
