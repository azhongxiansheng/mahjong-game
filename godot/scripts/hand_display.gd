class_name HandDisplay
extends Control

# 属性
var cards: Array = []
var card_scenes: Array = []
var selected_card = null
var card_start_x = 20
var card_spacing = 70
var card_y = 35

func _ready() -> void:
	print("HandDisplay初始化完成")

	# 设置背景
	var panel = Panel.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 1.0)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	add_child(panel)
	move_child(panel, 0)

	# 创建测试卡牌
	create_test_cards()

func create_test_cards() -> void:
	"""创建13张测试卡牌"""
	# 测试卡牌数据
	var test_cards = [
		{"suit": 0, "number": 1},  # 万1
		{"suit": 0, "number": 2},  # 万2
		{"suit": 0, "number": 3},  # 万3
		{"suit": 1, "number": 4},  # 筒4
		{"suit": 1, "number": 5},  # 筒5
		{"suit": 1, "number": 6},  # 筒6
		{"suit": 2, "number": 7},  # 条7
		{"suit": 2, "number": 8},  # 条8
		{"suit": 2, "number": 9},  # 条9
		{"suit": 3, "number": 1},  # 字1
		{"suit": 0, "number": 5},  # 万5
		{"suit": 1, "number": 2},  # 筒2
		{"suit": 2, "number": 4},  # 条4
	]

	# 为每个卡牌创建一个Label来显示
	for i in range(test_cards.size()):
		var card_info = test_cards[i]
		var card_label = Label.new()

		# 设置卡牌显示
		var suit_name = get_suit_name(card_info.suit)
		card_label.text = suit_name + str(card_info.number)
		card_label.add_theme_font_size_override("font_size", 14)

		# 设置位置和大小
		var x_pos = card_start_x + (i * card_spacing)
		card_label.position = Vector2(x_pos, card_y)
		card_label.custom_minimum_size = Vector2(60, 80)
		card_label.alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		# 添加到场景
		add_child(card_label)
		cards.append(card_label)
		card_scenes.append(card_info)

		print("添加卡牌: ", suit_name, card_info.number)

func get_suit_name(suit: int) -> String:
	"""获取花色名称"""
	match suit:
		0: return "万"
		1: return "筒"
		2: return "条"
		3: return "字"
	return ""

func add_card(suit: int, number: int) -> void:
	"""添加卡牌"""
	var card_label = Label.new()
	var suit_name = get_suit_name(suit)
	card_label.text = suit_name + str(number)
	card_label.custom_minimum_size = Vector2(60, 80)
	card_label.alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var x_pos = card_start_x + (cards.size() * card_spacing)
	card_label.position = Vector2(x_pos, card_y)

	add_child(card_label)
	cards.append(card_label)
	card_scenes.append({"suit": suit, "number": number})
	print("添加卡牌: ", suit_name, number)

func remove_card_at(index: int) -> void:
	"""移除指定索引的卡牌"""
	if index >= 0 and index < cards.size():
		var card = cards[index]
		card.queue_free()
		cards.remove_at(index)
		card_scenes.remove_at(index)
		print("移除卡牌在索引: ", index)

func select_card(index: int) -> void:
	"""选中指定索引的卡牌"""
	if index >= 0 and index < cards.size():
		# 取消前一个选中
		if selected_card != null:
			selected_card.modulate = Color.WHITE

		# 选中新卡牌
		selected_card = cards[index]
		selected_card.modulate = Color.YELLOW
		print("选中卡牌: ", card_scenes[index].suit, " - ", card_scenes[index].number)

func deselect_all() -> void:
	"""取消选中所有卡牌"""
	if selected_card != null:
		selected_card.modulate = Color.WHITE
		selected_card = null
	print("已取消选中")

func get_card_count() -> int:
	"""获取手牌数量"""
	return cards.size()

func clear_hand() -> void:
	"""清空手牌"""
	for card in cards:
		card.queue_free()
	cards.clear()
	card_scenes.clear()
	selected_card = null
	print("已清空手牌")
