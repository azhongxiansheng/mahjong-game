extends Control

# 属性
var cards: Array = []
var selected_card_index = -1

func _ready() -> void:
	print("========== GameUI 初始化 ==========")

	# 设置Node大小和位置
	custom_minimum_size = Vector2(1200, 800)
	anchor_right = 1.0
	anchor_bottom = 1.0

	# 设置背景
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 1.0)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	move_child(bg, 0)
	print("✓ 背景已添加")

	# 创建卡牌显示区域
	create_card_display()

	# 创建按钮区域
	create_buttons()

	print("========== GameUI 初始化完成 ==========")

func create_card_display() -> void:
	"""创建卡牌显示区域"""
	var card_panel = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	card_panel.add_theme_stylebox_override("panel", style)
	card_panel.position = Vector2(20, 350)
	card_panel.custom_minimum_size = Vector2(1160, 250)
	add_child(card_panel)

	# 创建13张卡牌
	var test_cards = [
		{"suit": "万", "number": "1"},
		{"suit": "万", "number": "2"},
		{"suit": "万", "number": "3"},
		{"suit": "筒", "number": "4"},
		{"suit": "筒", "number": "5"},
		{"suit": "筒", "number": "6"},
		{"suit": "条", "number": "7"},
		{"suit": "条", "number": "8"},
		{"suit": "条", "number": "9"},
		{"suit": "字", "number": "1"},
		{"suit": "万", "number": "5"},
		{"suit": "筒", "number": "2"},
		{"suit": "条", "number": "4"},
	]

	for i in range(test_cards.size()):
		var card_data = test_cards[i]

		# 创建卡牌容器（Panel作为卡牌背景）
		var card_container = Panel.new()
		var card_style = StyleBoxFlat.new()
		card_style.bg_color = Color(0.85, 0.8, 0.7, 1.0)  # 象牙色
		card_style.border_color = Color(0.3, 0.2, 0.1, 1.0)  # 深色边框
		# 设置四条边的宽度
		card_style.border_width_left = 2
		card_style.border_width_top = 2
		card_style.border_width_right = 2
		card_style.border_width_bottom = 2
		# 设置四个圆角
		card_style.corner_radius_top_left = 3
		card_style.corner_radius_top_right = 3
		card_style.corner_radius_bottom_right = 3
		card_style.corner_radius_bottom_left = 3
		card_container.add_theme_stylebox_override("panel", card_style)

		# 设置卡牌大小和位置
		var x_pos = 30 + (i * 85)
		var y_pos = 370
		card_container.position = Vector2(x_pos, y_pos)
		card_container.custom_minimum_size = Vector2(75, 145)
		card_container.mouse_filter = Control.MOUSE_FILTER_STOP

		add_child(card_container)

		# 创建卡牌内容
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.anchor_right = 1.0
		vbox.anchor_bottom = 1.0
		vbox.offset_top = 5
		vbox.offset_bottom = -5
		vbox.offset_left = 5
		vbox.offset_right = -5
		card_container.add_child(vbox)

		# 花色标签（上方）
		var suit_label = Label.new()
		suit_label.text = card_data.suit
		suit_label.add_theme_font_size_override("font_size", 12)
		suit_label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2, 1.0))
		suit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		suit_label.custom_minimum_size = Vector2(65, 25)
		vbox.add_child(suit_label)

		# 数字标签（中间）
		var number_label = Label.new()
		number_label.text = card_data.number
		number_label.add_theme_font_size_override("font_size", 32)
		number_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1, 1.0))
		number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number_label.custom_minimum_size = Vector2(65, 50)
		vbox.add_child(number_label)

		# 花色标签（下方）
		var suit_label_bottom = Label.new()
		suit_label_bottom.text = card_data.suit
		suit_label_bottom.add_theme_font_size_override("font_size", 12)
		suit_label_bottom.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2, 1.0))
		suit_label_bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		suit_label_bottom.custom_minimum_size = Vector2(65, 25)
		vbox.add_child(suit_label_bottom)

		# 连接鼠标事件
		card_container.gui_input.connect(_on_card_clicked.bind(i, card_container))

		cards.append(card_container)

		print("✓ 添加卡牌: ", card_data.suit, card_data.number, " 位置: (", x_pos, ", ", y_pos, ")")

	print("✓ 已添加 ", cards.size(), " 张卡牌")

func create_buttons() -> void:
	"""创建操作按钮"""
	var button_data = [
		{"text": "出牌", "callback": "_on_play_card_pressed"},
		{"text": "胡", "callback": "_on_win_pressed"},
		{"text": "不要", "callback": "_on_pass_pressed"},
		{"text": "取消", "callback": "_on_cancel_pressed"}
	]

	for i in range(button_data.size()):
		var btn = Button.new()
		btn.text = button_data[i].text
		btn.custom_minimum_size = Vector2(200, 50)
		btn.position = Vector2(50 + (i * 220), 650)

		# 连接信号
		var callback_name = button_data[i].callback
		btn.pressed.connect(Callable(self, callback_name))

		add_child(btn)
		print("✓ 创建按钮: ", button_data[i].text)

	print("✓ 按钮已创建")

func _on_card_clicked(event: InputEvent, index: int, card_container: Panel) -> void:
	"""卡牌被点击"""
	if event is InputEventMouseButton and event.pressed:
		select_card(index, card_container)

func select_card(index: int, card_container: Panel) -> void:
	"""选中卡牌"""
	if index >= 0 and index < cards.size():
		# 取消前一个
		if selected_card_index >= 0 and selected_card_index < cards.size():
			var old_style = StyleBoxFlat.new()
			old_style.bg_color = Color(0.85, 0.8, 0.7, 1.0)  # 象牙色
			old_style.border_color = Color(0.3, 0.2, 0.1, 1.0)
			old_style.border_width_left = 2
			old_style.border_width_top = 2
			old_style.border_width_right = 2
			old_style.border_width_bottom = 2
			old_style.corner_radius_top_left = 3
			old_style.corner_radius_top_right = 3
			old_style.corner_radius_bottom_right = 3
			old_style.corner_radius_bottom_left = 3
			cards[selected_card_index].add_theme_stylebox_override("panel", old_style)

		# 选中新卡
		selected_card_index = index
		var new_style = StyleBoxFlat.new()
		new_style.bg_color = Color(1.0, 0.95, 0.5, 1.0)  # 高亮黄色
		new_style.border_color = Color(1.0, 0.8, 0.0, 1.0)  # 金色边框
		new_style.border_width_left = 3
		new_style.border_width_top = 3
		new_style.border_width_right = 3
		new_style.border_width_bottom = 3
		new_style.corner_radius_top_left = 3
		new_style.corner_radius_top_right = 3
		new_style.corner_radius_bottom_right = 3
		new_style.corner_radius_bottom_left = 3
		card_container.add_theme_stylebox_override("panel", new_style)
		print("✓ 选中卡牌: ", index)

func _on_play_card_pressed() -> void:
	"""出牌按钮"""
	if selected_card_index >= 0 and selected_card_index < cards.size():
		print("✓ 出牌: 卡牌 ", selected_card_index)
		cards[selected_card_index].queue_free()
		cards.remove_at(selected_card_index)
		selected_card_index = -1
	else:
		print("⚠ 请先选择一张卡牌")

func _on_win_pressed() -> void:
	"""胡牌按钮"""
	print("✓ 胡牌!")

func _on_pass_pressed() -> void:
	"""不要按钮"""
	print("✓ 不要")

func _on_cancel_pressed() -> void:
	"""取消按钮"""
	print("✓ 取消操作")
	if selected_card_index >= 0 and selected_card_index < cards.size():
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.85, 0.8, 0.7, 1.0)  # 象牙色
		style.border_color = Color(0.3, 0.2, 0.1, 1.0)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.corner_radius_top_left = 3
		style.corner_radius_top_right = 3
		style.corner_radius_bottom_right = 3
		style.corner_radius_bottom_left = 3
		cards[selected_card_index].add_theme_stylebox_override("panel", style)
	selected_card_index = -1
