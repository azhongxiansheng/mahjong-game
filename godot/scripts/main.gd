extends Node2D

## 主游戏场景
## 管理游戏的主要逻辑和玩家交互

func _ready() -> void:
	print("🎮 主游戏场景已加载")

	# 检查用户是否已登录
	if has_node("/root/GameManager"):
		var user_data = GameManager.get_user_data()
		if user_data.is_empty():
			push_warning("⚠ 未检测到登录信息")
		else:
			print("👤 当前用户: ", GameManager.get_nickname())
			print("🆔 登录类型: ", GameManager.get_login_type())

	# 初始化游戏
	_initialize_game()

func _initialize_game() -> void:
	"""初始化游戏"""
	print("🎲 游戏初始化中...")

	# TODO: 初始化游戏逻辑
	# - 加载玩家数据
	# - 设置游戏规则
	# - 初始化牌局

	print("✅ 游戏初始化完成")

func _input(event: InputEvent) -> void:
	"""处理输入事件"""
	# 按 ESC 返回登录界面（测试用）
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		print("🔙 返回登录界面")
		get_tree().change_scene_to_file("res://scenes/loading_screen.tscn")
