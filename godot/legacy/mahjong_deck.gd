extends CardDeck

class_name MahjongDeck

func _init() -> void:
	"""初始化标准麻将牌池（108张）"""
	super._init()
	generate_standard_deck()

func generate_standard_deck() -> void:
	"""生成标准麻将牌（108张）"""
	print("生成标准麻将牌池...")

	# 标准麻将: 万、筒、条各36张 (1-9每种4张)
	# 共108张
	for suit in range(3):  # 只生成万、筒、条三种花色
		for number in range(1, 10):
			for count in range(4):  # 每种4张
				var card = CardData.new(suit, number)
				cards.append(card)

	print("✓ 麻将牌池已生成：%d 张卡牌" % cards.size())

func draw_initial_hand(count: int = 13) -> Array:
	"""抽初始手牌（默认13张）"""
	print("\n抽初始手牌 (%d 张)..." % count)
	return draw_cards(count)

func draw_one() -> CardData:
	"""抽一张牌"""
	return draw_card()

func get_deck_status() -> void:
	"""打印牌池状态"""
	var info = get_deck_info()
	print("\n【牌池状态】")
	print("  总牌数: 108")
	print("  剩余: %d" % info["remaining"])
	print("  弃牌: %d" % info["discarded"])
	print("  进度: %.1f%%" % ((108.0 - info["remaining"]) / 108.0 * 100))
