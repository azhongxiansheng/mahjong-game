class_name CardHand

var cards: Array = []

func _init() -> void:
	"""初始化空手牌"""
	cards = []

# 添加卡牌
func add_card(card: CardData) -> void:
	"""添加卡牌到手牌"""
	cards.append(card)
	print("添加卡牌: " + card.get_card_name())

# 查找卡牌
func find_card(suit: int, number: int) -> CardData:
	"""查找指定花色和号码的卡牌"""
	for card in cards:
		if card.suit == suit and card.number == number:
			return card
	return null

# 移除卡牌
func remove_card(card: CardData) -> bool:
	"""移除指定卡牌"""
	for i in range(cards.size()):
		if cards[i] == card:
			cards.remove_at(i)
			print("移除卡牌: " + card.get_card_name())
			return true
	return false

# 获取指定花色的所有卡牌
func get_cards_by_suit(suit: int) -> Array:
	"""获取所有同花色的卡牌"""
	var result: Array = []
	for card in cards:
		if card.suit == suit:
			result.append(card)
	return result

# 排序卡牌
func sort_cards() -> void:
	"""按花色和号码排序卡牌"""
	cards.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.suit != b.suit:
			return a.suit < b.suit
		return a.number < b.number
	)
	print("卡牌已排序")

# 显示手牌
func print_hand() -> void:
	"""打印当前手牌"""
	print("\n当前手牌 (%d张):" % cards.size())
	for i in range(cards.size()):
		print("  %d. %s" % [i + 1, cards[i].get_card_name()])
	print("")

# 获取手牌数量
func get_card_count() -> int:
	"""获取手牌数量"""
	return cards.size()

# 清空手牌
func clear() -> void:
	"""清空所有手牌"""
	cards.clear()
	print("手牌已清空")
