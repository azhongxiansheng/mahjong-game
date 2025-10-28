extends Node2D

# 麻将游戏主场景脚本
# 这里管理游戏的整体逻辑和流程

var game_manager: GameManager
var player: Player
var enemies: Array = []

# 防止连续触发的标志
var last_p_press_time = 0.0
var last_h_press_time = 0.0
var last_e_press_time = 0.0
var key_cooldown = 0.3  # 0.3秒的冷却时间

# 自动测试标志
var auto_test_started = false

# 分隔符
var separator = "========================================"

func _ready() -> void:
	"""
	当场景准备好时调用一次
	在这里初始化游戏
	"""
	print("欢迎来到麻将游戏！")
	print("游戏已启动")
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
	print("Main: 开始接收输入...")

	# 启动自动测试（延迟1秒后开始）
	await get_tree().create_timer(1.0).timeout
	print("\n" + separator)
	print("自动测试开始...")
	print(separator + "\n")
	start_auto_test()


func start_auto_test() -> void:
	"""自动测试所有功能"""
	if auto_test_started:
		return
	auto_test_started = true

	# 测试1: Player 受伤
	print("【测试1】Player 受伤测试...")
	if player:
		player.take_damage(10)
		await get_tree().create_timer(0.5).timeout

	# 测试2: Player 治疗
	print("\n【测试2】Player 治疗测试...")
	if player:
		player.heal(20)
		await get_tree().create_timer(0.5).timeout

	# 测试3: Enemy 受伤
	print("\n【测试3】Enemy 受伤测试...")
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy is Enemy:
			enemy.take_damage(20)
			await get_tree().create_timer(0.3).timeout

	# 继续受伤直到敌人死亡
	print("\n【测试4】继续伤害敌人直到死亡...")
	for i in range(5):
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy is Enemy:
				enemy.take_damage(20)
		await get_tree().create_timer(0.3).timeout

	print("\n" + separator)
	print("自动测试完成！")
	print(separator)
	print("\n按 ESC 退出游戏，或继续手动测试:")
	print("  P - Player 受伤 10 点")
	print("  H - Player 恢复 20 点")
	print("  E - 所有 Enemy 受伤 20 点")


func _process(delta: float) -> void:
	"""
	每一帧调用一次
	使用轮询方式检查按键状态
	"""
	var current_time = Time.get_ticks_msec() / 1000.0

	# 检查 P 键
	if Input.is_key_pressed(KEY_P):
		if current_time - last_p_press_time > key_cooldown:
			if player:
				print("✓ 检测到 P 键，Player 受伤")
				player.take_damage(10)
				last_p_press_time = current_time

	# 检查 H 键
	if Input.is_key_pressed(KEY_H):
		if current_time - last_h_press_time > key_cooldown:
			if player:
				print("✓ 检测到 H 键，Player 治疗")
				player.heal(20)
				last_h_press_time = current_time

	# 检查 E 键
	if Input.is_key_pressed(KEY_E):
		if current_time - last_e_press_time > key_cooldown:
			print("✓ 检测到 E 键，所有 Enemy 受伤")
			for enemy in enemies:
				if is_instance_valid(enemy) and enemy is Enemy:
					enemy.take_damage(20)
			last_e_press_time = current_time

	# 检查 ESC 键
	if Input.is_key_pressed(KEY_ESCAPE):
		print("按下 ESC，退出游戏")
		get_tree().quit()


func _input(event: InputEvent) -> void:
	"""
	处理用户输入事件（备用方案）
	"""
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_P:
			print("📥 _input 方式检测到 P 键")
		elif event.keycode == KEY_H:
			print("📥 _input 方式检测到 H 键")
		elif event.keycode == KEY_E:
			print("📥 _input 方式检测到 E 键")
		elif event.keycode == KEY_ESCAPE:
			print("按下 ESC，退出游戏")
			get_tree().quit()
