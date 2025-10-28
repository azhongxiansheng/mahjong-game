extends CardData

class_name SpecialCard

var effect_name: String = ""
var effect_value: int = 0

func _init(p_suit: int, p_number: int, effect: String = "", value: int = 0) -> void:
	"""初始化特殊卡牌"""
	super._init(p_suit, p_number)
	effect_name = effect
	effect_value = value

func get_card_name() -> String:
	"""获取卡牌名称（包含特殊效果）"""
	var base_name = super.get_card_name()
	if effect_name:
		return base_name + " <%s>" % effect_name
	return base_name

func apply_effect(target) -> void:
	"""应用特殊效果"""
	print("应用效果 %s，数值 %d" % [effect_name, effect_value])

func get_total_value() -> int:
	"""获取总数值（基础数值 + 效果加成）"""
	return number + effect_value
