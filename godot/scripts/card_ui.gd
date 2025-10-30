## 卡牌UI显示脚本
## 智能模式：优先加载纹理，备选代码绘制
class_name CardUI
extends Control

## 卡牌数据
var card_data: CardData
var is_selected: bool = false
var is_highlighted: bool = false

## UI配置
## 优化：增大卡牌尺寸从 80x120 到 100x150，让纹理显示更清晰
var card_width: float = 100.0
var card_height: float = 150.0

## 🆕 纹理滤波 - 最近邻确保像素完美
var texture_filter_mode = CanvasItem.TEXTURE_FILTER_NEAREST

## 🆕 纹理提取器 - 使用 AutoLoad 单例,不需要类型声明
var texture_extractor
var extractor_tile_texture: Texture2D

## 颜色配置
var color_wan: Color = Color(0.2, 0.5, 0.2) # 万牌 - 绿色
var color_tong: Color = Color(0.8, 0.4, 0.1) # 筒牌 - 橙色
var color_tiao: Color = Color(0.2, 0.6, 0.2) # 条牌 - 绿色
var color_letter: Color = Color(0.8, 0.1, 0.1) # 字牌 - 红色
var color_bg: Color = Color(0.98, 0.98, 0.95) # 背景 - 象牙白

## 纹理系统
var tile_texture: Texture2D = null
var use_texture: bool = false
var texture_path: String = "res://assets/mahjong_tiles/"

## 状态
var show_face: bool = true # true=正面, false=背面

## 信号
signal card_clicked(card_ui: CardUI)
signal card_hovered(card_ui: CardUI)
signal card_unhovered(card_ui: CardUI)

func _ready() -> void:
	custom_minimum_size = Vector2(card_width, card_height)
	mouse_filter = MOUSE_FILTER_STOP

	# 🆕 设置纹理滤波模式(Godot 4.5 的正确方法)
	texture_filter = texture_filter_mode

	# 🆕 修复:使用 AutoLoad 单例访问 TextureExtractor
	if TextureExtractor:
		texture_extractor = TextureExtractor
	else:
		print("⚠️ CardUI 未找到 TextureExtractor")

	# 连接鼠标事件
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

## 尝试加载纹理
func _try_load_texture() -> void:
	if not card_data:
		return

	# 🆕 重点:直接从 TextureExtractor 加载纹理
	if texture_extractor:
		var tile_name = _get_tile_name_for_extractor()
		if not tile_name.is_empty():
			extractor_tile_texture = texture_extractor.get_tile_texture(tile_name)
			if extractor_tile_texture:
				use_texture = true
				var tex_size = extractor_tile_texture.get_size()
				print("✅ [%s] 纹理加载成功 %dx%d" % [tile_name, tex_size.x, tex_size.y])
				return
			else:
				print("❌ [%s] TextureExtractor返回 null (dict size: %d)" % [tile_name, texture_extractor.extracted_tiles.size()])
		else:
			print("❌ tile_name 为空, 卡牌: suit=%s num=%d" % [card_data.suit, card_data.number])
	else:
		print("❌ texture_extractor 为 null")

	# 如果 TextureExtractor 没有纹理,才使用代码绘制
	use_texture = false

## 获取卡牌名称
func _get_tile_name() -> String:
	if not card_data:
		return ""

	match card_data.suit:
		CardData.Suit.WAN:
			return str(card_data.number) + "w"
		CardData.Suit.TONG:
			return str(card_data.number) + "t"
		CardData.Suit.TIAO:
			return str(card_data.number) + "s"
		CardData.Suit.ZI:
			match card_data.number:
				1: return "e"
				2: return "s"
				3: return "w"
				4: return "n"
				5: return "c"
				6: return "f"
				7: return "b"
	return ""

## 设置卡牌数据
func set_card(card: CardData) -> void:
	card_data = card
	# 直接标记为需要尝试加载纹理
	extractor_tile_texture = null
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
		# 🆕 每次绘制时都尝试加载纹理(如果还没加载)
		if not extractor_tile_texture and texture_extractor:
			_try_load_texture()

		if extractor_tile_texture:
			# 🎨 纹理渲染 - 麻将牌80x120,卡牌100x150
			var tex_size = extractor_tile_texture.get_size()
			print("🎨 [_draw] 渲染纹理 %dx%d 到 rect %s" % [tex_size.x, tex_size.y, rect])
			
			# 🔑 关键:先绘制白色背景,确保纹理可见
			draw_rect(rect, Color.WHITE)
			
			# 然后绘制纹理
			draw_texture_rect(extractor_tile_texture, rect, false)
			_draw_card_border(rect)
			return
		else:
			print("⚠️ [_draw] extractor_tile_texture 为 null")

		# 如果没有纹理，绘制背景 + 代码绘制
		var bg_color = color_bg
		if is_selected:
			bg_color = bg_color.darkened(0.2)
		elif is_highlighted:
			bg_color = bg_color.brightened(0.15)
		draw_rect(rect, bg_color)

		if use_texture and tile_texture:
			# 使用纹理
			draw_set_transform(Vector2.ZERO, 0, Vector2(1, 1))
			draw_texture(tile_texture, Vector2.ZERO)
		else:
			# 使用代码绘制
			_draw_card_face(rect)
	else:
		# 绘制卡牌背面
		var bg_color = color_bg
		if is_selected:
			bg_color = bg_color.darkened(0.2)
		elif is_highlighted:
			bg_color = bg_color.brightened(0.15)
		draw_rect(rect, bg_color)
		_draw_card_back(rect)

	# 绘制边框
	_draw_card_border(rect)

## 绘制卡牌正面
func _draw_card_face(rect: Rect2) -> void:
	var suit_color = _get_suit_color()
	var center = rect.get_center()

	# 根据花色绘制不同符号
	match card_data.suit:
		CardData.Suit.WAN:
			# 万牌 - 绘制"万"字
			_draw_large_text("万", center, suit_color, 36)
		CardData.Suit.TONG:
			# 筒牌 - 绘制圆形组合
			_draw_tong_pattern(center, card_data.number)
		CardData.Suit.TIAO:
			# 条牌 - 绘制竖条纹
			_draw_tiao_pattern(center, card_data.number)
		CardData.Suit.ZI:
			# 字牌 - 绘制大汉字
			_draw_large_text(_get_letter_name(), center, suit_color, 40)

## 绘制筒牌图案（圆形组合）
func _draw_tong_pattern(center: Vector2, number: int) -> void:
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
	for pos in positions:
		draw_circle(center + pos, 6.0, Color(0.2, 0.6, 0.2))
		draw_circle(center + pos, 3.5, Color(0.8, 0.1, 0.1))

## 绘制条牌图案（竖条纹）
func _draw_tiao_pattern(center: Vector2, number: int) -> void:
	var line_height = 30.0
	var line_width = 3.0
	var spacing = 7.0
	var color = Color(0.2, 0.6, 0.2)

	match number:
		1:
			draw_line(center + Vector2(0, -line_height / 2), center + Vector2(0, line_height / 2), color, line_width)
		2:
			draw_line(center + Vector2(-spacing, -line_height / 2), center + Vector2(-spacing, line_height / 2), color, line_width)
			draw_line(center + Vector2(spacing, -line_height / 2), center + Vector2(spacing, line_height / 2), color, line_width)
		_:
			# 3-9条显示多条竖线
			var count = number
			var start_x = center.x - (count - 1) * spacing / 2.0
			for i in range(count):
				var x = start_x + i * spacing
				draw_line(Vector2(x, center.y - line_height / 2), Vector2(x, center.y + line_height / 2), color, line_width)

## 绘制卡牌背面
func _draw_card_back(rect: Rect2) -> void:
	# 绘制背景
	draw_rect(rect, Color(0.3, 0.5, 0.3))

	# 绘制中间文字 "麻将"
	var center = rect.get_center()
	_draw_large_text("麻", center - Vector2(10, 8), Color.WHITE, 18)
	_draw_large_text("将", center + Vector2(6, 8), Color.WHITE, 18)

## 绘制卡牌边框
func _draw_card_border(rect: Rect2) -> void:
	var border_color = Color(0.3, 0.3, 0.3)
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

# 🆕 获取 TextureExtractor 使用的麻将牌名称
func _get_tile_name_for_extractor() -> String:
	if not card_data:
		return ""

	match card_data.suit:
		CardData.Suit.WAN:
			return "w%d" % card_data.number
		CardData.Suit.TONG:
			return "t%d" % card_data.number
		CardData.Suit.TIAO:
			return "s%d" % card_data.number
		CardData.Suit.ZI:
			match card_data.number:
				1:
					return "E" # 东
				2:
					return "S" # 南
				3:
					return "W" # 西
				4:
					return "N" # 北
				5:
					return "Z" # 中
				6:
					return "F" # 发
				7:
					return "B" # 白
				_:
					return ""
		_:
			return ""
