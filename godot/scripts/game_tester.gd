class_name GameTester
extends Node

# UI引用
var game_ui: GameUI
var test_hand: CardHand

func _ready() -> void:
	print("========== GameTester 初始化 ==========")

	# ✓ 方案 1: 尝试正确的相对路径
	var main = get_tree().root.get_node_or_null("/root/Main")
	if main:
		game_ui = main.get_node_or_null("UILayer/GameUI")

	# ✓ 方案 2: 如果失败，尝试通过 find_child
	if not game_ui:
		game_ui = get_tree().root.find_child("GameUI", true, false)

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
	print("  - test_discard_pile(): 测试弃牌堆")
	print("  - test_opponent_hand(): 测试对手手牌")
	print("  - test_complete_flow(): 测试完整流程")

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
	"""测试胡牌检查 - 完整测试套件"""
	print("\n========== 胡牌检查完整测试 ==========")
	print("执行 5 个胡牌检查测试用例...\n")

	# 测试 1.1: 标准胡牌 (平胡)
	test_case_1_1_standard_win()

	# 测试 1.2: 全刻胡牌
	test_case_1_2_all_pungs_win()

	# 测试 1.3: 清一色胡牌
	test_case_1_3_clean_win()

	# 测试 1.4: 牌数错误 (13张)
	test_case_1_4_wrong_card_count()

	# 测试 1.5: 眼不够
	test_case_1_5_no_eye()

	print("\n========== 胡牌测试完成 ==========")

func test_ting_check() -> void:
	"""测试听牌检查 - 完整测试套件"""
	print("\n========== 听牌检查完整测试 ==========")
	print("执行 4 个听牌检查测试用例...\n")

	# 测试 2.1: 基础听牌 (听1种牌)
	test_case_2_1_basic_ting()

	# 测试 2.2: 多种听牌
	test_case_2_2_multiple_ting()

	# 测试 2.3: 无法听牌
	test_case_2_3_cannot_ting()

	# 测试 2.4: 复杂听法
	test_case_2_4_complex_ting()

	print("\n========== 听牌测试完成 ==========")

func test_case_1_1_standard_win() -> void:
	"""Test Case 1.1: 标准胡牌 - 平胡"""
	print("📋 Test Case 1.1: 标准胡牌 (平胡)")

	var hand = CardHand.new()
	# 万1 万2 万3 (顺1)
	hand.add_card(CardData.new(CardData.Suit.WAN, 1))
	hand.add_card(CardData.new(CardData.Suit.WAN, 2))
	hand.add_card(CardData.new(CardData.Suit.WAN, 3))
	# 万4 万4 万4 (刻1)
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	# 筒5 筒5 筒5 (刻2)
	hand.add_card(CardData.new(CardData.Suit.TONG, 5))
	hand.add_card(CardData.new(CardData.Suit.TONG, 5))
	hand.add_card(CardData.new(CardData.Suit.TONG, 5))
	# 条6 条6 条6 (刻3)
	hand.add_card(CardData.new(CardData.Suit.TIAO, 6))
	hand.add_card(CardData.new(CardData.Suit.TIAO, 6))
	hand.add_card(CardData.new(CardData.Suit.TIAO, 6))
	# 字1 字1 (眼)
	hand.add_card(CardData.new(CardData.Suit.ZI, 1))
	hand.add_card(CardData.new(CardData.Suit.ZI, 1))

	var result = WinChecker.check_win(hand)

	if result.can_win:
		print("  ✅ 通过: 可以胡牌")
		print("  📊 结果: %s" % ("胡牌成功" if result.can_win else "无法胡牌"))
	else:
		print("  ❌ 失败: 应该能胡牌但无法识别")

	print("")

func test_case_1_2_all_pungs_win() -> void:
	"""Test Case 1.2: 全刻胡牌"""
	print("📋 Test Case 1.2: 全刻胡牌")

	var hand = CardHand.new()
	# 万1 万1 万1 (刻1)
	hand.add_card(CardData.new(CardData.Suit.WAN, 1))
	hand.add_card(CardData.new(CardData.Suit.WAN, 1))
	hand.add_card(CardData.new(CardData.Suit.WAN, 1))
	# 万2 万2 万2 (刻2)
	hand.add_card(CardData.new(CardData.Suit.WAN, 2))
	hand.add_card(CardData.new(CardData.Suit.WAN, 2))
	hand.add_card(CardData.new(CardData.Suit.WAN, 2))
	# 万3 万3 万3 (刻3)
	hand.add_card(CardData.new(CardData.Suit.WAN, 3))
	hand.add_card(CardData.new(CardData.Suit.WAN, 3))
	hand.add_card(CardData.new(CardData.Suit.WAN, 3))
	# 万4 万4 万4 (刻4)
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	# 万5 万5 (眼)
	hand.add_card(CardData.new(CardData.Suit.WAN, 5))
	hand.add_card(CardData.new(CardData.Suit.WAN, 5))

	var result = WinChecker.check_win(hand)

	if result.can_win:
		print("  ✅ 通过: 全刻胡牌")
	else:
		print("  ❌ 失败: 应该能胡牌")

	print("")

func test_case_1_3_clean_win() -> void:
	"""Test Case 1.3: 清一色胡牌"""
	print("📋 Test Case 1.3: 清一色胡牌")

	var hand = CardHand.new()
	# 万1 万2 万3 (顺1)
	hand.add_card(CardData.new(CardData.Suit.WAN, 1))
	hand.add_card(CardData.new(CardData.Suit.WAN, 2))
	hand.add_card(CardData.new(CardData.Suit.WAN, 3))
	# 万4 万5 万6 (顺2)
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	hand.add_card(CardData.new(CardData.Suit.WAN, 5))
	hand.add_card(CardData.new(CardData.Suit.WAN, 6))
	# 万7 万8 万9 (顺3)
	hand.add_card(CardData.new(CardData.Suit.WAN, 7))
	hand.add_card(CardData.new(CardData.Suit.WAN, 8))
	hand.add_card(CardData.new(CardData.Suit.WAN, 9))
	# 万1 万1 万1 (刻)
	hand.add_card(CardData.new(CardData.Suit.WAN, 1))
	hand.add_card(CardData.new(CardData.Suit.WAN, 1))
	hand.add_card(CardData.new(CardData.Suit.WAN, 1))
	# 万9 万9 (眼) - 修改: 使用万9作为眼，避免重复
	hand.add_card(CardData.new(CardData.Suit.WAN, 9))
	hand.add_card(CardData.new(CardData.Suit.WAN, 9))

	var result = WinChecker.check_win(hand)

	if result.can_win:
		print("  ✅ 通过: 清一色胡牌")
	else:
		print("  ❌ 失败: 应该能胡牌")
		# 调试信息
		print("  🔍 调试: 手牌数量 = %d" % hand.get_card_count())

	print("")

func test_case_1_4_wrong_card_count() -> void:
	"""Test Case 1.4: 牌数错误 (13张 - 应该失败)"""
	print("📋 Test Case 1.4: 牌数错误 (13张)")

	var hand = CardHand.new()
	# 只添加13张牌 (错误)
	hand.add_card(CardData.new(CardData.Suit.WAN, 1))
	hand.add_card(CardData.new(CardData.Suit.WAN, 2))
	hand.add_card(CardData.new(CardData.Suit.WAN, 3))
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	hand.add_card(CardData.new(CardData.Suit.TONG, 5))
	hand.add_card(CardData.new(CardData.Suit.TONG, 5))
	hand.add_card(CardData.new(CardData.Suit.TONG, 5))
	hand.add_card(CardData.new(CardData.Suit.TIAO, 6))
	hand.add_card(CardData.new(CardData.Suit.TIAO, 6))
	hand.add_card(CardData.new(CardData.Suit.TIAO, 6))
	hand.add_card(CardData.new(CardData.Suit.ZI, 1))

	var result = WinChecker.check_win(hand)

	if not result.can_win:
		print("  ✅ 通过: 正确拒绝 (牌数不对)")
	else:
		print("  ❌ 失败: 应该拒绝 (牌数不对)")

	print("")

func test_case_1_5_no_eye() -> void:
	"""Test Case 1.5: 眼不够"""
	print("📋 Test Case 1.5: 眼不够")

	var hand = CardHand.new()
	# 万1 万2 万3 (顺1)
	hand.add_card(CardData.new(CardData.Suit.WAN, 1))
	hand.add_card(CardData.new(CardData.Suit.WAN, 2))
	hand.add_card(CardData.new(CardData.Suit.WAN, 3))
	# 万4 万4 万4 (刻1)
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	# 筒5 筒5 筒5 (刻2)
	hand.add_card(CardData.new(CardData.Suit.TONG, 5))
	hand.add_card(CardData.new(CardData.Suit.TONG, 5))
	hand.add_card(CardData.new(CardData.Suit.TONG, 5))
	# 条6 条6 条6 (刻3)
	hand.add_card(CardData.new(CardData.Suit.TIAO, 6))
	hand.add_card(CardData.new(CardData.Suit.TIAO, 6))
	hand.add_card(CardData.new(CardData.Suit.TIAO, 6))
	# 字1 字2 字3 (不是眼)
	hand.add_card(CardData.new(CardData.Suit.ZI, 1))
	hand.add_card(CardData.new(CardData.Suit.ZI, 2))
	hand.add_card(CardData.new(CardData.Suit.ZI, 3))

	var result = WinChecker.check_win(hand)

	if not result.can_win:
		print("  ✅ 通过: 正确拒绝 (没有眼)")
	else:
		print("  ❌ 失败: 应该拒绝 (没有眼)")

	print("")

func test_case_2_1_basic_ting() -> void:
	print("📋 Test Case 2.1: 基础听牌 (听1种牌)")

	var hand = CardHand.new()

	# 万1万2万3 (sequence)
	hand.add_card(CardData.new(CardData.Suit.WAN, 1))
	hand.add_card(CardData.new(CardData.Suit.WAN, 2))
	hand.add_card(CardData.new(CardData.Suit.WAN, 3))
	# 万4万5万6 (sequence)
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	hand.add_card(CardData.new(CardData.Suit.WAN, 5))
	hand.add_card(CardData.new(CardData.Suit.WAN, 6))
	# 筒1筒1筒1 (triplet)
	hand.add_card(CardData.new(CardData.Suit.TONG, 1))
	hand.add_card(CardData.new(CardData.Suit.TONG, 1))
	hand.add_card(CardData.new(CardData.Suit.TONG, 1))
	# 条2条2 (pair - needs one more to complete)
	hand.add_card(CardData.new(CardData.Suit.TIAO, 2))
	hand.add_card(CardData.new(CardData.Suit.TIAO, 2))
	# 条3条4 (incomplete sequence - needs 条5)
	hand.add_card(CardData.new(CardData.Suit.TIAO, 3))
	hand.add_card(CardData.new(CardData.Suit.TIAO, 4))

	print("  手牌总数: %d 张" % hand.get_card_count())
	var ting_cards = WinChecker.check_can_hear(hand)

	print("  🔍 听牌检查结果:")
	print("    听数: %d 种" % ting_cards.size())

	if ting_cards.size() > 0:
		print("  ✅ 通过: 可以听牌")
	else:
		print("  ❌ 失败: 应该能听牌")

	print("")

func test_case_2_2_multiple_ting() -> void:
	"""Test Case 2.2: 多种听牌"""
	print("📋 Test Case 2.2: 多种听牌")

	var hand = CardHand.new()
	# 万1 万2 万3 (顺1)
	hand.add_card(CardData.new(CardData.Suit.WAN, 1))
	hand.add_card(CardData.new(CardData.Suit.WAN, 2))
	hand.add_card(CardData.new(CardData.Suit.WAN, 3))
	# 万4 万5 万6 (顺2)
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	hand.add_card(CardData.new(CardData.Suit.WAN, 5))
	hand.add_card(CardData.new(CardData.Suit.WAN, 6))
	# 筒7 筒8 (还差1张完成顺/刻)
	hand.add_card(CardData.new(CardData.Suit.TONG, 7))
	hand.add_card(CardData.new(CardData.Suit.TONG, 8))
	# 条1 条2 条3 (顺3)
	hand.add_card(CardData.new(CardData.Suit.TIAO, 1))
	hand.add_card(CardData.new(CardData.Suit.TIAO, 2))
	hand.add_card(CardData.new(CardData.Suit.TIAO, 3))
	# 字1 字1 (眼)
	hand.add_card(CardData.new(CardData.Suit.ZI, 1))
	hand.add_card(CardData.new(CardData.Suit.ZI, 1))

	var ting_cards = WinChecker.check_can_hear(hand)

	if ting_cards.size() > 1:
		print("  ✅ 通过: 多种听牌")
		print("  📊 听数: %d 种" % ting_cards.size())
	else:
		print("  ⚠️ 听数较少: %d 种" % ting_cards.size())

	print("")

func test_case_2_3_cannot_ting() -> void:
	"""Test Case 2.3: 无法听牌 - 距离太远"""
	print("📋 Test Case 2.3: 无法听牌 (距离太远)")

	var hand = CardHand.new()
	# 万1 万2 (缺1张完成顺)
	hand.add_card(CardData.new(CardData.Suit.WAN, 1))
	hand.add_card(CardData.new(CardData.Suit.WAN, 2))
	# 万4 万4 万4 (刻)
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	# 筒5 筒5 筒5 (刻)
	hand.add_card(CardData.new(CardData.Suit.TONG, 5))
	hand.add_card(CardData.new(CardData.Suit.TONG, 5))
	hand.add_card(CardData.new(CardData.Suit.TONG, 5))
	# 条6 条6 条6 (刻)
	hand.add_card(CardData.new(CardData.Suit.TIAO, 6))
	hand.add_card(CardData.new(CardData.Suit.TIAO, 6))
	hand.add_card(CardData.new(CardData.Suit.TIAO, 6))
	# 字1 字1 (眼)
	hand.add_card(CardData.new(CardData.Suit.ZI, 1))
	hand.add_card(CardData.new(CardData.Suit.ZI, 1))

	var ting_cards = WinChecker.check_can_hear(hand)

	if ting_cards.size() == 0:
		print("  ✅ 通过: 正确识别无法听牌")
	else:
		print("  ❌ 失败: 不应该能听牌 (听数: %d)" % ting_cards.size())

	print("")

func test_case_2_4_complex_ting() -> void:
	"""Test Case 2.4: 复杂听法 - 多种可能"""
	print("📋 Test Case 2.4: 复杂听法")

	var hand = CardHand.new()
	# 万1 万2 万3 万4 万5 (可以听万0或万6)
	hand.add_card(CardData.new(CardData.Suit.WAN, 1))
	hand.add_card(CardData.new(CardData.Suit.WAN, 2))
	hand.add_card(CardData.new(CardData.Suit.WAN, 3))
	hand.add_card(CardData.new(CardData.Suit.WAN, 4))
	hand.add_card(CardData.new(CardData.Suit.WAN, 5))
	# 万6 万6 (可以组成对或刻)
	hand.add_card(CardData.new(CardData.Suit.WAN, 6))
	hand.add_card(CardData.new(CardData.Suit.WAN, 6))
	# 筒1 筒1 筒1 (刻)
	hand.add_card(CardData.new(CardData.Suit.TONG, 1))
	hand.add_card(CardData.new(CardData.Suit.TONG, 1))
	hand.add_card(CardData.new(CardData.Suit.TONG, 1))
	# 条2 条2 条2 (刻)
	hand.add_card(CardData.new(CardData.Suit.TIAO, 2))
	hand.add_card(CardData.new(CardData.Suit.TIAO, 2))
	hand.add_card(CardData.new(CardData.Suit.TIAO, 2))
	# 字3 (还缺眼)
	hand.add_card(CardData.new(CardData.Suit.ZI, 3))

	var ting_cards = WinChecker.check_can_hear(hand)

	if ting_cards.size() > 2:
		print("  ✅ 通过: 复杂听法识别")
		print("  📊 听数: %d 种" % ting_cards.size())
	else:
		print("  ⚠️ 听数: %d 种" % ting_cards.size())

	print("")

func test_discard_pile() -> void:
	"""测试弃牌堆显示"""
	print("\n========== 测试弃牌堆显示 ==========")

	if not game_ui:
		print("⚠ GameUI为空")
		return

	# 添加多张卡牌到弃牌堆
	for i in range(16):
		var suit = i % 3
		var number = (i % 9) + 1
		var card = CardData.new(suit, number)
		game_ui.add_to_discard_pile(card)
		await get_tree().create_timer(0.05).timeout

	print("✓ 弃牌堆显示测试完成 - 已添加16张牌")

func test_opponent_hand() -> void:
	"""测试对手手牌显示"""
	print("\n========== 测试对手手牌显示 ==========")

	if not game_ui:
		print("⚠ GameUI为空")
		return

	# 显示对手的13张背面牌
	game_ui.display_opponent_hand(13)
	print("✓ 对手手牌显示测试完成 - 显示13张背面牌")

func test_complete_flow() -> void:
	"""完整流程测试"""
	print("\n========== 完整游戏流程测试 ==========\n")

	# 1. 显示手牌
	print("[步骤1/5] 显示玩家手牌...")
	test_display_hand()
	await get_tree().create_timer(1.0).timeout

	# 2. 显示对手手牌
	print("\n[步骤2/5] 显示对手手牌...")
	test_opponent_hand()
	await get_tree().create_timer(1.0).timeout

	# 3. 测试卡牌选择
	print("\n[步骤3/5] 测试卡牌选择...")
	test_card_selection()
	await get_tree().create_timer(1.0).timeout

	# 4. 显示弃牌堆
	print("\n[步骤4/5] 显示弃牌堆...")
	test_discard_pile()
	await get_tree().create_timer(1.0).timeout

	# 5. 显示动画
	print("\n[步骤5/5] 显示胡牌动画...")
	await test_animations()

	print("\n========== 完整流程测试完成 ==========\n")

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

	test_ting_check()
	await get_tree().create_timer(0.5).timeout

	test_play_card()

	print("\n========== 所有测试完成 ==========\n")
