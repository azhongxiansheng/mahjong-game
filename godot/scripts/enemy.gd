extends Node2D

class_name Enemy

# 定义信号
signal enemy_died

var health = 50
var max_health = 50
var damage = 10

func _ready() -> void:
	"""当节点加载时调用"""
	print("Enemy 已加载 - 生命值: ", health)
	add_to_group("enemies")

func take_damage(amount: int) -> void:
	"""受伤"""
	health -= amount
	print("Enemy 受伤 %d 点，当前生命值: %d" % [amount, health])
	
	if health <= 0:
		die()

func die() -> void:
	"""死亡"""
	print("敌人死亡！")
	emit_signal("enemy_died")
	queue_free()

func attack(target: Node2D) -> void:
	"""攻击目标"""
	if target and target.has_method("take_damage"):
		print("Enemy 攻击，造成 %d 点伤害" % damage)
		target.take_damage(damage)
