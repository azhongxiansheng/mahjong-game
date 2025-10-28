class_name WinChecker

# 胡牌判断器类
# 使用递归回溯法判断是否能胡牌

# 检查是否能胡牌
static func check_win(hand: CardHand, drawn_card: CardData = null) -> WinResult:
	"""
	检查手牌是否能胡牌
	hand: 玩家手牌
	drawn_card: 新抽的牌（可选）
	返回：胡牌结果
	"""
	var result = WinResult.new()

	if not hand or hand.get_card_count() == 0:
		return result

	# 获取要检查的牌
	var cards_to_check: Array[CardData] = []
	if drawn_card:
		cards_to_check = hand.cards.duplicate()
		cards_to_check.append(drawn_card)
	else:
		cards_to_check = hand.cards.duplicate()

	# 检查牌数是否正确（14张或13张）
	if cards_to_check.size() != 14 and cards_to_check.size() != 13:
		return result

	# 尝试找到眼睛（对子）
	var pair_map = _count_cards(cards_to_check)
	for suit_idx in range(4):
		for num_idx in range(1, 10):
			var card_key = "%d_%d" % [suit_idx, num_idx]
			if card_key in pair_map and pair_map[card_key] >= 2:
				# 找到可能的对子
				var remaining = cards_to_check.duplicate()

				# 移除对子
				var removed_count = 0
				var eye_card_found: CardData = null
				for i in range(remaining.size() - 1, -1, -1):
					if removed_count < 2:
						var card = remaining[i]
						if card.suit == suit_idx and card.number == num_idx:
							eye_card_found = card
							remaining.remove_at(i)
							removed_count += 1

				# 检查剩余的牌是否能组成完整的顺序
				if _can_form_melds(remaining):
					result.can_win = true
					result.eye_card = eye_card_found
					result.win_patterns.append({
						"eye": eye_card_found,
						"melds": _extract_melds(remaining)
					})

	return result

# 检查是否能听牌（缺一张牌就能胡）
static func check_can_hear(hand: CardHand) -> Array:
	"""
	检查哪些牌能听牌（缺一张牌就能胡）
	返回：能听的牌列表
	"""
	var winnable_cards: Array = []

	# 尝试所有可能的牌
	for suit in range(4):
		var max_num = 9 if suit < 3 else 7  # 字牌只有7种
		for number in range(1, max_num + 1):
			var test_card = CardData.new(suit, number)

			# 创建临时手牌进行测试
			var test_hand = CardHand.new()
			for card in hand.cards:
				test_hand.add_card(card)

			# 测试能否胡这张牌
			var result = check_win(test_hand, test_card)
			if result.can_win:
				winnable_cards.append(test_card)

	return winnable_cards

# 私有方法：计算牌的数量
static func _count_cards(cards: Array[CardData]) -> Dictionary:
	"""计算每种牌的数量"""
	var count_map = {}
	for card in cards:
		var key = "%d_%d" % [card.suit, card.number]
		count_map[key] = count_map.get(key, 0) + 1
	return count_map

# 私有方法：检查剩余牌是否能组成完整的面子
static func _can_form_melds(cards: Array[CardData]) -> bool:
	"""
	递归检查剩余的牌是否能组成4组面子（顺子或刻子）
	使用回溯法
	"""
	if cards.is_empty():
		return true

	# 按花色和数字排序
	var sorted_cards = cards.duplicate()
	sorted_cards.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.suit != b.suit:
			return a.suit < b.suit
		return a.number < b.number
	)

	# 尝试第一张牌开始的所有可能组合
	var first_card = sorted_cards[0]

	# 尝试刻子（三张相同）
	if _count_matching_cards(sorted_cards, first_card.suit, first_card.number) >= 3:
		var remaining = _remove_cards(sorted_cards, first_card.suit, first_card.number, 3)
		if _can_form_melds(remaining):
			return true

	# 尝试顺子（只有数字牌）
	if first_card.suit < 3 and first_card.number <= 7:
		if _has_card(sorted_cards, first_card.suit, first_card.number + 1) and \
		   _has_card(sorted_cards, first_card.suit, first_card.number + 2):
			var remaining = _remove_cards(sorted_cards, first_card.suit, first_card.number, 1)
			remaining = _remove_cards(remaining, first_card.suit, first_card.number + 1, 1)
			remaining = _remove_cards(remaining, first_card.suit, first_card.number + 2, 1)
			if _can_form_melds(remaining):
				return true

	return false

# 私有方法：计算匹配的牌数
static func _count_matching_cards(cards: Array[CardData], suit: int, number: int) -> int:
	"""计算符合条件的牌的数量"""
	var count = 0
	for card in cards:
		if card.suit == suit and card.number == number:
			count += 1
	return count

# 私有方法：移除牌
static func _remove_cards(cards: Array[CardData], suit: int, number: int, count: int) -> Array[CardData]:
	"""移除指定的牌"""
	var result = cards.duplicate()
	var removed = 0
	for i in range(result.size() - 1, -1, -1):
		if removed >= count:
			break
		if result[i].suit == suit and result[i].number == number:
			result.remove_at(i)
			removed += 1
	return result

# 私有方法：检查是否有指定的牌
static func _has_card(cards: Array[CardData], suit: int, number: int) -> bool:
	"""检查是否存在指定的牌"""
	for card in cards:
		if card.suit == suit and card.number == number:
			return true
	return false

# 私有方法：提取面子信息
static func _extract_melds(cards: Array[CardData]) -> Array:
	"""提取面子信息"""
	var melds: Array = []
	var sorted_cards = cards.duplicate()

	while not sorted_cards.is_empty():
		var first = sorted_cards[0]

		# 检查是否为刻子
		if _count_matching_cards(sorted_cards, first.suit, first.number) >= 3:
			melds.append({
				"type": "pung",
				"cards": [first]
			})
			sorted_cards = _remove_cards(sorted_cards, first.suit, first.number, 3)
		# 检查是否为顺子
		elif first.suit < 3 and _has_card(sorted_cards, first.suit, first.number + 1) and \
			 _has_card(sorted_cards, first.suit, first.number + 2):
			melds.append({
				"type": "chow",
				"cards": [first, CardData.new(first.suit, first.number + 1), CardData.new(first.suit, first.number + 2)]
			})
			sorted_cards = _remove_cards(sorted_cards, first.suit, first.number, 1)
			sorted_cards = _remove_cards(sorted_cards, first.suit, first.number + 1, 1)
			sorted_cards = _remove_cards(sorted_cards, first.suit, first.number + 2, 1)
		else:
			break

	return melds
