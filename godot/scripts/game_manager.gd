extends Node

class_name GameManager

var player: Player
var enemies: Array = []
var score = 0

func _ready() -> void:
	"""初始化游戏管理器"""
	# 获取 Player 节点
	player = get_tree().get_first_node_in_group("player")

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
		if enemy is Enemy:
			enemy.connect("enemy_died", Callable(self, "_on_enemy_died").bindv([enemy]))
			print("GameManager: 已连接 Enemy 信号")

func _on_player_health_changed(_health: int) -> void:
	"""玩家血量改变时"""
	print("GameManager: 玩家血量更新 -> %d" % _health)

func _on_player_died() -> void:
	"""玩家死亡时"""
	print("GameManager: 游戏结束！玩家死亡")
	await get_tree().create_timer(2.0).timeout
	get_tree().reload_current_scene()

func _on_enemy_died(_enemy: Enemy) -> void:
	"""敌人死亡时"""
	print("GameManager: 敌人死亡！")
	enemies.erase(_enemy)
	score += 10

	if enemies.is_empty():
		print("GameManager: 所有敌人已消灭，玩家胜利！")
		print("GameManager: 最终分数: %d" % score)
