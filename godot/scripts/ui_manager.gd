class_name UIManager
extends Node

# UI屏幕引用
var current_screen: ScreenBase
var screens: Dictionary = {}

# 预加载UI场景
var game_ui_scene = preload("res://scenes/game_ui.tscn")
var main_menu_scene = preload("res://scenes/main.tscn")

# 游戏引用
var game_controller: GameController

func _ready() -> void:
	print("========== UIManager 初始化 ==========")
	
	# 初始化游戏UI
	initialize_game_ui()

func initialize_game_ui() -> void:
	"""初始化游戏UI"""
	# 实例化GameUI
	var game_ui = game_ui_scene.instantiate() as GameUI
	
	if not game_ui:
		print("⚠ 无法创建GameUI")
		return
	
	# 设置GameUI
	screens["game_ui"] = game_ui
	add_child(game_ui)
	
	# 显示GameUI
	show_screen("game_ui")
	
	print("✓ GameUI已初始化")

func show_screen(screen_name: String) -> void:
	"""显示指定的屏幕"""
	if not screen_name in screens:
		print("⚠ 屏幕不存在: %s" % screen_name)
		return
	
	# 隐藏当前屏幕
	if current_screen:
		current_screen.hide_screen()
	
	# 显示新屏幕
	current_screen = screens[screen_name]
	current_screen.show_screen()
	print("✓ 显示屏幕: %s" % screen_name)

func get_game_ui() -> GameUI:
	"""获取GameUI实例"""
	if "game_ui" in screens:
		return screens["game_ui"] as GameUI
	return null

func update_game_state() -> void:
	"""更新游戏状态显示"""
	var game_ui = get_game_ui()
	if game_ui and game_controller:
		# 更新UI显示
		if game_controller.get_current_player():
			var hand = game_controller.get_current_player().get_hand()
			if hand:
				game_ui.display_hand(hand)
