## 卡牌UI显示脚本
## 负责显示单个卡牌的视觉表现，包括卡牌正面、背面和交互反馈
class_name CardUI
extends Control

## 卡牌数据
var card_data: CardData
var is_selected: bool = false
var is_highlighted: bool = false

## UI配置
var card_width: float = 80.0
var card_height: float = 100.0
var corner_radius: float = 6.0

## 颜色配置
var color_wan: Color = Color(0.1, 0.3, 0.7) # 万牌 - 深蓝
var color_tong: Color = Color(0.9, 0.6, 0.1) # 筒牌 - 金色
var color_tiao: Color = Color(0.2, 0.6, 0.2) # 条牌 - 绿色
var color_letter: Color = Color(0.8, 0.1, 0.1) # 字牌 - 深红
var color_bg: Color = Color(0.98, 0.98, 0.98) # 背景 - 米白色

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

	# 绘制卡牌背景和阴影
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
	# 绘制阴影效果
	var shadow_color = Color.BLACK
	shadow_color.a = 0.15
	var shadow_rect = rect.grow_side(SIDE_RIGHT, 2).grow_side(SIDE_BOTTOM, 2)
	draw_rect(shadow_rect, shadow_color)

	# 卡牌背景色
	var bg_color = color_bg

	if is_selected:
		bg_color = bg_color.darkened(0.2)
	elif is_highlighted:
		bg_color = bg_color.brightened(0.15)

	# 绘制卡牌主体
	draw_rect(rect, bg_color)
	
	# 绘制内边框（增加立体感）
	draw_rect(rect.grow(-2), Color.WHITE, false, 1)

## 绘制卡牌正面
func _draw_card_face(rect: Rect2) -> void:
	# 根据花色获取颜色
	var suit_color = _get_suit_color()

	# 调整内容区域
	var content_rect = rect.grow(-4)

	# 绘制中间大符号
	_draw_card_symbols(content_rect, suit_color)

	# 绘制顶部角标
	_draw_corner_mark(content_rect, suit_color, true)

	# 绘制底部角标（倒置）
	_draw_corner_mark(content_rect, suit_color, false)

## 绘制角标（数字或汉字）
func _draw_corner_mark(rect: Rect2, suit_color: Color, is_top: bool) -> void:
	var pos = Vector2.ZERO
	if is_top:
		pos = rect.position + Vector2(2, 2)
	else:
		pos = rect.position + rect.size - Vector2(14, 14)

	var display_text = card_data.get_display_name()
	_draw_text_simple(display_text, pos, suit_color, 8)

## 绘制卡牌符号（中间图案）
func _draw_card_symbols(rect: Rect2, color: Color) -> void:
	var center = rect.get_center()

	# 根据花色绘制不同符号
	match card_data.suit:
		CardData.Suit.WAN:
			# 万牌 - 绘制"万"字
			_draw_text_simple("万", center - Vector2(12, 15), color, 24)
		CardData.Suit.TONG:
			# 筒牌 - 绘制圆形组合
			_draw_tong_symbols(center, color, card_data.number)
		CardData.Suit.TIAO:
			# 条牌 - 绘制竖条纹
			_draw_tiao_symbols(center, color, card_data.number)
		CardData.Suit.ZI:
			# 字牌 - 绘制大汉字
			_draw_text_simple(_get_letter_name(), center - Vector2(14, 18), color, 32)

## 绘制筒牌符号（圆形组合）
func _draw_tong_symbols(center: Vector2, color: Color, number: int) -> void:
	var circle_size = 6.0
	var positions = []

	# 根据数字显示不同的圆形排列
	match number:
		1:
			positions = [Vector2(0, 0)]
		2:
			positions = [Vector2(-8, -6), Vector2(8, 6)]
		3:
			positions = [Vector2(-8, -6), Vector2(0, 0), Vector2(8, 6)]
		4:
			positions = [Vector2(-8, -8), Vector2(8, -8), Vector2(-8, 8), Vector2(8, 8)]
		5:
			positions = [Vector2(-8, -8), Vector2(8, -8), Vector2(0, 0), Vector2(-8, 8), Vector2(8, 8)]
		6:
			positions = [Vector2(-10, -8), Vector2(0, -8), Vector2(10, -8), Vector2(-10, 8), Vector2(0, 8), Vector2(10, 8)]
		7:
			positions = [Vector2(-10, -8), Vector2(0, -8), Vector2(10, -8), Vector2(-5, 0), Vector2(5, 0), Vector2(-10, 8), Vector2(10, 8)]
		8:
			positions = [Vector2(-10, -8), Vector2(0, -8), Vector2(10, -8), Vector2(-10, 0), Vector2(10, 0), Vector2(-10, 8), Vector2(0, 8), Vector2(10, 8)]
		9:
			positions = [Vector2(-10, -8), Vector2(0, -8), Vector2(10, -8), Vector2(-10, 0), Vector2(0, 0), Vector2(10, 0), Vector2(-10, 8), Vector2(0, 8), Vector2(10, 8)]

	for pos in positions:
		draw_circle(center + pos, circle_size, color)

## 绘制条牌符号（竖条）
func _draw_tiao_symbols(center: Vector2, color: Color, number: int) -> void:
	var line_height = 24.0
	var line_width = 2.0
	var spacing = 6.0

	match number:
		1:
			draw_line(center - Vector2(0, line_height / 2), center + Vector2(0, line_height / 2), color, line_width)
		2:
			draw_line(center - Vector2(spacing / 2, line_height / 2), center - Vector2(spacing / 2, -line_height / 2), color, line_width)
			draw_line(center + Vector2(spacing / 2, line_height / 2), center + Vector2(spacing / 2, -line_height / 2), color, line_width)
		_:
			# 3-9条显示多条竖线
			var start_x = center.x - (number - 1) * spacing / 2.0
			for i in range(number):
				var x = start_x + i * spacing
				draw_line(Vector2(x, center.y - line_height / 2), Vector2(x, center.y + line_height / 2), color, line_width)

## 绘制卡牌背面
func _draw_card_back(rect: Rect2) -> void:
	# 绘制棋盘图案
	var pattern_color = Color(0.3, 0.3, 0.5)
	pattern_color.a = 0.3
	var square_size = 8

	for x in range(0, int(rect.size.x), square_size * 2):
		for y in range(0, int(rect.size.y), square_size * 2):
			if (int(float(x) / float(square_size)) + int(float(y) / float(square_size))) % 2 == 0:
				draw_rect(Rect2(x, y, square_size, square_size), pattern_color)

	# 绘制中间文字 "麻将"
	var center = rect.get_center()
	_draw_text_simple("麻", center - Vector2(16, 12), Color(0.3, 0.3, 0.3), 18)
	_draw_text_simple("将", center + Vector2(4, 12), Color(0.3, 0.3, 0.3), 18)

## 绘制卡牌边框
func _draw_card_border(rect: Rect2) -> void:
	var border_color = Color.GRAY
	border_color.a = 0.4
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

## 简单文字绘制（使用draw_char或draw_string）
func _draw_text_simple(text: String, pos: Vector2, color: Color, font_size: int) -> void:
	# 使用更简单的方式绘制文字
	# 这是一个基础实现，直接在指定位置绘制
	var offset = 0
	for char in text:
		var char_str = char
		# 绘制单个字符（颜色、大小固定）
		draw_string(ThemeDB.fallback_font, pos + Vector2(offset, 0), char_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		offset += font_size / 2

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
