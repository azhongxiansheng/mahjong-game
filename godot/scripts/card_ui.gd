## 卡牌UI显示脚本
## 负责显示单个卡牌的视觉表现，包括卡牌正面、背面和交互反馈
class_name CardUI
extends Control

## 卡牌数据
var card_data: CardData
var is_selected: bool = false
var is_highlighted: bool = false

## UI配置
var card_width: float = 60.0
var card_height: float = 90.0
var corner_radius: float = 4.0

## 颜色配置
var color_wan: Color = Color(0.2, 0.4, 0.8) # 万牌 - 蓝色
var color_tong: Color = Color(0.8, 0.5, 0.2) # 筒牌 - 橙色
var color_tiao: Color = Color(0.2, 0.7, 0.3) # 条牌 - 绿色
var color_letter: Color = Color(0.7, 0.2, 0.3) # 字牌 - 红色
var color_bg: Color = Color(0.95, 0.95, 0.95) # 背景 - 白色

## 状态
var show_face: bool = true # true=正面, false=背面

## 信号
signal card_clicked(card_ui: CardUI)
signal card_hovered(card_ui: CardUI)
signal card_unhovered(card_ui: CardUI)

func _ready() -> void:
	custom_minimum_size = Vector2(card_width, card_height)
	mouse_filter = MOUSE_FILTER_STOP

	# 连接鼠标事件
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

## 设置卡牌数据
func set_card(card: CardData) -> void:
	card_data = card
	queue_redraw()

## 设置是否显示正面
func set_show_face(show_face_flag: bool) -> void:
	show_face = show_face_flag
	queue_redraw()

## 选中卡牌
func set_selected(selected: bool) -> void:
	is_selected = selected
	queue_redraw()

## 高亮卡牌
func set_highlighted(highlighted: bool) -> void:
	is_highlighted = highlighted
	queue_redraw()

## 绘制卡牌
func _draw() -> void:
	if not card_data:
		return

	var rect = Rect2(Vector2.ZERO, custom_minimum_size)

	# 绘制卡牌背景
	_draw_card_background(rect)

	if show_face:
		# 绘制卡牌正面
		_draw_card_face(rect)
	else:
		# 绘制卡牌背面
		_draw_card_back(rect)

	# 绘制选中/高亮边框
	_draw_card_border(rect)

## 绘制卡牌背景
func _draw_card_background(rect: Rect2) -> void:
	var bg_color = color_bg

	if is_selected:
		bg_color = bg_color.darkened(0.3)
	elif is_highlighted:
		bg_color = bg_color.brightened(0.2)

	draw_rect(rect, bg_color)

## 绘制卡牌正面
func _draw_card_face(rect: Rect2) -> void:
	# 根据花色获取颜色
	var suit_color = _get_suit_color()

	# 绘制顶部数字/名称
	var display_name = card_data.get_display_name()
	draw_card_text(display_name, Vector2(8, 15), suit_color)

	# 绘制中间大符号
	_draw_card_symbol(rect, suit_color)

	# 绘制底部倒置的数字
	draw_card_text(display_name, Vector2(rect.size.x - 35, rect.size.y - 10), suit_color)

## 绘制卡牌背面
func _draw_card_back(rect: Rect2) -> void:
	# 绘制棋盘图案
	var pattern_color = Color(0.3, 0.3, 0.5)
	var square_size = 6

	for x in range(0, int(rect.size.x), square_size * 2):
		for y in range(0, int(rect.size.y), square_size * 2):
			if (int(x / square_size) + int(y / square_size)) % 2 == 0:
				draw_rect(Rect2(x, y, square_size, square_size), pattern_color)

	# 绘制中间文字 "麻将"
	var center = rect.get_center()
	draw_card_text("麻", center - Vector2(12, 8), Color.WHITE)
	draw_card_text("将", center + Vector2(8, -8), Color.WHITE)

## 绘制卡牌符号（中间图案）
func _draw_card_symbol(rect: Rect2, color: Color) -> void:
	var center = rect.get_center()
	var symbol_size = 20

	# 根据花色绘制不同符号
	match card_data.suit:
		CardData.Suit.WAN:
			# 万牌 - 绘制圆形
			draw_circle(center, symbol_size * 0.6, color)
		CardData.Suit.TONG:
			# 筒牌 - 绘制方形
			draw_rect(Rect2(center - Vector2(symbol_size * 0.5, symbol_size * 0.5), Vector2(symbol_size, symbol_size)), color)
		CardData.Suit.TIAO:
			# 条牌 - 绘制竖条纹
			for i in range(5):
				draw_line(center + Vector2(-symbol_size * 0.4 + i * symbol_size * 0.2, -symbol_size * 0.5),
						center + Vector2(-symbol_size * 0.4 + i * symbol_size * 0.2, symbol_size * 0.5), color, 2)
		CardData.Suit.ZI:
			# 字牌 - 绘制中文字
			draw_card_text(_get_letter_name(), center - Vector2(8, 8), color)

## 绘制卡牌边框
func _draw_card_border(rect: Rect2) -> void:
	var border_color = Color.GRAY
	var border_width = 1

	if is_selected:
		border_color = Color.YELLOW
		border_width = 3
	elif is_highlighted:
		border_color = Color.WHITE
		border_width = 2

	draw_rect(rect, border_color, false, border_width)

## 获取花色颜色
func _get_suit_color() -> Color:
	match card_data.suit:
		CardData.Suit.WAN:
			return color_wan
		CardData.Suit.TONG:
			return color_tong
		CardData.Suit.TIAO:
			return color_tiao
		CardData.Suit.ZI:
			return color_letter
		_:
			return Color.BLACK

## 获取字牌名称
func _get_letter_name() -> String:
	match card_data.number:
		1: return "东"
		2: return "南"
		3: return "西"
		4: return "北"
		5: return "中"
		6: return "发"
		7: return "白"
		_: return "?"

## 绘制卡牌文本
func draw_card_text(text: String, pos: Vector2, color: Color) -> void:
	# 简化版本 - 直接绘制字符
	var font = get_theme_font("font")
	var font_size = get_theme_font_size("font_size")

	if font:
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	else:
		# 如果没有主题字体，绘制简单的数字文本
		draw_card_text_simple(text, pos, color, font_size)

## 简单的文字绘制
func draw_card_text_simple(_text: String, _pos: Vector2, _color: Color, _font_size: int = 12) -> void:
	# 这是一个简化实现，使用基础绘制
	# 在实际项目中应该使用主题字体
	pass

## 鼠标进入
func _on_mouse_entered() -> void:
	card_hovered.emit(self)
	queue_redraw()

## 鼠标离开
func _on_mouse_exited() -> void:
	card_unhovered.emit(self)
	queue_redraw()

## GUI输入事件
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_clicked.emit(self)
		is_selected = not is_selected
		queue_redraw()
