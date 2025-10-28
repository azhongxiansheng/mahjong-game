extends Node

# 游戏管理器
var game_ui: GameUI
var game_tester: GameTester
var game_flow: GameFlow

func _ready() -> void:
	print("\n========== 游戏启动 ==========\n")

	# 初始化游戏UI
	initialize_game_ui()

	# 初始化游戏流程
	initialize_game_flow()

	# 启动测试
	call_deferred("start_test")

func initialize_game_ui() -> void:
	"""初始化游戏UI"""
	# 获取或创建GameUI - 修正节点路径
	game_ui = get_node_or_null("UILayer/GameUI")

	if not game_ui:
		print("⚠ 无法找到 UILayer/GameUI，尝试动态创建")
		var game_ui_scene = preload("res://scenes/game_ui.tscn")
		game_ui = game_ui_scene.instantiate()
		add_child(game_ui)

	if game_ui:
		print("✓ GameUI已初始化")
		# 延迟显示测试手牌，确保GameUI已完全初始化
		game_ui.call_deferred("test_display_hand")
	else:
		print("⚠ 无法初始化GameUI")

func initialize_game_flow() -> void:
	"""初始化游戏流程"""
	game_flow = GameFlow.new()
	add_child(game_flow)
	game_flow._ready()

	print("✓ 游戏流程已初始化")

func start_test() -> void:
	"""启动测试"""
	print("\n========== 启动GameUI测试 ==========\n")

	# 创建测试器
	game_tester = GameTester.new()
	add_child(game_tester)
	game_tester._ready()

	print("\n========== 准备进行测试 ==========")
	print("快捷键说明:")
	print("  [1] 显示手牌")
	print("  [2] 卡牌选择")
	print("  [3] 出牌")
	print("  [4] 动画效果")
	print("  [5] 完整测试")
	print("  [D] 弃牌堆")
	print("  [O] 对手手牌")
	print("  [C] 完整流程")
	print("  [ESC] 退出")
	print("")

func _input(event: InputEvent) -> void:
	"""处理输入"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:  # 测试显示手牌
				if game_ui:
					game_ui.test_display_hand()
				print("✓ 已显示测试手牌")

			KEY_2:  # 测试卡牌选择
				if game_tester:
					game_tester.test_card_selection()

			KEY_3:  # 测试出牌
				if game_tester:
					game_tester.test_play_card()

			KEY_4:  # 测试动画
				if game_tester:
					await game_tester.test_animations()

			KEY_5:  # 运行所有测试
				if game_tester:
					await game_tester.run_all_tests()

			KEY_D:  # 测试弃牌堆
				if game_tester:
					await game_tester.test_discard_pile()

			KEY_O:  # 测试对手手牌
				if game_tester:
					game_tester.test_opponent_hand()

			KEY_C:  # 测试完整流程
				if game_tester:
					await game_tester.test_complete_flow()

			KEY_ESCAPE:  # 退出
				get_tree().quit()
