class_name HuRule

# 胡牌规则和番数计算类

## 胡牌类型枚举
enum HuType {
	BASIC,          # 基本胡
	ALL_PUNG,       # 全刻
	ALL_CHOW,       # 全顺
	SINGLE_SUIT,    # 清一色
	TERMINAL,       # 清老头（只有1和9）
	ALL_TERMINAL,   # 全老头
	SPECIAL,        # 特殊胡法
}

## 番数等级
enum Fan {
	FAN_1 = 1,
	FAN_2 = 2,
	FAN_3 = 3,
	FAN_6 = 6,
	FAN_8 = 8,
}

# 计算胡牌的番数
static func calculate_fan(win_result: WinResult, hand: CardHand) -> int:
	"""
	根据胡牌结果计算番数
	返回：总番数
	"""
	if not win_result or not win_result.can_win:
		return 0

	var total_fan = Fan.FAN_1  # 基本胡1番

	# 获取所有牌（包括眼睛）
	var all_cards: Array[CardData] = []
	for card in hand.cards:
		all_cards.append(card)
	if win_result.eye_card:
		all_cards.append(win_result.eye_card)

	# 检查特殊胡法
	if is_all_pung(win_result):
		total_fan += Fan.FAN_1  # 全刻 1番

	if is_all_chow(win_result):
		total_fan += Fan.FAN_1  # 全顺 1番

	if is_single_suit(all_cards):
		total_fan += Fan.FAN_6  # 清一色 6番

	if is_all_terminal(all_cards):
		total_fan += Fan.FAN_8  # 全老头 8番

	if is_terminal(all_cards):
		total_fan += Fan.FAN_2  # 清老头 2番

	return total_fan

# 检查是否全是刻子
static func is_all_pung(win_result: WinResult) -> bool:
	"""检查是否全是刻子（包括杠）"""
	if not win_result or win_result.win_patterns.is_empty():
		return false

	for pattern in win_result.win_patterns:
		if pattern is Dictionary and "melds" in pattern:
			var melds = pattern["melds"]
			for meld in melds:
				if meld is Dictionary and meld.get("type") != "pung":
					return false

	return true

# 检查是否全是顺子
static func is_all_chow(win_result: WinResult) -> bool:
	"""检查是否全是顺子"""
	if not win_result or win_result.win_patterns.is_empty():
		return false

	for pattern in win_result.win_patterns:
		if pattern is Dictionary and "melds" in pattern:
			var melds = pattern["melds"]
			for meld in melds:
				if meld is Dictionary and meld.get("type") != "chow":
					return false

	return true

# 检查是否清一色（只有一种花色）
static func is_single_suit(cards: Array[CardData]) -> bool:
	"""检查是否清一色"""
	if cards.is_empty():
		return false

	var suit = cards[0].suit
	for card in cards:
		if card.suit != suit:
			return false

	return true

# 检查是否清老头（只有1和9）
static func is_terminal(cards: Array[CardData]) -> bool:
	"""检查是否清老头（数字牌中只有1和9）"""
	for card in cards:
		if card.suit < 3:  # 数字牌
			if card.number != 1 and card.number != 9:
				return false
		# 字牌不算

	# 必须有数字牌
	var has_number = false
	for card in cards:
		if card.suit < 3:
			has_number = true
			break

	return has_number

# 检查是否全老头（只有字牌和1、9）
static func is_all_terminal(cards: Array[CardData]) -> bool:
	"""检查是否全老头（数字牌只有1和9，加上字牌）"""
	var has_honor = false
	var has_number = false

	for card in cards:
		if card.suit == 3:  # 字牌
			has_honor = true
		elif card.suit < 3:  # 数字牌
			has_number = true
			if card.number != 1 and card.number != 9:
				return false

	# 必须同时有字牌和老头牌
	return has_honor and has_number

# 获取胡牌类型名称
static func get_hu_type_name(win_result: WinResult, hand: CardHand) -> String:
	"""获取胡牌类型的名称"""
	if is_all_terminal(hand.cards):
		return "全老头"
	elif is_terminal(hand.cards):
		return "清老头"
	elif is_single_suit(hand.cards):
		return "清一色"
	elif is_all_chow(win_result):
		return "全顺"
	elif is_all_pung(win_result):
		return "全刻"
	else:
		return "平胡"

# 打印胡牌信息
static func print_win_info(win_result: WinResult, hand: CardHand) -> void:
	"""打印详细的胡牌信息"""
	if not win_result or not win_result.can_win:
		print("✗ 未能胡牌")
		return

	var fan = calculate_fan(win_result, hand)
	var hu_type = get_hu_type_name(win_result, hand)

	print("✓ 胡牌成功！")
	print("  胡牌类型: %s" % hu_type)
	print("  番数: %d 番" % fan)

	if win_result.eye_card:
		print("  将: %s" % win_result.eye_card.get_card_name())

	if not win_result.win_patterns.is_empty():
		var pattern = win_result.win_patterns[0]
		if pattern is Dictionary and "melds" in pattern:
			var melds = pattern["melds"]
			print("  面子:")
			for meld in melds:
				if meld is Dictionary:
					var meld_type = meld.get("type", "unknown")
					if meld_type == "pung":
						print("    - 刻子（3张相同）")
					elif meld_type == "chow":
						print("    - 顺子（3张连续）")
