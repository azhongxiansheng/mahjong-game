# 特殊胜牌检测器 - 用于检测七对、十三幺等特殊牌型
class_name SpecialWinChecker

# 检查七对 (7组配对)
static func check_seven_pairs(hand: CardHand) -> bool:
	if hand.get_card_count() != 14:
		return false

	# 计算每种牌的数量
	var card_count: Dictionary = {}
	for card in hand.cards:
		var key = "%d_%d" % [card.suit, card.number]
		card_count[key] = card_count.get(key, 0) + 1

	# 检查是否所有牌都成对
	var pair_count = 0
	for count in card_count.values():
		if count != 2:
			return false
		pair_count += 1

	return pair_count == 7

# 检查十三幺 (13种老牌)
static func check_thirteen_orphans(hand: CardHand) -> bool:
	if hand.get_card_count() != 14:
		return false

	# 统计手中的老牌
	var orphan_count: Dictionary = {}
	for card in hand.cards:
		if _is_orphan(card):
			var key = "%d_%d" % [card.suit, card.number]
			orphan_count[key] = orphan_count.get(key, 0) + 1

	# 检查: 13种老牌，其中12种各1张，1种2张
	if orphan_count.size() != 13:
		return false

	var pairs = 0
	for count in orphan_count.values():
		if count > 2:
			return false
		if count == 2:
			pairs += 1

	return pairs == 1

# 检查清一色 (所有牌同一花色)
static func check_all_one_suit(hand: CardHand) -> bool:
	if hand.get_card_count() != 14:
		return false

	if hand.cards.size() == 0:
		return false

	var first_suit = hand.cards[0].suit

	for card in hand.cards:
		if card.suit != first_suit:
			return false

	# 必须能形成一个有效的胜手
	return true

# 检查字牌清 (所有字牌)
static func check_all_honor(hand: CardHand) -> bool:
	if hand.get_card_count() != 14:
		return false

	for card in hand.cards:
		if card.suit != 3:  # 3是字牌花色
			return false

	return true

# 检查数字清 (只有数字牌)
static func check_all_numeric(hand: CardHand) -> bool:
	if hand.get_card_count() != 14:
		return false

	for card in hand.cards:
		if card.suit >= 3:  # 3以上是字牌
			return false

	return true

# 获取胜牌类型
static func detect_win_type(hand: CardHand) -> String:
	if check_seven_pairs(hand):
		return "七对"
	elif check_thirteen_orphans(hand):
		return "十三幺"
	elif check_all_honor(hand):
		return "字牌清"
	elif check_all_numeric(hand):
		return "数字清"
	elif check_all_one_suit(hand):
		return "清一色"
	else:
		return "标准胜牌"

# 获取胜牌得分 (简单评分系统)
static func get_win_score(win_type: String) -> int:
	match win_type:
		"七对":
			return 50
		"十三幺":
			return 100
		"字牌清":
			return 60
		"数字清":
			return 40
		"清一色":
			return 30
		"标准胜牌":
			return 10
		_:
			return 0

# 辅助函数: 检查是否是老牌
static func _is_orphan(card: CardData) -> bool:
	# 数字牌的1或9
	if card.suit < 3 and (card.number == 1 or card.number == 9):
		return true

	# 字牌
	if card.suit == 3:
		return true

	return false
