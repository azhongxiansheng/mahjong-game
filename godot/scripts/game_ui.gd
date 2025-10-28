class_name GameUI
extends ScreenBase

# 组件引用
@onready var player_hand_display = $GameLayer/TableArea/PlayerHand
@onready var opponent_hand_display = $GameLayer/TableArea/OpponentHand
@onready var discard_pile = $GameLayer/TableArea/GameCenter/DiscardPile
@onready var game_info = $GameLayer/TableArea/GameCenter/GameInfo
@onready var player_stats = $InfoPanel/PlayerStats
@onready var game_log = $InfoPanel/GameLog

@onready var hu_button = $GameLayer/ActionPanel/HuButton
@onready var ting_button = $GameLayer/ActionPanel/TingButton
@onready var peng_button = $GameLayer/ActionPanel/PengButton
@onready var pass_button = $GameLayer/ActionPanel/PassButton
@onready var quit_button = $InfoPanel/QuitButton

# 游戏状态
var game_controller: GameController
var current_hand: CardHand
var discard_cards: Array[CardData] = []

# 信号
signal card_played(card: CardData)
signal player_action(action: String)

func _ready() -> void:
	print("========== GameUI 初始化 ==========")
	super()
	setup_ui()
	connect_signals()
	apply_theme()
	print("========== GameUI 初始化完成 ==========")

func setup_ui() -> void:
	"""设置UI初始状态"""
	# 设置初始文本
	player_stats.text = "等待游戏开始..."
	game_log.text = ""
	game_info.text = "游戏信息"

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
	
	# 连接手牌显示信号
	if player_hand_display:
		player_hand_display.card_pressed.connect(_on_card_pressed)
		player_hand_display.card_selected.connect(_on_card_selected)

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
	add_log_message("显示手牌: %d张" % hand.get_card_count())

func add_log_message(message: String) -> void:
	"""添加日志消息"""
	if game_log:
		var timestamp = Time.get_ticks_msec() / 1000
		var formatted_msg = "[%.1f] %s" % [timestamp, message]
		game_log.text += formatted_msg + "\n"
		# 滚动到底部
		game_log.scroll_to_line(game_log.get_line_count() - 1)

func update_player_stats() -> void:
	"""更新玩家统计信息"""
	if player_stats and current_hand:
		var card_count = current_hand.get_card_count()
		var selected_card = ""
		if player_hand_display and player_hand_display.get_selected_card():
			selected_card = " | 选中: " + player_hand_display.get_selected_card().get_card_name()
		player_stats.text = "手牌数: %d%s" % [card_count, selected_card]

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
		# 这里可以添加显示弃牌的逻辑
		pass

func show_opponent_play(card: CardData) -> void:
	"""显示对手出牌"""
	add_to_discard_pile(card)
	add_log_message("对手出牌: %s" % card.get_card_name())

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
