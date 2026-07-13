class_name PlayerDecisionPort extends RefCounted

# 玩家决策的战斗层端口。
#
# BattleController 只描述“需要哪类决策”和合法选项；具体按钮、手牌点击、
# 高亮与提示文案由 UI 层适配器实现。测试可注入无场景树的脚本化端口。


func request(_kind: StringName, _context: Dictionary = {}) -> Dictionary:
	return {}


func present(_state_name: StringName, _context: Dictionary = {}) -> void:
	pass
