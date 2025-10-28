class_name TingResult

# 听牌结果信息类

var can_ting: bool                  # 是否能听牌
var ting_cards: Array[CardData]     # 能听的牌列表
var ting_count: int                 # 听牌数量
var is_ting_tightly: bool           # 是否紧听（只能等一张）

func _init():
	can_ting = false
	ting_cards = []
	ting_count = 0
	is_ting_tightly = false
