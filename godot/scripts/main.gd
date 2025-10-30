extends Node2D

## Main game scene
## 管理游戏的主要逻辑和玩家交互

## 调试模式
var debug_mode: bool = true

func _ready() -> void:
	print("\n========== Main._ready() started ==========")
	
	# 延迟初始化，确保场景树完全加载
	call_deferred("_deferred_initialize")
	
	print("========== Main._ready() completed ==========\n")

func _deferred_initialize() -> void:
	print("[Main] Deferred initialization started")
	_initialize_game_ui()
	print("[Main] Deferred initialization completed")

func _initialize_game_ui() -> void:
	"""初始化游戏UI"""
	print("正在初始化游戏UI...")

	var title_label = Label.new()
	title_label.text = "Mahjong Game - Main Scene"
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.position = Vector2(400, 100)
	add_child(title_label)

	var status_label = Label.new()
	status_label.text = "Game loaded successfully!\n\n[ESC] Return to login"
	status_label.add_theme_font_size_override("font_size", 20)
	status_label.position = Vector2(250, 300)
	add_child(status_label)

	print("游戏UI初始化完成")

## Handle debug input
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return

	if event.keycode == KEY_ESCAPE:
		print("返回登录界面")
		get_tree().change_scene_to_file("res://scenes/wechat_login_final.tscn")
