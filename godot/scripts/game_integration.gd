class_name GameIntegration
extends Node

# 引用
var game_ui: Control
var game_controller
var game_state
var card_hand

# 属性
var current_hand: Array = []
var is_game_running: bool = false

func _ready() -> void:
	print("========== 游戏集成初始化 ==========")

	# 获取UI引用
	game_ui = get_tree().root.get_child(0).get_node("GameUI") if has_node("/root/Main/GameUI") else null

	if game_ui:
		print("✓ GameUI引用已获取")
	else:
		print("⚠ GameUI节点未找到")

	print("========== 游戏集成准备就绪 ==========")

func start_game() -> void:
	"""启动游戏"""
	is_game_running = true
	print("✓ 游戏已启动")

	# 初始化手牌（13张）
	initialize_hand()

	# 发送第一个抽卡信号
	draw_card()

func initialize_hand() -> void:
	"""初始化手牌"""
	current_hand = []

	# 创建13张初始卡牌
	var suits = ["万", "筒", "条", "字"]
	var card_count = 0

	for suit_idx in range(4):
		for num in range(1, 10):
			if card_count < 13:
				var card_data = {
					"suit": suits[suit_idx],
					"number": num,
					"id": card_count
				}
				current_hand.append(card_data)
				card_count += 1
			else:
				break
		if card_count >= 13:
			break

	print("✓ 初始手牌已创建: ", current_hand.size(), " 张卡牌")
	update_ui_hand()

func draw_card() -> void:
	"""抽一张卡牌"""
	if current_hand.size() < 14:
		var new_card = {
			"suit": ["万", "筒", "条", "字"][randi() % 4],
			"number": (randi() % 9) + 1,
			"id": current_hand.size()
		}
		current_hand.append(new_card)
		print("✓ 抽卡: ", new_card.suit, new_card.number)
		update_ui_hand()
	else:
		print("⚠ 手牌已满 (14张)")

func play_card(card_index: int) -> void:
	"""出牌"""
	if card_index >= 0 and card_index < current_hand.size():
		var card = current_hand[card_index]
		print("✓ 出牌: ", card.suit, card.number)
		current_hand.remove_at(card_index)
		update_ui_hand()

		# 检查是否胡牌
		check_win()
	else:
		print("⚠ 无效的卡牌索引")

func check_win() -> void:
	"""检查是否胡牌（简化版）"""
	if current_hand.size() == 0:
		print("✓ 胡牌! 恭喜!")
		is_game_running = false
		show_win_message()
	else:
		# 自动抽卡
		await get_tree().create_timer(0.5).timeout
		draw_card()

func update_ui_hand() -> void:
	"""更新UI显示的手牌"""
	if game_ui:
		# 清空旧卡牌
		for card in game_ui.cards:
			card.queue_free()
		game_ui.cards.clear()

		# 添加新卡牌
		for i in range(current_hand.size()):
			var card_data = current_hand[i]
			var card_label = Label.new()

			card_label.text = card_data.suit + str(card_data.number)
			card_label.add_theme_font_size_override("font_size", 16)
			card_label.modulate = Color.WHITE

			# 设置位置
			var x_pos = 30 + (i * 85)
			var y_pos = 420
			card_label.position = Vector2(x_pos, y_pos)
			card_label.custom_minimum_size = Vector2(70, 150)
			card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			card_label.mouse_filter = Control.MOUSE_FILTER_STOP

			game_ui.add_child(card_label)
			game_ui.cards.append(card_label)

			# 连接鼠标事件
			card_label.gui_input.connect(game_ui._on_card_clicked.bind(i))
			card_label.mouse_entered.connect(game_ui._on_card_hover.bind(i))
			card_label.mouse_exited.connect(game_ui._on_card_unhover.bind(i))

		print("✓ UI手牌已更新: ", current_hand.size(), " 张卡牌")

func show_win_message() -> void:
	"""显示胡牌信息"""
	print("\n")
	print("╔════════════════════╗")
	print("║   🎉 恭喜胡牌! 🎉  ║")
	print("╚════════════════════╝")
	print("\n")

func get_hand_info() -> String:
	"""获取手牌信息"""
	var info = "当前手牌: "
	for card in current_hand:
		info += card.suit + str(card.number) + " "
	return info

func reset_game() -> void:
	"""重置游戏"""
	current_hand.clear()
	is_game_running = false
	print("✓ 游戏已重置")
