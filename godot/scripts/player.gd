extends Node2D

class_name Player

# 定义信号
signal health_changed(current_health)
signal player_died

var health = 100
var max_health = 100

func _ready() -> void:
	"""当节点加载时调用"""
	print("Player 已加载 - 生命值: ", health)
	add_to_group("player")

func take_damage(amount: int) -> void:
	"""受伤处理"""
	health -= amount
	emit_signal("health_changed", health)
	print("Player 受伤 %d 点，当前生命值: %d" % [amount, health])
	
	if health <= 0:
		die()

func heal(amount: int) -> void:
	"""治疗"""
	health = min(health + amount, max_health)
	emit_signal("health_changed", health)
	print("Player 恢复 %d 点，当前生命值: %d" % [amount, health])

func die() -> void:
	"""死亡处理"""
	print("玩家死亡！")
	emit_signal("player_died")
	queue_free()  # 删除这个节点
