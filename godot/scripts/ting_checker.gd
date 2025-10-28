class_name TingChecker

# 听牌检测器类 - 优化版
# 比 WinChecker.check_can_hear() 更快，只关注听牌检测

# 检测是否能听牌（返回能听的牌列表）
static func check_ting(hand: CardHand) -> TingResult:
	"""
	检测手牌是否能听牌
	使用缓存和优化算法提高性能
	"""
	var result = TingResult.new()
	
	if not hand or hand.get_card_count() != 13:
		return result
	
	# 尝试检测每张可能的牌
	var ting_cards_found: Array[CardData] = [] as Array[CardData]
	
	# 检查特定牌（只需检查已有的花色）
	var suits_to_check = _get_relevant_suits(hand)
	
	for suit in suits_to_check:
		var max_num = 9 if suit < 3 else 7
		for number in range(1, max_num + 1):
			var test_card = CardData.new(suit, number)
			
			# 快速检测是否能胡这张牌
			if _can_win_with_card(hand, test_card):
				ting_cards_found.append(test_card)
	
	if not ting_cards_found.is_empty():
		result.can_ting = true
		result.ting_cards = ting_cards_found
		result.ting_count = ting_cards_found.size()
		result.is_ting_tightly = (ting_cards_found.size() == 1)
	
	return result

# 私有：快速检测是否能胡特定的牌
static func _can_win_with_card(hand: CardHand, card: CardData) -> bool:
	"""快速检测是否能胡特定牌"""
	var test_hand = CardHand.new()
	for c in hand.cards:
		test_hand.add_card(c)
	
	var result = WinChecker.check_win(test_hand, card)
	return result.can_win

# 私有：获取需要检查的花色
static func _get_relevant_suits(hand: CardHand) -> Array:
	"""获取手中已有的花色，避免检查完全没有的花色"""
	var suits_present = {}
	for card in hand.cards:
		suits_present[card.suit] = true
	
	# 总是检查1-3号花色（数字牌），但对字牌要检查
	var result = [0, 1, 2]  # 万、筒、条
	if 3 in suits_present:
		result.append(3)  # 字牌
	
	return result

# 获取听牌描述文本
static func get_ting_description(ting_result: TingResult) -> String:
	"""获取听牌的文字描述"""
	if not ting_result.can_ting:
		return "未听牌"
	
	var desc = ""
	if ting_result.is_ting_tightly:
		desc = "紧听"
	else:
		desc = "%d听" % ting_result.ting_count
	
	# 列出听牌
	var cards_str = ""
	for i in range(min(3, ting_result.ting_cards.size())):  # 最多显示3张
		if i > 0:
			cards_str += "、"
		cards_str += ting_result.ting_cards[i].get_card_name()
	
	if ting_result.ting_cards.size() > 3:
		cards_str += "等"
	
	return "%s（%s）" % [desc, cards_str]

# 获取最优听牌（倾向于保留更多选择）
static func get_best_ting(ting_result: TingResult) -> Array[CardData]:
	"""获取最优的听牌牌组合（可能有多个等价的选择）"""
	if not ting_result.can_ting:
		return []
	
	return ting_result.ting_cards

# 计算听牌收益（简单版）
static func calculate_ting_value(ting_result: TingResult, hand: CardHand) -> int:
	"""
	计算听牌的价值
	更多听数 = 更高价值
	"""
	if not ting_result.can_ting:
		return 0
	
	# 简单评分：听数 × 100 + 手牌整体质量
	var base_score = ting_result.ting_count * 100
	
	# 奖励：如果是紧听但能胡很好的牌（如清一色）
	if ting_result.is_ting_tightly:
		base_score += 50  # 紧听通常更激进
	
	return base_score
