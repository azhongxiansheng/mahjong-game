class_name WinResult

# 胡牌结果信息类

var can_win: bool
var win_patterns: Array  # 赢的方式（不同的组合）
var eye_card: CardData  # 眼睛（将）

func _init():
	can_win = false
	win_patterns = []
	eye_card = null
