extends Control

# 属性
var cards: Array = []
var selected_card_index = -1

func _ready() -> void:
	print("========== GameUI 初始化 ==========")

	# 设置背景
	var bg = ColorRect.new()
	bg.color = Color(0.15, 0.15, 0.15, 1.0)
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
	style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	card_panel.add_theme_stylebox_override("panel", style)
	card_panel.position = Vector2(20, 400)
	card_panel.custom_minimum_size = Vector2(1160, 200)
	add_child(card_panel)

	# 创建13张卡牌
	var test_cards = [
		"万1", "万2", "万3",
		"筒4", "筒5", "筒6",
		"条7", "条8", "条9",
		"字1", "万5", "筒2", "条4"
	]

	for i in range(test_cards.size()):
		var card_label = Label.new()
		card_label.text = test_cards[i]
		card_label.add_theme_font_size_override("font_size", 16)
		card_label.modulate = Color.WHITE

		# 设置位置（手动排列）
		var x_pos = 30 + (i * 85)
		var y_pos = 420
		card_label.position = Vector2(x_pos, y_pos)
		card_label.custom_minimum_size = Vector2(70, 150)
		card_label.alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		# 鼠标检测
		card_label.mouse_filter = Control.MOUSE_FILTER_STOP

		add_child(card_label)
		cards.append(card_label)

		# 连接鼠标事件
		card_label.gui_input.connect(_on_card_clicked.bind(i))

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

	print("✓ 按钮已创建")

func _on_card_clicked(event: InputEvent, index: int) -> void:
	"""卡牌被点击"""
	if event is InputEventMouseButton and event.pressed:
		select_card(index)

func select_card(index: int) -> void:
	"""选中卡牌"""
	if index >= 0 and index < cards.size():
		# 取消前一个
		if selected_card_index >= 0 and selected_card_index < cards.size():
			cards[selected_card_index].modulate = Color.WHITE

		# 选中新卡
		selected_card_index = index
		cards[index].modulate = Color.YELLOW
		print("✓ 选中卡牌: ", cards[index].text)

func _on_play_card_pressed() -> void:
	"""出牌按钮"""
	if selected_card_index >= 0 and selected_card_index < cards.size():
		var card_text = cards[selected_card_index].text
		print("✓ 出牌: ", card_text)
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
		cards[selected_card_index].modulate = Color.WHITE
	selected_card_index = -1
