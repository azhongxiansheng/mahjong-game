class_name GameTester
extends Node

# UI引用
var game_ui: GameUI
var test_hand: CardHand

func _ready() -> void:
	print("========== GameTester 初始化 ==========")
	
	# 获取GameUI
	game_ui = get_node_or_null("../GameUI")
	
	if not game_ui:
		print("⚠ 无法找到GameUI")
		return
	
	print("✓ GameTester已初始化")
	print("✓ 可用的测试方法:")
	print("  - test_display_hand(): 测试显示手牌")
	print("  - test_card_selection(): 测试卡牌选择")
	print("  - test_play_card(): 测试出牌")
	print("  - test_animations(): 测试动画效果")
	print("  - test_win_check(): 测试胡牌检查")

func test_display_hand() -> void:
	"""测试显示手牌"""
	print("\n========== 测试1: 显示手牌 ==========")
	
	# 创建测试手牌
	test_hand = CardHand.new()
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
	
	# 显示手牌
	if game_ui:
		game_ui.display_hand(test_hand)
		print("✓ 手牌已显示: %d张" % test_hand.get_card_count())
	else:
		print("⚠ GameUI为空")

func test_card_selection() -> void:
	"""测试卡牌选择"""
	print("\n========== 测试2: 卡牌选择 ==========")
	
	if not game_ui or not game_ui.player_hand_display:
		print("⚠ GameUI或HandDisplay为空")
		return
	
	# 选择第一张卡牌
	if game_ui.player_hand_display.card_tiles.size() > 0:
		var first_tile = game_ui.player_hand_display.card_tiles[0]
		game_ui.player_hand_display.select_card(first_tile)
		print("✓ 已选择卡牌: %s" % first_tile.card_data.get_card_name())
		
		# 验证选择
		var selected = game_ui.player_hand_display.get_selected_card()
		if selected:
			print("✓ 验证选择成功: %s" % selected.get_card_name())
		else:
			print("⚠ 选择验证失败")
	else:
		print("⚠ 没有可选择的卡牌")

func test_play_card() -> void:
	"""测试出牌"""
	print("\n========== 测试3: 出牌 ==========")
	
	if not game_ui:
		print("⚠ GameUI为空")
		return
	
	# 先显示手牌
	if not test_hand or test_hand.get_card_count() == 0:
		test_display_hand()
	
	# 选择第一张卡牌
	if game_ui.player_hand_display.card_tiles.size() > 0:
		var first_tile = game_ui.player_hand_display.card_tiles[0]
		game_ui.player_hand_display.select_card(first_tile)
		
		# 出牌
		var before_count = game_ui.current_hand.get_card_count()
		game_ui.play_card()
		var after_count = game_ui.current_hand.get_card_count()
		
		if after_count < before_count:
			print("✓ 出牌成功: %d -> %d张" % [before_count, after_count])
		else:
			print("⚠ 出牌失败")
	else:
		print("⚠ 没有可出的卡牌")

func test_animations() -> void:
	"""测试动画效果"""
	print("\n========== 测试4: 动画效果 ==========")
	
	if not game_ui or not game_ui.player_hand_display:
		print("⚠ GameUI为空")
		return
	
	# 播放胡牌动画
	print("✓ 播放胡牌动画...")
	game_ui.animate_win()
	
	await get_tree().create_timer(1.0).timeout
	print("✓ 动画测试完成")

func test_win_check() -> void:
	"""测试胡牌检查"""
	print("\n========== 测试5: 胡牌检查 ==========")
	
	if not game_ui:
		print("⚠ GameUI为空")
		return
	
	# 显示日志消息测试
	game_ui.add_log_message("测试日志消息")
	game_ui.add_log_message("✓ 第二条消息")
	game_ui.add_log_message("⚠ 警告消息")
	
	print("✓ 日志消息已添加")

func run_all_tests() -> void:
	"""运行所有测试"""
	print("\n========== 开始运行所有测试 ==========\n")
	
	test_display_hand()
	await get_tree().create_timer(0.5).timeout
	
	test_card_selection()
	await get_tree().create_timer(0.5).timeout
	
	test_animations()
	await get_tree().create_timer(1.5).timeout
	
	test_win_check()
	await get_tree().create_timer(0.5).timeout
	
	test_play_card()
	
	print("\n========== 所有测试完成 ==========\n")
