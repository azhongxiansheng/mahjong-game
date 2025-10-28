extends Node

class_name GameManager

var player: Player
var enemies: Array[Enemy] = []
var score = 0

func _ready() -> void:
	"""初始化游戏管理器"""
	# 获取 Player 节点
	player = get_tree().get_first_child_in_group("player")
	
	# 如果找不到，手动获取
	if not player:
		var game_layer = get_node_or_null("../GameLayer")
		if game_layer:
			player = game_layer.get_node_or_null("Player")
	
	# 连接 player 的信号
	if player:
		player.connect("health_changed", Callable(self, "_on_player_health_changed"))
		player.connect("player_died", Callable(self, "_on_player_died"))
		print("GameManager: 已连接 Player 信号")
	else:
		print("GameManager: 警告 - 找不到 Player 节点")
	
	# 获取所有敌人并连接它们的信号
	enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		enemy.connect("enemy_died", Callable(self, "_on_enemy_died").bindv([enemy]))
		print("GameManager: 已连接 Enemy 信号")

func _input(event: InputEvent) -> void:
	"""处理用户输入 - 用于测试"""
	if event is InputEventKey and event.pressed:
		# 测试：按 P 键让 player 受伤
		if event.keycode == KEY_P:
			if player:
				player.take_damage(10)
		
		# 测试：按 H 键让 player 治疗
		elif event.keycode == KEY_H:
			if player:
				player.heal(20)
		
		# 测试：按 E 键让所有敌人受伤
		elif event.keycode == KEY_E:
			for enemy in enemies:
				if is_instance_valid(enemy):
					enemy.take_damage(20)

func _on_player_health_changed(health: int) -> void:
	"""玩家血量改变时"""
	print("GameManager: 玩家血量更新 -> %d" % health)

func _on_player_died() -> void:
	"""玩家死亡时"""
	print("GameManager: 游戏结束！玩家死亡")
	await get_tree().create_timer(2.0).timeout
	get_tree().reload_current_scene()

func _on_enemy_died(enemy: Enemy) -> void:
	"""敌人死亡时"""
	print("GameManager: 敌人死亡！")
	enemies.erase(enemy)
	score += 10
	
	if enemies.is_empty():
		print("GameManager: 所有敌人已消灭，玩家胜利！")
		print("GameManager: 最终分数: %d" % score)
