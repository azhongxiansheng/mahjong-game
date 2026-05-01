# LegacyWinPattern (旧中式麻将牌型识别)
# class_name 已移除以避免与 core/rules_japanese/win_pattern.gd (日麻 WinPattern) 冲突。
# 仅作旧 scripts/ 下中式麻将代码的内部 helper；如需引用请 preload。
#
# 牌型识别类
# 用于识别和分类各种麻将牌型（顺子、刻子、对子等）

## 牌型枚举
enum PatternType {
	UNKNOWN,      # 未知牌型
	PUNG,         # 刻子（三张相同）
	KONG,         # 杠（四张相同）
	CHOW,         # 顺子（三张连续）
	PAIR,         # 对子（两张相同）
	SINGLE,       # 单张
}

# 检测顺子（三张连续的数字牌）
static func is_chow(cards: Array[CardData]) -> bool:
	"""检测是否为顺子（必须是三张连续的数字牌）"""
	if cards.size() != 3:
		return false

	# 字牌不能组成顺子
	for card in cards:
		if card.suit == 3:  # suit 3 是字牌
			return false

	# 对所有花色中的数字牌进行排序
	var sorted_cards = cards.duplicate()
	sorted_cards.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.suit != b.suit:
			return a.suit < b.suit
		return a.number < b.number
	)

	# 检测是否连续
	if sorted_cards[0].suit == sorted_cards[1].suit and sorted_cards[1].suit == sorted_cards[2].suit:
		if sorted_cards[0].number + 1 == sorted_cards[1].number and sorted_cards[1].number + 1 == sorted_cards[2].number:
			return true

	return false

# 检测刻子（三张相同的牌）
static func is_pung(cards: Array[CardData]) -> bool:
	"""检测是否为刻子（三张相同）"""
	if cards.size() != 3:
		return false

	return cards[0].suit == cards[1].suit and cards[1].suit == cards[2].suit and \
		   cards[0].number == cards[1].number and cards[1].number == cards[2].number

# 检测杠（四张相同的牌）
static func is_kong(cards: Array[CardData]) -> bool:
	"""检测是否为杠（四张相同）"""
	if cards.size() != 4:
		return false

	return cards[0].suit == cards[1].suit and cards[1].suit == cards[2].suit and cards[2].suit == cards[3].suit and \
		   cards[0].number == cards[1].number and cards[1].number == cards[2].number and cards[2].number == cards[3].number

# 检测对子（两张相同的牌）
static func is_pair(cards: Array[CardData]) -> bool:
	"""检测是否为对子（两张相同）"""
	if cards.size() != 2:
		return false

	return cards[0].suit == cards[1].suit and cards[0].number == cards[1].number

# 检测牌型
static func identify_pattern(cards: Array[CardData]) -> PatternType:
	"""识别牌型"""
	if is_kong(cards):
		return PatternType.KONG
	elif is_pung(cards):
		return PatternType.PUNG
	elif is_chow(cards):
		return PatternType.CHOW
	elif is_pair(cards):
		return PatternType.PAIR
	elif cards.size() == 1:
		return PatternType.SINGLE

	return PatternType.UNKNOWN

# 牌型名称
static func get_pattern_name(pattern_type: PatternType) -> String:
	"""获取牌型名称"""
	match pattern_type:
		PatternType.PUNG:
			return "刻子"
		PatternType.KONG:
			return "杠"
		PatternType.CHOW:
			return "顺子"
		PatternType.PAIR:
			return "对子"
		PatternType.SINGLE:
			return "单张"
		_:
			return "未知"

# 检测是否为番（特殊牌型组合）
static func check_all_pung(patterns: Array) -> bool:
	"""检测是否全是刻子"""
	for pattern in patterns:
		if pattern is Dictionary and pattern.get("type") != PatternType.PUNG and pattern.get("type") != PatternType.KONG:
			return false
	return true

static func check_all_chow(patterns: Array) -> bool:
	"""检测是否全是顺子"""
	for pattern in patterns:
		if pattern is Dictionary and pattern.get("type") != PatternType.CHOW:
			return false
	return true

static func check_all_simple(cards: Array[CardData]) -> bool:
	"""检测是否全是老头牌（1和9）"""
	for card in cards:
		if card.suit == 3:  # 字牌
			return false
		if card.number != 1 and card.number != 9:
			return false
	return true

static func check_single_suit(cards: Array[CardData]) -> bool:
	"""检测是否清一色（只有一种花色）"""
	if cards.is_empty():
		return false

	var suit = cards[0].suit
	for card in cards:
		if card.suit != suit:
			return false
	return true
