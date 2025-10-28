extends Node2D

# 麻将游戏主场景脚本
# 这里管理游戏的整体逻辑和流程

func _ready() -> void:
	"""
	当场景准备好时调用一次
	在这里初始化游戏
	"""
	print("欢迎来到麻将游戏！")
	print("游戏已启动")


func _process(delta: float) -> void:
	"""
	每一帧调用一次
	delta: 上一帧的时间（秒）
	"""
	pass


func _input(event: InputEvent) -> void:
	"""
	处理用户输入
	"""
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			print("按下 ESC，退出游戏")
			get_tree().quit()
