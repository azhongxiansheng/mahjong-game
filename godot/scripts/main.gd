extends Node

# 游戏管理器
var game_ui: GameUI
var game_tester: GameTester

func _ready() -> void:
	print("\n========== 游戏启动 ==========\n")
	
	# 初始化游戏UI
	initialize_game_ui()
	
	# 启动测试
	call_deferred("start_test")

func initialize_game_ui() -> void:
	"""初始化游戏UI"""
	# 获取或创建GameUI
	game_ui = get_node_or_null("GameUI")
	
	if not game_ui:
		print("⚠ 场景中没有GameUI，尝试动态创建")
		var game_ui_scene = preload("res://scenes/game_ui.tscn")
		game_ui = game_ui_scene.instantiate()
		add_child(game_ui)
	
	if game_ui:
		print("✓ GameUI已初始化")
		# 显示测试手牌
		game_ui.test_display_hand()
	else:
		print("⚠ 无法初始化GameUI")

func start_test() -> void:
	"""启动测试"""
	print("\n========== 启动GameUI测试 ==========\n")
	
	# 创建测试器
	game_tester = GameTester.new()
	add_child(game_tester)
	game_tester._ready()
	
	print("\n========== 准备进行测试 ==========")
	print("可以在控制台运行以下命令进行测试:")
	print("  - game_tester.test_card_selection()")
	print("  - game_tester.test_animations()")
	print("  - game_tester.test_play_card()")
	print("  - game_tester.run_all_tests()")
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
			
			KEY_ESCAPE:  # 退出
				get_tree().quit()
