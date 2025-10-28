class_name CardDeck

var cards: Array = []
var discard_pile: Array = []  # 弃牌堆

func _init() -> void:
	"""初始化空牌池"""
	cards = []
	discard_pile = []

func add_card(card: CardData) -> void:
	"""添加卡牌到牌池"""
	cards.append(card)
	print("添加卡牌到牌池: %s (剩余: %d)" % [card.get_card_name(), cards.size()])

func add_cards(new_cards: Array) -> void:
	"""添加多张卡牌到牌池"""
	for card in new_cards:
		cards.append(card)

func draw_card() -> CardData:
	"""从牌池抽一张卡"""
	if cards.size() == 0:
		print("牌池为空！")
		return null
	var card = cards.pop_front()
	print("抽卡: %s (剩余: %d)" % [card.get_card_name(), cards.size()])
	return card

func draw_cards(count: int) -> Array:
	"""抽多张卡"""
	var result: Array = []
	for i in range(count):
		if cards.size() > 0:
			result.append(draw_card())
		else:
			break
	return result

func discard_card(card: CardData) -> void:
	"""将卡牌放入弃牌堆"""
	discard_pile.append(card)
	print("弃牌: %s (弃牌堆: %d)" % [card.get_card_name(), discard_pile.size()])

func shuffle() -> void:
	"""洗牌"""
	cards.shuffle()
	print("牌池已洗牌，共 %d 张" % cards.size())

func get_remaining_count() -> int:
	"""获取剩余卡牌数"""
	return cards.size()

func get_deck_info() -> Dictionary:
	"""获取牌池信息"""
	return {
		"remaining": cards.size(),
		"discarded": discard_pile.size()
	}

func clear() -> void:
	"""清空牌池"""
	cards.clear()
	discard_pile.clear()
	print("牌池已清空")
