extends Node2D

# 麻将游戏主场景脚本
# 这里管理游戏的整体逻辑和流程

var game_manager: GameManager
var player: Player
var enemies: Array = []

func _ready() -> void:
	"""
	当场景准备好时调用一次
	在这里初始化游戏
	"""
	print("欢迎来到麻将游戏！")
	print("游戏已启动")
	var separator = "========================================"
	print(separator)
	print("测试快捷键:")
	print("  P - Player 受伤 10 点")
	print("  H - Player 恢复 20 点")
	print("  E - 所有 Enemy 受伤 20 点")
	print("  ESC - 退出游戏")
	print(separator)
	
	# 创建 GameManager 来管理游戏
	game_manager = GameManager.new()
	add_child(game_manager)
	
	# 获取 Player 和 Enemies 的引用
	player = get_node_or_null("GameLayer/Player")
	enemies = get_tree().get_nodes_in_group("enemies")
	
	print("Main: Player 和 Enemy 引用已获取")


func _process(delta: float) -> void:
	"""
	每一帧调用一次
	delta: 上一帧的时间（秒）
	"""
	pass


func _input(event: InputEvent) -> void:
	"""
	处理用户输入 - 测试信号系统
	"""
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			print("按下 ESC，退出游戏")
			get_tree().quit()
		
		# 按 P 键让 player 受伤
		elif event.keycode == KEY_P:
			if player:
				print("Main: 触发 Player 受伤")
				player.take_damage(10)
		
		# 按 H 键让 player 治疗
		elif event.keycode == KEY_H:
			if player:
				print("Main: 触发 Player 治疗")
				player.heal(20)
		
		# 按 E 键让所有敌人受伤
		elif event.keycode == KEY_E:
			print("Main: 触发所有 Enemy 受伤")
			for enemy in enemies:
				if is_instance_valid(enemy) and enemy is Enemy:
					enemy.take_damage(20)
