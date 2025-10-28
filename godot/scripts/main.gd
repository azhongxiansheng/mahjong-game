extends Node2D

# 麻将游戏主场景脚本
# 这里管理游戏的整体逻辑和流程

var game_manager: GameManager
var player: Player
var enemies: Array = []

# 防止连续触发的标志
var last_p_press_time = 0.0
var last_h_press_time = 0.0
var last_e_press_time = 0.0
var key_cooldown = 0.3  # 0.3秒的冷却时间

# 自动测试标志
var auto_test_started = false

# 分隔符
var separator = "========================================"

func _ready() -> void:
	"""
	当场景准备好时调用一次
	在这里初始化游戏
	"""
	print("欢迎来到麻将游戏！")
	print("游戏已启动")
	print(separator)
	print("测试快捷键:")
	print("  P - Player 受伤 10 点")
	print("  H - Player 恢复 20 点")
	print("  E - 所有 Enemy 受伤 20 点")
	print("  ESC - 退出游戏")
	print(separator)

	# 创建 GameManager 来管理游戏
	game_manager = GameManager.new()
	add_child(game_manager)

	# 获取 Player 和 Enemies 的引用
	player = get_node_or_null("GameLayer/Player")
	enemies = get_tree().get_nodes_in_group("enemies")

	print("Main: Player 和 Enemy 引用已获取")
	print("Main: 开始接收输入...")

	# 启动自动测试（延迟1秒后开始）
	await get_tree().create_timer(1.0).timeout
	print("\n" + separator)
	print("自动测试开始...")
	print(separator + "\n")
	start_auto_test()


func start_auto_test() -> void:
	"""自动测试所有功能"""
	if auto_test_started:
		return
	auto_test_started = true

	# 测试1: Player 受伤
	print("【测试1】Player 受伤测试...")
	if player:
		player.take_damage(10)
		await get_tree().create_timer(0.5).timeout

	# 测试2: Player 治疗
	print("\n【测试2】Player 治疗测试...")
	if player:
		player.heal(20)
		await get_tree().create_timer(0.5).timeout

	# 测试3: Enemy 受伤
	print("\n【测试3】Enemy 受伤测试...")
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy is Enemy:
			enemy.take_damage(20)
			await get_tree().create_timer(0.3).timeout

	# 继续受伤直到敌人死亡
	print("\n【测试4】继续伤害敌人直到死亡...")
	for i in range(5):
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy is Enemy:
				enemy.take_damage(20)
		await get_tree().create_timer(0.3).timeout

	print("\n" + separator)
	print("自动测试完成！")
	print(separator)

	# 第2周测试
	print("\n" + separator)
	print("第2周：GDScript 基础语法测试")
	print(separator)
	await test_card_system()


func test_card_system() -> void:
	"""测试卡牌系统"""
	print("\n【测试5】CardData 和 CardHand 系统...")

	# 创建手牌
	var hand = CardHand.new()

	# 添加卡牌
	print("\n--- 添加卡牌 ---")
	var card1 = CardData.new(CardData.Suit.WAN, 1)
	var card2 = CardData.new(CardData.Suit.WAN, 2)
	var card3 = CardData.new(CardData.Suit.TONG, 5)
	var card4 = CardData.new(CardData.Suit.TIAO, 9)

	hand.add_card(card1)
	hand.add_card(card2)
	hand.add_card(card3)
	hand.add_card(card4)
	await get_tree().create_timer(0.5).timeout

	# 显示手牌
	hand.print_hand()
	await get_tree().create_timer(0.5).timeout

	# 排序卡牌
	print("--- 排序卡牌 ---")
	var unsorted_hand = CardHand.new()
	unsorted_hand.add_card(CardData.new(CardData.Suit.ZI, 3))
	unsorted_hand.add_card(CardData.new(CardData.Suit.WAN, 5))
	unsorted_hand.add_card(CardData.new(CardData.Suit.TONG, 1))
	unsorted_hand.print_hand()

	unsorted_hand.sort_cards()
	unsorted_hand.print_hand()
	await get_tree().create_timer(0.5).timeout

	# 查找卡牌
	print("--- 查找卡牌 ---")
	print("尝试查找 万花色 2号卡牌...")
	var found = hand.find_card(int(CardData.Suit.WAN), 2)
	if found:
		print("✓ 找到卡牌: %s" % found.get_card_name())
	else:
		print("✗ 未找到卡牌")
	await get_tree().create_timer(0.5).timeout

	# 获取同花色卡牌
	print("--- 获取同花色卡牌 ---")
	var wan_cards = hand.get_cards_by_suit(CardData.Suit.WAN)
	print("万花色卡牌数: %d" % wan_cards.size())
	for card in wan_cards:
		print("  - %s" % card.get_card_name())
	await get_tree().create_timer(0.5).timeout

	# 测试卡牌配对
	print("--- 测试卡牌配对 ---")
	var card_a = CardData.new(CardData.Suit.TIAO, 3)
	var card_b = CardData.new(CardData.Suit.TIAO, 3)
	var card_c = CardData.new(CardData.Suit.TIAO, 4)
	print("%s 和 %s 能配对: %s" % [card_a.get_card_name(), card_b.get_card_name(), card_a.can_pair_with(card_b)])
	print("%s 和 %s 能配对: %s" % [card_a.get_card_name(), card_c.get_card_name(), card_a.can_pair_with(card_c)])
	await get_tree().create_timer(0.5).timeout

	# 测试等级判断
	print("--- 测试卡牌等级 ---")
	for num in range(1, 10):
		var test_card = CardData.new(CardData.Suit.WAN, num)
		print("%s 的等级: %s" % [test_card.get_card_name(), test_card.get_rank()])

	print("\n" + separator)
	print("第2周测试完成！")
	print(separator)

	# 第3周测试
	print("\n" + separator)
	print("第3周：函数进阶和类的继承测试")
	print(separator)
	await test_week3_inheritance()


func test_week3_inheritance() -> void:
	"""第3周测试：继承和卡牌池"""
	print("\n【测试6】SpecialCard 和 CardDeck 系统...")

	# 测试 SpecialCard（继承示例）
	print("\n--- 创建特殊卡牌 ---")
	var normal_card = CardData.new(CardData.Suit.WAN, 5)
	var special_card = SpecialCard.new(CardData.Suit.TONG, 8, "暴击", 5)

	print("普通卡牌: %s" % normal_card.get_card_name())
	print("特殊卡牌: %s" % special_card.get_card_name())
	print("特殊卡牌总数值: %d (基础: %d + 效果: %d)" % [special_card.get_total_value(), special_card.number, special_card.effect_value])
	await get_tree().create_timer(0.5).timeout

	# 测试 CardDeck（牌池管理）
	print("\n--- 创建和管理卡牌池 ---")
	var deck = CardDeck.new()

	# 添加一些卡牌
	print("添加卡牌到牌池...")
	deck.add_card(CardData.new(CardData.Suit.WAN, 1))
	deck.add_card(CardData.new(CardData.Suit.TONG, 5))
	deck.add_card(CardData.new(CardData.Suit.TIAO, 9))
	await get_tree().create_timer(0.5).timeout

	# 测试洗牌
	print("\n--- 洗牌 ---")
	deck.shuffle()
	await get_tree().create_timer(0.5).timeout

	# 测试抽卡
	print("\n--- 抽卡 ---")
	var drawn = deck.draw_cards(2)
	print("抽了 %d 张卡牌" % drawn.size())
	await get_tree().create_timer(0.5).timeout

	# 测试 MahjongDeck（标准麻将牌池）
	print("\n--- 创建标准麻将牌池（108张）---")
	var mahjong_deck = MahjongDeck.new()
	await get_tree().create_timer(0.5).timeout

	# 抽初始手牌
	print("\n--- 抽初始手牌 ---")
	var hand = mahjong_deck.draw_initial_hand(13)
	print("✓ 抽了 %d 张初始手牌" % hand.size())

	# 显示手牌
	print("\n初始手牌:")
	for i in range(hand.size()):
		print("  %d. %s" % [i + 1, hand[i].get_card_name()])
	await get_tree().create_timer(0.5).timeout

	# 继续抽牌
	print("\n--- 继续抽牌 ---")
	for i in range(3):
		var card = mahjong_deck.draw_one()
		if card:
			print("抽到: %s" % card.get_card_name())
	await get_tree().create_timer(0.5).timeout

	# 显示牌池状态
	mahjong_deck.get_deck_status()
	await get_tree().create_timer(0.5).timeout

	# 测试类型检查
	print("\n--- 测试继承和类型检查 ---")
	var card_a: CardData = CardData.new(CardData.Suit.WAN, 1)
	var card_b: CardData = SpecialCard.new(CardData.Suit.TONG, 2, "冻结", 3)

	print("card_a 是 CardData: %s" % (card_a is CardData))
	print("card_a 是 SpecialCard: %s" % (card_a is SpecialCard))
	print("card_b 是 CardData: %s" % (card_b is CardData))
	print("card_b 是 SpecialCard: %s" % (card_b is SpecialCard))

	if card_b is SpecialCard:
		var special = card_b as SpecialCard
		print("card_b 的特殊效果: %s (+%d)" % [special.effect_name, special.effect_value])

	print("\n" + separator)
	print("第3周测试完成！")
	print(separator)

	# 第4周测试
	print("\n" + separator)
	print("第4周：游戏状态管理和完整游戏流程")
	print(separator)
	await test_week4_game_flow()


func test_week4_game_flow() -> void:
	"""第4周测试：游戏状态机和完整流程"""
	print("\n【测试7】GameState 和 GameController 系统...")

	# 创建游戏控制器
	var game = GameController.new()
	await get_tree().create_timer(0.5).timeout

	# 初始化游戏
	print("\n--- 游戏初始化 ---")
	game.init_game()
	print("当前状态: %s" % game.game_state.get_state_name())
	await get_tree().create_timer(0.5).timeout

	# 开始游戏
	print("\n--- 开始游戏 ---")
	game.start_game()
	print("当前状态: %s" % game.game_state.get_state_name())
	print("手牌数量: %d" % game.player_hand.get_card_count())
	await get_tree().create_timer(0.5).timeout

	# 模拟游戏流程
	print("\n--- 游戏流程模拟 ---")
	for i in range(3):
		print("\n【回合 %d】" % (i + 1))

		# 抽卡
		var drawn_card = game.draw_card()
		print("当前状态: %s" % game.game_state.get_state_name())
		print("手牌数量: %d" % game.player_hand.get_card_count())
		await get_tree().create_timer(0.3).timeout

		# 出卡
		if drawn_card:
			var success = game.discard_card(drawn_card)
			if success:
				print("当前状态: %s" % game.game_state.get_state_name())
				print("手牌数量: %d" % game.player_hand.get_card_count())

		await get_tree().create_timer(0.3).timeout

	# 显示游戏状态
	print("\n--- 游戏状态信息 ---")
	game.game_state.print_state_info()
	await get_tree().create_timer(0.5).timeout

	# 显示游戏统计
	print("\n--- 游戏统计 ---")
	game.print_game_stats()
	await get_tree().create_timer(0.5).timeout

	# 获取游戏状态
	print("\n--- 游戏状态快照 ---")
	var status = game.get_game_status()
	print("当前状态: %s" % status["current_state"])
	print("手牌数: %d" % status["hand_count"])
	print("牌池剩余: %d" % status["deck_remaining"])
	print("轮数: %d" % status["rounds"])
	await get_tree().create_timer(0.5).timeout

	# 结束游戏
	print("\n--- 结束游戏 ---")
	game.end_game()

	print("\n" + separator)
	print("第4周测试完成！")
	print(separator)


	# 第5周测试
	print("\n" + separator)
	print("第5周：胡牌算法和规则判断测试")
	print(separator)
	await test_week5_hu_algorithm()


func _process(delta: float) -> void:
	"""
	每一帧调用一次
	使用轮询方式检查按键状态
	"""
	var current_time = Time.get_ticks_msec() / 1000.0

	# 检查 P 键
	if Input.is_key_pressed(KEY_P):
		if current_time - last_p_press_time > key_cooldown:
			if player:
				print("✓ 检测到 P 键，Player 受伤")
				player.take_damage(10)
				last_p_press_time = current_time

	# 检查 H 键
	if Input.is_key_pressed(KEY_H):
		if current_time - last_h_press_time > key_cooldown:
			if player:
				print("✓ 检测到 H 键，Player 治疗")
				player.heal(20)
				last_h_press_time = current_time

	# 检查 E 键
	if Input.is_key_pressed(KEY_E):
		if current_time - last_e_press_time > key_cooldown:
			print("✓ 检测到 E 键，所有 Enemy 受伤")
			for enemy in enemies:
				if is_instance_valid(enemy) and enemy is Enemy:
					enemy.take_damage(20)
			last_e_press_time = current_time

	# 检查 ESC 键
	if Input.is_key_pressed(KEY_ESCAPE):
		print("按下 ESC，退出游戏")
		get_tree().quit()


func _input(event: InputEvent) -> void:
	"""
	处理用户输入事件（备用方案）
	"""
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_P:
			print("📥 _input 方式检测到 P 键")
		elif event.keycode == KEY_H:
			print("📥 _input 方式检测到 H 键")
		elif event.keycode == KEY_E:
			print("📥 _input 方式检测到 E 键")
		elif event.keycode == KEY_ESCAPE:
			print("按下 ESC，退出游戏")
			get_tree().quit()


func test_week5_hu_algorithm() -> void:
	"""第5周测试：胡牌算法"""
	print("\n【测试8】胡牌算法和规则判断...")

	# 创建麻将牌池
	var deck = MahjongDeck.new()
	deck.shuffle()

	# 测试1：基本胡牌
	print("\n--- 测试1：基本胡牌 ---")
	var hand1 = CardHand.new()

	# 构造一个能胡的手牌
	# 胡牌：万1万1 万2万3万4 筒5筒5筒5 条6条7条8 条9条9
	hand1.add_card(CardData.new(0, 1))
	hand1.add_card(CardData.new(0, 1))
	hand1.add_card(CardData.new(0, 2))
	hand1.add_card(CardData.new(0, 3))
	hand1.add_card(CardData.new(0, 4))
	hand1.add_card(CardData.new(1, 5))
	hand1.add_card(CardData.new(1, 5))
	hand1.add_card(CardData.new(1, 5))
	hand1.add_card(CardData.new(2, 6))
	hand1.add_card(CardData.new(2, 7))
	hand1.add_card(CardData.new(2, 8))
	hand1.add_card(CardData.new(2, 9))
	hand1.add_card(CardData.new(2, 9))

	print("手牌: 万1万1 万2万3万4 筒5筒5筒5 条6条7条8 条9条9")
	var result1 = WinChecker.check_win(hand1)
	if result1.can_win:
		print("✓ 能胡牌！")
		var fan = HuRule.calculate_fan(result1, hand1)
		print("  番数: %d 番" % fan)
		HuRule.print_win_info(result1, hand1)
	else:
		print("✗ 无法胡牌")

	await get_tree().create_timer(0.3).timeout

	# 测试2：全刻
	print("\n--- 测试2：全刻胡牌 ---")
	var hand2 = CardHand.new()
	# 全刻：万1万1万1 万2万2万2 筒3筒3筒3 条4条4条4 条5条5
	for i in range(3):
		hand2.add_card(CardData.new(0, 1))
	for i in range(3):
		hand2.add_card(CardData.new(0, 2))
	for i in range(3):
		hand2.add_card(CardData.new(1, 3))
	for i in range(3):
		hand2.add_card(CardData.new(2, 4))
	for i in range(2):
		hand2.add_card(CardData.new(2, 5))

	print("手牌: 万1万1万1 万2万2万2 筒3筒3筒3 条4条4条4 条5条5")
	var result2 = WinChecker.check_win(hand2)
	if result2.can_win:
		print("✓ 能胡牌！（全刻）")
		var fan2 = HuRule.calculate_fan(result2, hand2)
		print("  番数: %d 番" % fan2)
		HuRule.print_win_info(result2, hand2)
	else:
		print("✗ 无法胡牌")

	await get_tree().create_timer(0.3).timeout

	# 测试3：清一色
	print("\n--- 测试3：清一色胡牌 ---")
	var hand3 = CardHand.new()
	# 清一色（只有万牌）：万1万1 万2万3万4 万5万5万5 万6万7万8 万9万9
	hand3.add_card(CardData.new(0, 1))
	hand3.add_card(CardData.new(0, 1))
	hand3.add_card(CardData.new(0, 2))
	hand3.add_card(CardData.new(0, 3))
	hand3.add_card(CardData.new(0, 4))
	hand3.add_card(CardData.new(0, 5))
	hand3.add_card(CardData.new(0, 5))
	hand3.add_card(CardData.new(0, 5))
	hand3.add_card(CardData.new(0, 6))
	hand3.add_card(CardData.new(0, 7))
	hand3.add_card(CardData.new(0, 8))
	hand3.add_card(CardData.new(0, 9))
	hand3.add_card(CardData.new(0, 9))

	print("手牌: 万1万1 万2万3万4 万5万5万5 万6万7万8 万9万9")
	var result3 = WinChecker.check_win(hand3)
	if result3.can_win:
		print("✓ 能胡牌！（清一色）")
		var fan3 = HuRule.calculate_fan(result3, hand3)
		print("  番数: %d 番" % fan3)
		HuRule.print_win_info(result3, hand3)
	else:
		print("✗ 无法胡牌")

	await get_tree().create_timer(0.3).timeout

	# 测试4：牌型识别
	print("\n--- 测试4：牌型识别 ---")
	var chow_cards = [CardData.new(0, 1), CardData.new(0, 2), CardData.new(0, 3)]
	var pung_cards = [CardData.new(1, 5), CardData.new(1, 5), CardData.new(1, 5)]
	var pair_cards = [CardData.new(2, 7), CardData.new(2, 7)]

	print("识别顺子 (万1万2万3): %s" % WinPattern.get_pattern_name(WinPattern.identify_pattern(chow_cards)))
	print("识别刻子 (筒5筒5筒5): %s" % WinPattern.get_pattern_name(WinPattern.identify_pattern(pung_cards)))
	print("识别对子 (条7条7): %s" % WinPattern.get_pattern_name(WinPattern.identify_pattern(pair_cards)))

	await get_tree().create_timer(0.3).timeout

	print("\n" + separator)
	print("第5周测试完成！")
	print(separator)


func test_week6_ai_and_ting() -> void:
	"""第6周测试：听牌检测和AI玩家"""
	print("\n【测试9】听牌检测和AI玩家...")

	# 测试1：听牌检测
	print("\n--- 测试1：听牌检测 ---")
	var hand = CardHand.new()

	# 构造一个能听牌的手牌
	# 缺条9就能胡：万1万1 万2万3万4 筒5筒5筒5 条6条7条8
	hand.add_card(CardData.new(0, 1))
	hand.add_card(CardData.new(0, 1))
	hand.add_card(CardData.new(0, 2))
	hand.add_card(CardData.new(0, 3))
	hand.add_card(CardData.new(0, 4))
	hand.add_card(CardData.new(1, 5))
	hand.add_card(CardData.new(1, 5))
	hand.add_card(CardData.new(1, 5))
	hand.add_card(CardData.new(2, 6))
	hand.add_card(CardData.new(2, 7))
	hand.add_card(CardData.new(2, 8))
	hand.add_card(CardData.new(2, 9))

	print("手牌: 万1万1 万2万3万4 筒5筒5筒5 条6条7条8 条9")
	var ting_result = TingChecker.check_ting(hand)

	if ting_result.can_ting:
		print("✓ 能听牌！")
		print("  听牌描述: %s" % TingChecker.get_ting_description(ting_result))
		print("  听牌数量: %d" % ting_result.ting_count)
	else:
		print("✗ 无法听牌")

	await get_tree().create_timer(0.3).timeout

	# 测试2：AI玩家创建和难度等级
	print("\n--- 测试2：AI玩家创建 ---")

	var ai_easy = AIPlayer.new(0, AIPlayer.Difficulty.EASY)
	var ai_normal = AIPlayer.new(1, AIPlayer.Difficulty.NORMAL)
	var ai_hard = AIPlayer.new(2, AIPlayer.Difficulty.HARD)
	var ai_expert = AIPlayer.new(3, AIPlayer.Difficulty.EXPERT)

	print("✓ 已创建4个AI玩家:")
	print("  - %s (简单)" % ai_easy.name)
	print("  - %s (普通)" % ai_normal.name)
	print("  - %s (困难)" % ai_hard.name)
	print("  - %s (专家)" % ai_expert.name)

	await get_tree().create_timer(0.3).timeout

	# 测试3：AI发牌和出牌
	print("\n--- 测试3：AI发牌和出牌模拟 ---")

	# 给AI发初始手牌
	var deck = MahjongDeck.new()
	deck.shuffle()

	for ai in [ai_easy, ai_normal, ai_hard, ai_expert]:
		for i in range(13):
			var card = deck.draw_one()
			if card:
				ai.receive_card(card)

	print("✓ 已给每个AI发13张初始手牌")
	print("\n--- 每个AI的状态 ---")
	for ai in [ai_easy, ai_normal, ai_hard, ai_expert]:
		print("  %s" % ai.get_status_string())

	await get_tree().create_timer(0.3).timeout

	# 测试4：模拟游戏回合
	print("\n--- 测试4：游戏回合模拟 ---")

	for round_num in range(1, 4):
		print("\n【第 %d 回合】" % round_num)

		# 每个AI抽一张牌并出牌
		for ai in [ai_easy, ai_normal, ai_hard, ai_expert]:
			# 抽卡
			var drawn = deck.draw_one()
			if drawn:
				ai.receive_card(drawn)
				print("  %s 抽卡: %s (现有: %d张)" % [ai.name, drawn.get_card_name(), ai.hand.get_card_count()])

			# 更新听牌
			ai.update_ting_info()

			# 出牌
			var discarded = ai.discard_card()
			if discarded:
				print("    → 出牌: %s" % discarded.get_card_name())
				if ai.is_ting:
					print("    → [已听牌] %s" % TingChecker.get_ting_description(ai.ting_info))

			await get_tree().create_timer(0.1).timeout

	await get_tree().create_timer(0.3).timeout

	# 测试5：性能测试
	print("\n--- 测试5：性能测试 ---")
	var test_hand = CardHand.new()
	# 构造一个复杂的手牌
	for suit in range(3):
		for num in range(1, 7):
			test_hand.add_card(CardData.new(suit, num))

	print("测试手牌 (%d张): 进行1000次听牌检测..." % test_hand.get_card_count())
	var start_time = Time.get_ticks_msec()

	for i in range(1000):
		var result = TingChecker.check_ting(test_hand)

	var elapsed = Time.get_ticks_msec() - start_time
	print("✓ 完成! 耗时: %d ms (平均: %.2f ms/次)" % [elapsed, float(elapsed) / 1000.0])

	await get_tree().create_timer(0.3).timeout

	print("\n" + separator)
	print("第6周测试完成！")
	print(separator)
