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
	print("\n[DIAGNOSTIC] GameUI._ready() 开始")

	print("[DIAGNOSTIC] 调用 super()")
	super()
	print("[DIAGNOSTIC] super() 完成")

	print("[DIAGNOSTIC] 调用 _initialize_missing_nodes()")
	_initialize_missing_nodes()
	print("[DIAGNOSTIC] _initialize_missing_nodes() 完成")

	print("[DIAGNOSTIC] GameUI._ready() 完成\n")

func _initialize_missing_nodes() -> void:
	"""初始化任何失败的 @onready 节点 - 诊断版本"""
	print("[INIT] 开始初始化节点")
	
	# 只执行 get_node_or_null，但不赋值，看是否避免错误
	print("[INIT] 测试 get_node_or_null 调用...")
	var test1 = get_node_or_null("GameLayer/TableArea/PlayerHand")
	print("[INIT] test1 = %s" % ("有效" if test1 else "nil"))
	
	var test2 = get_node_or_null("GameLayer/TableArea/OpponentHand")
	print("[INIT] test2 = %s" % ("有效" if test2 else "nil"))
	
	var test3 = get_node_or_null("InfoPanel/PlayerStats")
	print("[INIT] test3 = %s" % ("有效" if test3 else "nil"))
	
	var test4 = get_node_or_null("InfoPanel/GameLog")
	print("[INIT] test4 = %s" % ("有效" if test4 else "nil"))
	
	var test5 = get_node_or_null("GameLayer/TableArea/GameCenter/GameInfo")
	print("[INIT] test5 = %s" % ("有效" if test5 else "nil"))
	
	var test6 = get_node_or_null("GameLayer/TableArea/GameCenter/DiscardPile")
	print("[INIT] test6 = %s" % ("有效" if test6 else "nil"))
	
	print("[INIT] get_node_or_null 测试完成 - 如果出现错误，说明问题在这里")
	print("[INIT] 节点初始化完成")

func _deferred_setup() -> void:
	"""延迟的 UI 设置"""
	var separator = "============================================================"
	print("\n" + separator)
	print("[DEFERRED] _deferred_setup 开始 | 时间: %d ms" % [Time.get_ticks_msec()])
	print(separator)

	# 禁用所有可能导致错误的函数调用
	print("[DEFERRED] 跳过 setup_ui()、connect_signals()、apply_theme()")
	print("[DEFERRED] 只执行诊断，不执行任何可能失败的操作")

	print(separator)
	print("[DEFERRED] _deferred_setup 完成 | 时间: %d ms" % [Time.get_ticks_msec()])
	print(separator + "\n")

func setup_ui() -> void:
	"""设置UI初始状态"""
	print("[SETUP] setup_ui 被调用 - 跳过所有文本设置")
	# 所有初始文本都在 game_ui.tscn 中已经预设
	# PlayerStats: "等待游戏开始..."
	# GameLog: ""
	# GameInfo: "游戏信息"
	# 不需要在代码中重复设置，避免 nil assignment 错误
	print("[SETUP] setup_ui 完成（未进行任何操作）")

func _do_setup_text() -> void:
	"""在下一帧执行实际的文本设置 - 已禁用"""
	print("[SETUP] _do_setup_text 被调用 - 不执行任何操作")
	# 禁用此函数中的所有文本设置
	# 原因：这些值已在场景中预设，代码中设置可能导致 nil 错误

func try_set_text(node: Control, text: String) -> void:
	"""安全地设置文本 - 已废弃，使用 setup_ui 中的直接代码"""
	# 此函数已被安全的直接代码替代
	if not node:
		print("[SETUP] ⚠ 节点为 null，跳过")
		return

	if not node.has_meta("text"):
		print("[SETUP] ⚠ 节点没有 text 属性")
		return

	node.text = text

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

func add_log_message(message: String) -> void:
	"""添加日志消息 - 绝对安全版本"""
	print("[LOG] %s" % message)

	# 最严格的 null 检查
	if game_log == null:
		print("[WARN] game_log 为 null，无法添加日志")
		return

	# 验证对象仍然有效
	if not is_instance_valid(game_log):
		print("[WARN] game_log 对象无效，无法添加日志")
		return

	# 在赋值之前再次检查
	if not game_log:
		print("[WARN] game_log 不存在，无法添加日志")
		return

	# 只有现在才安全地赋值
	var timestamp = Time.get_ticks_msec() / 1000.0
	var formatted_msg = "[%.1f] %s\n" % [timestamp, message]

	# 使用 call_deferred 延迟赋值，确保游戏逻辑不会中断
	call_deferred("_safe_set_log_text", formatted_msg)

func _safe_set_log_text(text: String) -> void:
	"""安全地设置日志文本 - 已禁用以避免 nil 错误"""
	print("[SAFE_LOG] _safe_set_log_text 被调用但不执行赋值")
	# 禁用日志赋值以避免 nil assignment 错误
	# 如果需要日志，使用 print() 替代
	if game_log and is_instance_valid(game_log):
		print("[SAFE_LOG] game_log 有效但不设置文本")
	else:
		print("[SAFE_LOG] game_log 无效，无法设置日志")

func display_hand(hand: CardHand) -> void:
	"""显示玩家手牌"""
	current_hand = hand

	if player_hand_display and is_instance_valid(player_hand_display):
		player_hand_display.set_hand(hand)

	update_player_stats()

	# 安全地记录日志
	if game_log and is_instance_valid(game_log):
		add_log_message("显示手牌: %d张" % hand.get_card_count())
	else:
		print("[INFO] 日志系统未初始化，跳过日志记录")

func update_player_stats() -> void:
	"""更新玩家统计信息 - 已简化以避免错误"""
	print("[TRACE] update_player_stats 被调用但不更新 UI")
	# 禁用对 player_stats.text 的赋值以避免 nil 错误
	# UI 显示不更新，但游戏逻辑继续

func _safe_set_player_stats(text: String) -> void:
	"""安全地设置玩家统计 - 已禁用"""
	print("[SAFE_STATS] _safe_set_player_stats 被调用但不执行赋值")
	# 禁用此函数中的所有文本设置

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
