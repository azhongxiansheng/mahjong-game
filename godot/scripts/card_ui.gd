## 卡牌UI显示脚本
## 负责显示单个卡牌的视觉表现，包括卡牌正面、背面和交互反馈
class_name CardUI
extends Control

## 卡牌数据
var card_data: CardData
var is_selected: bool = false
var is_highlighted: bool = false

## UI配置
var card_width: float = 70.0
var card_height: float = 95.0
var corner_radius: float = 3.0

## 颜色配置
var color_wan: Color = Color(0.2, 0.5, 0.2) # 万牌 - 绿色
var color_tong: Color = Color(0.8, 0.4, 0.1) # 筒牌 - 橙/红色
var color_tiao: Color = Color(0.2, 0.6, 0.2) # 条牌 - 绿色
var color_letter: Color = Color(0.8, 0.1, 0.1) # 字牌 - 红色
var color_bg: Color = Color(0.98, 0.98, 0.95) # 背景 - 象牙白
var color_border: Color = Color(0.3, 0.3, 0.3) # 边框 - 深灰

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

	if show_face:
		# 绘制卡牌正面
		_draw_card_face(rect)
	else:
		# 绘制卡牌背面
		_draw_card_back(rect)

	# 绘制选中/高亮边框
	_draw_card_border(rect)

## 绘制卡牌正面
func _draw_card_face(rect: Rect2) -> void:
	# 绘制背景
	draw_rect(rect, color_bg)
	
	# 获取花色颜色
	var suit_color = _get_suit_color()
	
	# 绘制中间符号
	var content_rect = rect.grow(-3)
	_draw_card_symbols(content_rect, suit_color)

## 绘制卡牌符号
func _draw_card_symbols(rect: Rect2, color: Color) -> void:
	var center = rect.get_center()
	
	# 根据花色绘制不同符号
	match card_data.suit:
		CardData.Suit.WAN:
			# 万牌 - 绘制"万"字
			_draw_large_text("万", center, color, 36)
		CardData.Suit.TONG:
			# 筒牌 - 绘制圆形组合
			_draw_tong_pattern(center, card_data.number)
		CardData.Suit.TIAO:
			# 条牌 - 绘制竖条纹
			_draw_tiao_pattern(center, card_data.number)
		CardData.Suit.ZI:
			# 字牌 - 绘制大汉字
			_draw_large_text(_get_letter_name(), center, color, 40)

## 绘制筒牌图案（圆形组合）
func _draw_tong_pattern(center: Vector2, number: int) -> void:
	# 筒牌风格：圆形排列
	# 红色圆形在中间，绿色圆形在外围
	var positions = []
	
	match number:
		1:
			positions = [Vector2(0, 0)]
		2:
			positions = [Vector2(-10, 0), Vector2(10, 0)]
		3:
			positions = [Vector2(-10, -8), Vector2(0, 0), Vector2(10, 8)]
		4:
			positions = [Vector2(-10, -8), Vector2(10, -8), Vector2(-10, 8), Vector2(10, 8)]
		5:
			positions = [Vector2(-10, -10), Vector2(10, -10), Vector2(0, 0), Vector2(-10, 10), Vector2(10, 10)]
		6:
			positions = [Vector2(-12, -10), Vector2(0, -10), Vector2(12, -10), Vector2(-12, 10), Vector2(0, 10), Vector2(12, 10)]
		7:
			positions = [Vector2(-12, -10), Vector2(0, -10), Vector2(12, -10), Vector2(-6, 0), Vector2(6, 0), Vector2(-12, 10), Vector2(12, 10)]
		8:
			positions = [Vector2(-12, -10), Vector2(0, -10), Vector2(12, -10), Vector2(-12, 0), Vector2(12, 0), Vector2(-12, 10), Vector2(0, 10), Vector2(12, 10)]
		9:
			positions = [Vector2(-12, -10), Vector2(0, -10), Vector2(12, -10), Vector2(-12, 0), Vector2(0, 0), Vector2(12, 0), Vector2(-12, 10), Vector2(0, 10), Vector2(12, 10)]
	
	# 绘制圆形
	for i in range(positions.size()):
		var pos = positions[i]
		# 绿色外圆
		draw_circle(center + pos, 6.0, Color(0.2, 0.6, 0.2))
		# 红色内圆
		draw_circle(center + pos, 3.5, Color(0.8, 0.1, 0.1))

## 绘制条牌图案（竖条纹）
func _draw_tiao_pattern(center: Vector2, number: int) -> void:
	var line_height = 30.0
	var line_width = 3.0
	var spacing = 7.0
	var color = Color(0.2, 0.6, 0.2)
	
	match number:
		1:
			draw_line(center + Vector2(0, -line_height/2), center + Vector2(0, line_height/2), color, line_width)
		2:
			draw_line(center + Vector2(-spacing, -line_height/2), center + Vector2(-spacing, line_height/2), color, line_width)
			draw_line(center + Vector2(spacing, -line_height/2), center + Vector2(spacing, line_height/2), color, line_width)
		_:
			# 3-9条显示多条竖线
			var count = number
			var start_x = center.x - (count - 1) * spacing / 2.0
			for i in range(count):
				var x = start_x + i * spacing
				draw_line(Vector2(x, center.y - line_height/2), Vector2(x, center.y + line_height/2), color, line_width)

## 绘制卡牌背面
func _draw_card_back(rect: Rect2) -> void:
	# 绘制背景
	draw_rect(rect, Color(0.3, 0.5, 0.3))
	
	# 绘制棋盘图案
	var pattern_color = Color.WHITE
	pattern_color.a = 0.2
	var square_size = 8

	for x in range(0, int(rect.size.x), square_size * 2):
		for y in range(0, int(rect.size.y), square_size * 2):
			if (int(float(x) / float(square_size)) + int(float(y) / float(square_size))) % 2 == 0:
				draw_rect(Rect2(x, y, square_size, square_size), pattern_color)

	# 绘制中间文字 "麻将"
	var center = rect.get_center()
	_draw_large_text("麻", center - Vector2(10, 8), Color.WHITE, 18)
	_draw_large_text("将", center + Vector2(6, 8), Color.WHITE, 18)

## 绘制卡牌边框
func _draw_card_border(rect: Rect2) -> void:
	var border_color = color_border
	var border_width = 2

	if is_selected:
		border_color = Color.YELLOW
		border_width = 3
	elif is_highlighted:
		border_color = Color(0.7, 0.7, 0.1)
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

## 绘制大文字
func _draw_large_text(text: String, pos: Vector2, color: Color, font_size: int) -> void:
	draw_string(ThemeDB.fallback_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)

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
