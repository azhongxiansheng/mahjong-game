class_name DebugWinChecker

# 调试脚本：详细分析胡牌和听牌问题

static func debug_clear_win() -> void:
	"""调试清一色胡牌"""
	print("\n【调试】清一色（All One Suit）胡牌测试")
	var separator = ""
	for i in range(60):
		separator += "="
	print(separator)

	# 测试1: 简单的清一色
	print("\n测试1: 简单清一色")
	var sep1 = ""
	for i in range(40):
		sep1 += "-"
	print(sep1)
	var hand1 = CardHand.new()
	# 万1万1万1 万2万3万4 万5万6万7 万8万9万9万9 (14张)
	hand1.add_card(CardData.new(0, 1))
	hand1.add_card(CardData.new(0, 1))
	hand1.add_card(CardData.new(0, 1))
	hand1.add_card(CardData.new(0, 2))
	hand1.add_card(CardData.new(0, 3))
	hand1.add_card(CardData.new(0, 4))
	hand1.add_card(CardData.new(0, 5))
	hand1.add_card(CardData.new(0, 6))
	hand1.add_card(CardData.new(0, 7))
	hand1.add_card(CardData.new(0, 8))
	hand1.add_card(CardData.new(0, 9))
	hand1.add_card(CardData.new(0, 9))
	hand1.add_card(CardData.new(0, 9))
	hand1.add_card(CardData.new(0, 1))  # 第14张

	print("手牌: 万1万1万1 万2万3万4 万5万6万7 万8万9万9万9")
	print("牌数: %d" % hand1.get_card_count())
	_debug_hand(hand1)

	var result1 = WinChecker.check_win(hand1)
	print("能否胡牌: %s" % ("是" if result1.can_win else "否"))
	if not result1.can_win:
		print(">>> 问题：清一色应该能胡，但检测失败！")
	print()

	# 测试2: 另一个清一色变体
	print("测试2: 清一色变体")
	var sep2b = ""
	for i in range(40):
		sep2b += "-"
	print(sep2b)
	var hand2 = CardHand.new()
	# 万2万2万2 万3万4万5 万6万7万8 万9万9 万1万1万1 (14张)
	hand2.add_card(CardData.new(0, 2))
	hand2.add_card(CardData.new(0, 2))
	hand2.add_card(CardData.new(0, 2))
	hand2.add_card(CardData.new(0, 3))
	hand2.add_card(CardData.new(0, 4))
	hand2.add_card(CardData.new(0, 5))
	hand2.add_card(CardData.new(0, 6))
	hand2.add_card(CardData.new(0, 7))
	hand2.add_card(CardData.new(0, 8))
	hand2.add_card(CardData.new(0, 9))
	hand2.add_card(CardData.new(0, 9))
	hand2.add_card(CardData.new(0, 1))
	hand2.add_card(CardData.new(0, 1))
	hand2.add_card(CardData.new(0, 1))

	print("手牌: 万2万2万2 万3万4万5 万6万7万8 万9万9 万1万1万1")
	print("牌数: %d" % hand2.get_card_count())
	_debug_hand(hand2)

	var result2 = WinChecker.check_win(hand2)
	print("能否胡牌: %s" % ("是" if result2.can_win else "否"))
	print()

static func debug_ting_detection() -> void:
	"""调试听牌检测"""
	print("\n【调试】听牌检测测试")
	var sep = ""
	for i in range(60):
		sep += "="
	print(sep)

	# 测试1: 基本听牌（13张手牌）
	print("\n测试1: 基本听牌")
	var sep2 = ""
	for i in range(40):
		sep2 += "-"
	print(sep2)
	var hand1 = CardHand.new()
	# 万1万1 万2万3万4 筒5筒5筒5 条6条7条8 条9 (13张)
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

	print("手牌: 万1万1 万2万3万4 筒5筒5筒5 条6条7条8 条9 (13张)")
	print("牌数: %d" % hand1.get_card_count())
	_debug_hand(hand1)

	# 测试听牌
	var ting_result = TingChecker.check_ting(hand1)
	print("能否听牌: %s" % ("是" if ting_result.can_ting else "否"))
	if ting_result.can_ting:
		print("听牌数量: %d" % ting_result.ting_count)
		print("听牌描述: %s" % TingChecker.get_ting_description(ting_result))
		print("听牌列表:")
		for card in ting_result.ting_cards:
			print("  - %s" % card.get_card_name())
	else:
		print(">>> 问题：这个手牌应该能听牌，但检测失败！")
	print()

static func _debug_hand(hand: CardHand) -> void:
	"""打印手牌详细信息"""
	print("花色分布:")
	var suits = [[], [], [], []]
	for card in hand.cards:
		suits[card.suit].append(card.number)

	var suit_names = ["万", "筒", "条", "字"]
	for suit in range(4):
		if not suits[suit].is_empty():
			suits[suit].sort()
			var nums_str = ""
			for num in suits[suit]:
				nums_str += str(num)
			print("  %s: %s" % [suit_names[suit], nums_str])

# 运行所有调试
static func run_all_debug() -> void:
	"""运行所有调试测试"""
	var sep = ""
	for i in range(60):
		sep += "="

	print("\n" + sep)
	print("开始详细调试...")
	print(sep)

	debug_clear_win()
	debug_ting_detection()

	print("\n" + sep)
	print("调试完成！")
	print(sep)
