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

func get_display_name() -> String:
	"""获取卡牌显示名称（数字或字牌名称）"""
	# 字牌显示中文名
	if suit == Suit.ZI:
		match number:
			1: return "东"
			2: return "南"
			3: return "西"
			4: return "北"
			5: return "中"
			6: return "发"
			7: return "白"
			_: return "?"
	else:
		# 数字牌显示数字
		return str(number)

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
