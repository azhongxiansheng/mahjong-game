class_name GameUI
extends ScreenBase

# 组件引用 - 不使用 @onready，改为显式初始化
var player_hand_display: Control = null
var opponent_hand_display: Control = null
var discard_pile: Control = null
var game_info: Label = null
var player_stats: Label = null
var game_log: RichTextLabel = null

var hu_button: Button = null
var ting_button: Button = null
var peng_button: Button = null
var pass_button: Button = null
var quit_button: Button = null

# 游戏状态
var game_controller: GameController
var current_hand: CardHand
var discard_cards: Array[CardData] = []

# 信号
signal card_played(card: CardData)
signal player_action(action: String)

func _ready() -> void:
	var separator = "============================================================"
	print("\n" + separator)
	print("GameUI._ready() 开始 | 时间: %d ms" % [Time.get_ticks_msec()])
	print(separator)

	print("[TRACE] 调用 super()")
	super()
	print("[TRACE] super() 完成")

	print("[TRACE] 调用 _initialize_missing_nodes()")
	_initialize_missing_nodes()
	print("[TRACE] _initialize_missing_nodes() 完成")

	# 延迟 UI 设置到下一帧，完全避免初始化时的问题
	print("[TRACE] 注册 _deferred_setup 到下一帧")
	call_deferred("_deferred_setup")

	print(separator)
	print("GameUI._ready() 完成 | 时间: %d ms" % [Time.get_ticks_msec()])
	print(separator + "\n")

func _initialize_missing_nodes() -> void:
	"""初始化任何失败的 @onready 节点 - 防护性编程"""
	if not player_hand_display:
		player_hand_display = get_node_or_null("GameLayer/TableArea/PlayerHand")
		print("⚠ player_hand_display 从 @onready 重新获取: %s" % ("成功" if player_hand_display else "失败"))

	if not opponent_hand_display:
		opponent_hand_display = get_node_or_null("GameLayer/TableArea/OpponentHand")
		print("⚠ opponent_hand_display 从 @onready 重新获取: %s" % ("成功" if opponent_hand_display else "失败"))

	if not player_stats:
		player_stats = get_node_or_null("InfoPanel/PlayerStats")
		print("⚠ player_stats 从 @onready 重新获取: %s" % ("成功" if player_stats else "失败"))

	if not game_log:
		game_log = get_node_or_null("InfoPanel/GameLog")
		print("⚠ game_log 从 @onready 重新获取: %s" % ("成功" if game_log else "失败"))

	if not game_info:
		game_info = get_node_or_null("GameLayer/TableArea/GameCenter/GameInfo")
		print("⚠ game_info 从 @onready 重新获取: %s" % ("成功" if game_info else "失败"))

	if not discard_pile:
		discard_pile = get_node_or_null("GameLayer/TableArea/GameCenter/DiscardPile")
		print("⚠ discard_pile 从 @onready 重新获取: %s" % ("成功" if discard_pile else "失败"))

	if not hu_button:
		hu_button = get_node_or_null("GameLayer/ActionPanel/HuButton")
	if not ting_button:
		ting_button = get_node_or_null("GameLayer/ActionPanel/TingButton")
	if not peng_button:
		peng_button = get_node_or_null("GameLayer/ActionPanel/PengButton")
	if not pass_button:
		pass_button = get_node_or_null("GameLayer/ActionPanel/PassButton")
	if not quit_button:
		quit_button = get_node_or_null("InfoPanel/QuitButton")

func _deferred_setup() -> void:
	"""延迟的 UI 设置"""
	var separator = "============================================================"
	print("\n" + separator)
	print("[DEFERRED] _deferred_setup 开始 | 时间: %d ms" % [Time.get_ticks_msec()])
	print(separator)

	print("[DEFERRED] 调用 setup_ui()")
	setup_ui()
	print("[DEFERRED] setup_ui() 完成")

	print("[DEFERRED] 调用 connect_signals()")
	connect_signals()
	print("[DEFERRED] connect_signals() 完成")

	print("[DEFERRED] 调用 apply_theme()")
	apply_theme()
	print("[DEFERRED] apply_theme() 完成")

	print(separator)
	print("[DEFERRED] _deferred_setup 完成 | 时间: %d ms" % [Time.get_ticks_msec()])
	print(separator + "\n")

func setup_ui() -> void:
	"""设置UI初始状态 - 最安全的版本"""
	print("[SETUP] 开始设置 UI")

	# 验证所有UI组件已初始化
	if not _verify_ui_components():
		print("[SETUP] ⚠ 部分UI组件初始化失败，跳过 setup_ui")
		return

	# 设置初始文本 - 最保守的方法
	try_set_text(player_stats, "等待游戏开始...")
	try_set_text(game_log, "")
	try_set_text(game_info, "游戏信息")

	print("[SETUP] UI 设置完成")

func try_set_text(node: Control, text: String) -> void:
	"""安全地设置文本，捕获所有可能的错误"""
	if not node:
		print("[SETUP] ⚠ 节点为 nil，跳过")
		return

	if node == null:
		print("[SETUP] ⚠ 节点明确为 null，跳过")
		return

	var node_name = node.name if node else "unknown"
	print("[SETUP] 尝试设置 %s 的文本为: %s" % [node_name, text])

	# 使用 get_property_list 来验证属性
	var props = node.get_property_list()
	var has_text = false
	for prop in props:
		if prop.name == "text":
			has_text = true
			break

	if not has_text:
		print("[SETUP] ⚠ 节点 %s 没有 text 属性" % node_name)
		return

	# 最后才尝试赋值
	node.text = text
	print("[SETUP] ✓ %s 的文本已设置" % node_name)

func _verify_ui_components() -> bool:
	"""验证所有UI组件是否正确初始化"""
	var all_ok = true

	if not player_hand_display:
		print("⚠ player_hand_display 为空")
		all_ok = false
	if not opponent_hand_display:
		print("⚠ opponent_hand_display 为空")
		all_ok = false
	if not player_stats:
		print("⚠ player_stats 为空")
		all_ok = false
	if not game_log:
		print("⚠ game_log 为空")
		all_ok = false
	if not game_info:
		print("⚠ game_info 为空")
		all_ok = false
	if not discard_pile:
		print("⚠ discard_pile 为空")
		all_ok = false

	return all_ok

func connect_signals() -> void:
	"""连接所有信号"""
	# 连接按钮信号
	if hu_button:
		hu_button.pressed.connect(_on_hu_pressed)
	if ting_button:
		ting_button.pressed.connect(_on_ting_pressed)
	if peng_button:
		peng_button.pressed.connect(_on_peng_pressed)
	if pass_button:
		pass_button.pressed.connect(_on_pass_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

	# 连接手牌显示信号 - 添加安全检查
	if player_hand_display:
		# 验证对象是否是HandDisplay类型
		if player_hand_display is HandDisplay:
			if player_hand_display.has_signal("card_pressed"):
				player_hand_display.card_pressed.connect(_on_card_pressed)
			else:
				print("⚠ HandDisplay没有card_pressed信号")

			if player_hand_display.has_signal("card_selected"):
				player_hand_display.card_selected.connect(_on_card_selected)
			else:
				print("⚠ HandDisplay没有card_selected信号")
		else:
			print("⚠ player_hand_display 不是 HandDisplay 类型，而是: ", player_hand_display.get_class())
	else:
		print("⚠ player_hand_display 为空")

func apply_theme() -> void:
	"""应用主题颜色"""
	# 设置背景颜色
	modulate = Color(0x2C3E50FF)

	# 设置按钮颜色
	if hu_button:
		hu_button.modulate = Color(0xE74C3CFF)
	if ting_button:
		ting_button.modulate = Color(0x27AE60FF)
	if peng_button:
		peng_button.modulate = Color(0x3498DBFF)
	if pass_button:
		pass_button.modulate = Color(0x95A5A6FF)

func display_hand(hand: CardHand) -> void:
	"""显示玩家手牌"""
	current_hand = hand
	if player_hand_display:
		player_hand_display.set_hand(hand)
	update_player_stats()
	if game_log:
		add_log_message("显示手牌: %d张" % hand.get_card_count())
	else:
		print("日志系统未初始化，跳过日志记录")

func add_log_message(message: String) -> void:
	"""添加日志消息 - 安全版本"""
	print("[TRACE] add_log_message 被调用: %s" % message)

	if not game_log:
		print("[WARN] game_log 为 nil，无法添加日志: %s" % message)
		return

	# 分步调试每个操作
	var timestamp = Time.get_ticks_msec() / 1000
	var formatted_msg = "[%.1f] %s" % [timestamp, message]

	print("[TRACE] 准备写入日志: %s" % formatted_msg)

	# 验证游戏日志有必要的属性
	if not game_log.has_property("text"):
		print("[ERROR] game_log 没有 text 属性")
		return

	# 添加文本
	game_log.text += formatted_msg + "\n"
	print("[TRACE] 日志文本已添加")

	# 滚动到底部
	if game_log.get_line_count() > 0:
		game_log.scroll_to_line(game_log.get_line_count() - 1)
		print("[TRACE] 已滚动到日志底部")

func update_player_stats() -> void:
	"""更新玩家统计信息"""
	print("[TRACE] update_player_stats 被调用")

	if not player_stats:
		print("[WARN] player_stats 为 nil")
		return

	if not current_hand:
		print("[WARN] current_hand 为 nil")
		return

	var card_count = current_hand.get_card_count()
	var selected_card = ""

	if player_hand_display and player_hand_display.get_selected_card():
		selected_card = " | 选中: " + player_hand_display.get_selected_card().get_card_name()

	var stats_text = "手牌数: %d%s" % [card_count, selected_card]
	print("[TRACE] 准备设置玩家统计: %s" % stats_text)

	# 验证有text属性
	if not player_stats.has_property("text"):
		print("[ERROR] player_stats 没有 text 属性")
		return

	player_stats.text = stats_text
	print("[TRACE] 玩家统计已设置")

func _on_card_pressed(card: CardData) -> void:
	"""处理卡牌被按下"""
	update_player_stats()
	add_log_message("选中卡牌: %s" % card.get_card_name())

func _on_card_selected(card: CardData) -> void:
	"""处理卡牌被选中"""
	update_player_stats()

func play_card() -> void:
	"""出牌"""
	if not current_hand or not player_hand_display:
		add_log_message("⚠ 无法出牌: 游戏未初始化")
		return

	var card = player_hand_display.get_selected_card()
	if not card:
		add_log_message("⚠ 请先选择一张卡牌")
		return

	# 从手牌中移除
	if current_hand.remove_card(card):
		# 从显示中移除
		player_hand_display.remove_card_display(card)
		# 添加到弃牌堆
		add_to_discard_pile(card)
		# 更新显示
		update_player_stats()
		# 发送信号
		card_played.emit(card)
		add_log_message("✓ 出牌: %s" % card.get_card_name())
	else:
		add_log_message("⚠ 出牌失败")

func add_to_discard_pile(card: CardData) -> void:
	"""添加卡牌到弃牌堆"""
	discard_cards.append(card)
	if discard_pile:
		# 显示最近的弃牌（限制显示最多16张）
		update_discard_pile_display()

func update_discard_pile_display() -> void:
	"""更新弃牌堆显示"""
	if not discard_pile:
		return

	# 清空旧的显示
	for child in discard_pile.get_children():
		child.queue_free()

	# 显示最近的16张牌（4x4网格）
	var display_count = min(16, discard_cards.size())
	var start_index = max(0, discard_cards.size() - 16)

	for i in range(display_count):
		var card = discard_cards[start_index + i]
		var label = Label.new()
		label.text = card.get_card_name()
		label.add_theme_font_size_override("font_size", 12)
		label.custom_minimum_size = Vector2(50, 40)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		discard_pile.add_child(label)
		print("添加到弃牌堆: %s" % card.get_card_name())

func show_opponent_play(card: CardData) -> void:
	"""显示对手出牌"""
	add_to_discard_pile(card)
	add_log_message("对手出牌: %s" % card.get_card_name())

func display_opponent_hand(hand_count: int) -> void:
	"""显示对手手牌（背面）"""
	if not opponent_hand_display:
		return

	# 清空旧的显示
	for child in opponent_hand_display.get_children():
		child.queue_free()

	# 显示指定数量的背面卡牌
	for i in range(hand_count):
		var label = Label.new()
		label.text = "🂠"  # 卡牌背面符号
		label.add_theme_font_size_override("font_size", 14)
		label.custom_minimum_size = Vector2(60, 80)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.modulate = Color(0.4, 0.4, 0.6, 1.0)  # 灰蓝色
		opponent_hand_display.add_child(label)

	print("✓ 显示对手手牌: %d张" % hand_count)

func show_win_result(result: WinResult) -> void:
	"""显示胡牌结果"""
	if result.eye_card:
		add_log_message("✓ 胡牌! 将: %s" % result.eye_card.get_card_name())
	for pattern in result.win_patterns:
		add_log_message("  胡牌类型: %s" % str(pattern))

func _on_hu_pressed() -> void:
	"""胡牌按钮"""
	print("胡牌按钮按下")
	if not current_hand:
		add_log_message("⚠ 无法胡牌: 没有手牌")
		return

	# 这里应该调用WinChecker检查是否能胡
	add_log_message("🎯 尝试胡牌...")

	# 显示胡牌动画
	if player_hand_display:
		animate_win()

func _on_ting_pressed() -> void:
	"""听牌按钮"""
	print("听牌按钮按下")
	if not current_hand:
		add_log_message("⚠ 无法听牌: 没有手牌")
		return

	# 这里应该调用TingChecker检查是否能听
	add_log_message("👂 尝试听牌...")

func _on_peng_pressed() -> void:
	"""碰按钮"""
	print("碰按钮按下")
	add_log_message("✋ 碰")
	player_action.emit("peng")

func _on_pass_pressed() -> void:
	"""跳过按钮"""
	print("跳过按钮按下")
	add_log_message("⏭ 跳过")
	player_action.emit("pass")

func _on_quit_pressed() -> void:
	"""退出游戏"""
	print("退出游戏")
	add_log_message("📌 退出游戏")
	get_tree().quit()

func animate_win() -> void:
	"""胡牌动画效果"""
	var tween = create_tween()
	for i in range(3):
		tween.tween_property(player_hand_display, "scale", Vector2(1.1, 1.1), 0.15)
		tween.tween_property(player_hand_display, "scale", Vector2(1.0, 1.0), 0.15)
	add_log_message("✨ 胡牌特效播放")

func test_display_hand() -> void:
	"""测试用: 显示测试手牌"""
	var test_hand = CardHand.new()
	test_hand.add_card(CardData.new(CardData.Suit.WAN, 1))
	test_hand.add_card(CardData.new(CardData.Suit.WAN, 2))
	test_hand.add_card(CardData.new(CardData.Suit.WAN, 3))
	test_hand.add_card(CardData.new(CardData.Suit.TONG, 4))
	test_hand.add_card(CardData.new(CardData.Suit.TONG, 5))
	test_hand.add_card(CardData.new(CardData.Suit.TONG, 6))
	test_hand.add_card(CardData.new(CardData.Suit.TIAO, 7))
	test_hand.add_card(CardData.new(CardData.Suit.TIAO, 8))
	test_hand.add_card(CardData.new(CardData.Suit.TIAO, 9))
	test_hand.add_card(CardData.new(CardData.Suit.ZI, 1))
	test_hand.add_card(CardData.new(CardData.Suit.WAN, 5))
	test_hand.add_card(CardData.new(CardData.Suit.TONG, 2))
	test_hand.add_card(CardData.new(CardData.Suit.TIAO, 4))

	display_hand(test_hand)
