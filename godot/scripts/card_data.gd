class_name CardData

# 卡牌花色枚举
enum Suit { WAN = 0, TONG = 1, TIAO = 2, ZI = 3 }  # 万、筒、条、字

# 卡牌属性
var suit: Suit
var number: int
var id: int

func _init(p_suit: Suit, p_number: int) -> void:
	"""初始化卡牌"""
	suit = p_suit
	number = p_number
	id = int(suit) * 10 + p_number

func get_card_name() -> String:
	"""获取卡牌名称"""
	var suit_names = ["万", "筒", "条", "字"]
	return suit_names[suit] + str(number)

func can_pair_with(other: CardData) -> bool:
	"""判断是否能和另一张卡配对（完全相同）"""
	return suit == other.suit and number == other.number

func get_rank() -> String:
	"""根据号码返回等级"""
	if number == 1:
		return "幺"
	elif number <= 5:
		return "小"
	else:
		return "大"

func _to_string() -> String:
	"""转换为字符串"""
	return get_card_name()
