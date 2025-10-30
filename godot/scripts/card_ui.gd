## 卡牌UI显示脚本
## 负责显示单个卡牌的视觉表现，使用真实的麻将牌纹理
class_name CardUI
extends Control

## 卡牌数据
var card_data: CardData
var is_selected: bool = false
var is_highlighted: bool = false

## UI配置
var card_width: float = 80.0
var card_height: float = 120.0

## 纹理缓存
var tile_textures: Dictionary = {}
var back_texture: Texture2D = null

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
	
	# 加载纹理
	_load_textures()

## 加载所有麻将牌纹理
func _load_textures() -> void:
	var base_path = "res://assets/mahjong_tiles/"
	
	# 尝试加载单独的牌文件
	var tile_names = []
	for i in range(1, 10):
		tile_names.append(str(i) + "w")
		tile_names.append(str(i) + "t")
		tile_names.append(str(i) + "s")
	tile_names.append_array(["e", "s", "w", "n", "c", "f", "b"])
	
	for name in tile_names:
		var path = base_path + name + ".png"
		if ResourceLoader.exists(path):
			tile_textures[name] = load(path)
		else:
			# 如果单独文件不存在，尝试从图集加载
			var atlas_path = base_path + "mahjong_atlas0.png"
			if ResourceLoader.exists(atlas_path):
				tile_textures[name] = load(atlas_path)
	
	# 加载背面
	var back_path = base_path + "back.png"
	if ResourceLoader.exists(back_path):
		back_texture = load(back_path)

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
	# 获取卡牌对应的纹理
	var texture = _get_tile_texture()
	
	if texture:
		# 绘制纹理
		draw_set_transform(Vector2.ZERO, 0, Vector2(1, 1))
		draw_texture(texture, Vector2.ZERO)
	else:
		# 如果没有纹理，绘制降级方案（白色背景）
		draw_rect(rect, Color(0.98, 0.98, 0.95))
		draw_rect(rect, Color(0.3, 0.3, 0.3), false, 2)

## 获取卡牌对应的纹理
func _get_tile_texture() -> Texture2D:
	if not card_data:
		return null
	
	# 根据卡牌信息生成纹理键名
	var key = ""
	match card_data.suit:
		CardData.Suit.WAN:
			key = str(card_data.number) + "w"
		CardData.Suit.TONG:
			key = str(card_data.number) + "t"
		CardData.Suit.TIAO:
			key = str(card_data.number) + "s"
		CardData.Suit.ZI:
			match card_data.number:
				1: key = "e"
				2: key = "s"
				3: key = "w"
				4: key = "n"
				5: key = "c"
				6: key = "f"
				7: key = "b"
	
	if key in tile_textures:
		return tile_textures[key]
	
	return null

## 绘制卡牌背面
func _draw_card_back(rect: Rect2) -> void:
	if back_texture:
		draw_set_transform(Vector2.ZERO, 0, Vector2(1, 1))
		draw_texture(back_texture, Vector2.ZERO)
	else:
		# 降级方案：绘制绿色背景
		draw_rect(rect, Color(0.3, 0.5, 0.3))
		draw_rect(rect, Color(0.2, 0.2, 0.2), false, 2)

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
