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
	print("Main: _input 函数已准备好接收输入")


func _process(delta: float) -> void:
	"""
	每一帧调用一次
	使用轮询方式检查按键状态（备用方案）
	"""
	# 使用 Input 类轮询按键状态
	if Input.is_key_pressed(KEY_P):
		if player:
			print("Main (_process): 检测到 P 键，触发 Player 受伤")
			player.take_damage(10)
			await get_tree().create_timer(0.2).timeout  # 防止连续触发
	
	if Input.is_key_pressed(KEY_H):
		if player:
			print("Main (_process): 检测到 H 键，触发 Player 治疗")
			player.heal(20)
			await get_tree().create_timer(0.2).timeout
	
	if Input.is_key_pressed(KEY_E):
		print("Main (_process): 检测到 E 键，触发所有 Enemy 受伤")
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy is Enemy:
				enemy.take_damage(20)
		await get_tree().create_timer(0.2).timeout


func _input(event: InputEvent) -> void:
	"""
	处理用户输入 - 测试信号系统
	"""
	if event is InputEventKey:
		print("Main _input: 检测到按键事件，keycode=%d, pressed=%s" % [event.keycode, event.pressed])
		
		if event.pressed:
			if event.keycode == KEY_ESCAPE:
				print("按下 ESC，退出游戏")
				get_tree().quit()
			
			# 按 P 键让 player 受伤
			elif event.keycode == KEY_P:
				if player:
					print("Main _input: 触发 Player 受伤")
					player.take_damage(10)
				else:
					print("Main _input: 警告 - Player 为空")
			
			# 按 H 键让 player 治疗
			elif event.keycode == KEY_H:
				if player:
					print("Main _input: 触发 Player 治疗")
					player.heal(20)
				else:
					print("Main _input: 警告 - Player 为空")
			
			# 按 E 键让所有敌人受伤
			elif event.keycode == KEY_E:
				print("Main _input: 触发所有 Enemy 受伤，敌人数量=%d" % enemies.size())
				for enemy in enemies:
					if is_instance_valid(enemy) and enemy is Enemy:
						enemy.take_damage(20)
