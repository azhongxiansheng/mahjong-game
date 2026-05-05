class_name UIDiagnostics
extends Node

# 诊断工具 - 用于调试UI相关的问题

func _ready() -> void:
	print("\n========== UI 诊断开始 ==========\n")

	# 获取GameUI
	var game_ui = get_tree().root.get_node_or_null("Main/GameUI")
	if not game_ui:
		print("⚠ 无法找到GameUI")
		return

	diagnose_game_ui(game_ui)

func diagnose_game_ui(game_ui: Node) -> void:
	"""诊断GameUI及其子组件"""
	print("✓ 找到GameUI")
	print("  类型: ", game_ui.get_class())
	print("  脚本: ", game_ui.get_script())

	# 检查player_hand_display
	print("\n[检查 player_hand_display]")
	if game_ui.has_meta("player_hand_display"):
		var phd = game_ui.get_meta("player_hand_display")
		print("  ✓ 存在 (通过meta)")
		print("  类型: ", phd.get_class())
	else:
		var phd = game_ui.get_node_or_null("GameLayer/TableArea/PlayerHand")
		if phd:
			print("  ✓ 存在 (通过get_node)")
			print("  类型: ", phd.get_class())
			print("  脚本: ", phd.get_script())

			# 检查信号
			print("\n  [信号检查]")
			print("  has_signal('card_pressed'): ", phd.has_signal("card_pressed"))
			print("  has_signal('card_selected'): ", phd.has_signal("card_selected"))

			# 尝试获取信号列表
			var signals = phd.get_signal_list()
			print("  所有信号数量: ", signals.size())
			for sig in signals:
				print("    - ", sig.name)
		else:
			print("  ⚠ 无法找到player_hand_display")

func diagnose_card_tile() -> void:
	"""诊断CardTile组件"""
	print("\n[检查 CardTile]")

	var scene = preload("res://scenes/card_tile.tscn")
	if not scene:
		print("  ⚠ 无法加载card_tile.tscn")
		return

	print("  ✓ 场景已加载")

	var instance = scene.instantiate()
	print("  实例类型: ", instance.get_class())
	print("  实例脚本: ", instance.get_script())

	# 检查类名
	if instance.get_script():
		print("  脚本类名: ", instance.get_script().get_global_name())

	# 检查信号
	var signals = instance.get_signal_list()
	print("  信号数量: ", signals.size())
	for sig in signals:
		print("    - ", sig.name)

	instance.queue_free()

func test_hand_display() -> void:
	"""测试HandDisplay实例"""
	print("\n[测试 HandDisplay 实例]")

	var scene = preload("res://scenes/hand_display.tscn")
	if not scene:
		print("  ⚠ 无法加载hand_display.tscn")
		return

	print("  ✓ 场景已加载")

	var instance = scene.instantiate()
	print("  实例类型: ", instance.get_class())
	print("  实例脚本: ", instance.get_script())
	print("  是HandDisplay: ", instance is HandDisplay)

	# 检查信号
	var signals = instance.get_signal_list()
	print("  信号数量: ", signals.size())
	for sig in signals:
		print("    - ", sig.name)

	instance.queue_free()

func print_all_diagnostics() -> void:
	"""运行所有诊断"""
	diagnose_game_ui(get_tree().root.get_node("Main/GameUI"))
	diagnose_card_tile()
	test_hand_display()
	print("\n========== 诊断完成 ==========\n")
