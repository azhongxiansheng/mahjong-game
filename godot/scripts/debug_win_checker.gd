class_name DebugWinChecker

# 调试 WinChecker 的脚本

static func test_basic_win() -> void:
	"""测试基本胡牌"""
	print("\n=== 调试基本胡牌 ===")
	
	var hand = CardHand.new()
	# 手牌: 万1万1 万2万3万4 筒5筒5筒5 条6条7条8 条9条9
	hand.add_card(CardData.new(0, 1))  # 万1
	hand.add_card(CardData.new(0, 1))  # 万1
	hand.add_card(CardData.new(0, 2))  # 万2
	hand.add_card(CardData.new(0, 3))  # 万3
	hand.add_card(CardData.new(0, 4))  # 万4
	hand.add_card(CardData.new(1, 5))  # 筒5
	hand.add_card(CardData.new(1, 5))  # 筒5
	hand.add_card(CardData.new(1, 5))  # 筒5
	hand.add_card(CardData.new(2, 6))  # 条6
	hand.add_card(CardData.new(2, 7))  # 条7
	hand.add_card(CardData.new(2, 8))  # 条8
	hand.add_card(CardData.new(2, 9))  # 条9
	hand.add_card(CardData.new(2, 9))  # 条9
	
	print("手牌数量: %d" % hand.get_card_count())
	print("手牌: ", end="")
	for card in hand.cards:
		print("%s " % card.get_card_name(), end="")
	print()
	
	# 测试胡牌
	var result = WinChecker.check_win(hand)
	print("能否胡牌: %s" % result.can_win)
	
	if result.can_win:
		print("✓ 成功！")
		if result.eye_card:
			print("眼睛: %s" % result.eye_card.get_card_name())
	else:
		print("✗ 失败 - 应该能胡但没有")
		# 手动调试
		_manual_debug(hand)

static func _manual_debug(hand: CardHand) -> void:
	"""手动调试为什么不能胡"""
	print("\n--- 手动调试 ---")
	
	# 尝试移除万1作为眼睛
	print("尝试用万1作为眼睛...")
	var test_hand = CardHand.new()
	for card in hand.cards:
		test_hand.add_card(card)
	
	# 移除两个万1
	var removed = 0
	for i in range(test_hand.cards.size() - 1, -1, -1):
		if removed < 2 and test_hand.cards[i].suit == 0 and test_hand.cards[i].number == 1:
			test_hand.cards.remove_at(i)
			removed += 1
	
	print("移除眼睛后的手牌数: %d" % test_hand.get_card_count())
	print("手牌: ", end="")
	for card in test_hand.cards:
		print("%s " % card.get_card_name(), end="")
	print()
	
	# 检查这12张牌是否能组成4组
	var can_form = _test_can_form_melds(test_hand.cards)
	print("能否组成4组: %s" % can_form)

static func _test_can_form_melds(cards: Array[CardData]) -> bool:
	"""测试版本的形成面子检查"""
	print("\n  开始递归...")
	return _recursive_test(cards, 0)

static func _recursive_test(cards: Array[CardData], depth: int) -> bool:
	"""递归测试"""
	var indent = "    " * depth
	
	if cards.is_empty():
		print("%s✓ 空了，成功！" % indent)
		return true
	
	# 排序
	var sorted_cards = (cards.duplicate()) as Array[CardData]
	sorted_cards.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.suit != b.suit:
			return a.suit < b.suit
		return a.number < b.number
	)
	
	var first = sorted_cards[0]
	print("%s测试 %s..." % [indent, first.get_card_name()])
	
	# 尝试刻子
	var count_first = 0
	for card in sorted_cards:
		if card.suit == first.suit and card.number == first.number:
			count_first += 1
	
	if count_first >= 3:
		print("%s  尝试刻子 (%d个%s)" % [indent, count_first, first.get_card_name()])
		var remaining = _remove_cards_test(sorted_cards, first.suit, first.number, 3)
		if _recursive_test(remaining, depth + 1):
			return true
	
	# 尝试顺子
	if first.suit < 3 and first.number <= 7:
		if _has_card_test(sorted_cards, first.suit, first.number + 1) and \
		   _has_card_test(sorted_cards, first.suit, first.number + 2):
			print("%s  尝试顺子 (%s%s%s)" % [indent, first.get_card_name(), CardData.new(first.suit, first.number + 1).get_card_name(), CardData.new(first.suit, first.number + 2).get_card_name()])
			var remaining = _remove_cards_test(sorted_cards, first.suit, first.number, 1)
			remaining = _remove_cards_test(remaining, first.suit, first.number + 1, 1)
			remaining = _remove_cards_test(remaining, first.suit, first.number + 2, 1)
			if _recursive_test(remaining, depth + 1):
				return true
	
	print("%s✗ 无法继续" % indent)
	return false

static func _has_card_test(cards: Array[CardData], suit: int, number: int) -> bool:
	for card in cards:
		if card.suit == suit and card.number == number:
			return true
	return false

static func _remove_cards_test(cards: Array[CardData], suit: int, number: int, count: int) -> Array[CardData]:
	var result = cards.duplicate()
	var removed = 0
	for i in range(result.size() - 1, -1, -1):
		if removed >= count:
			break
		if result[i].suit == suit and result[i].number == number:
			result.remove_at(i)
			removed += 1
	return result
