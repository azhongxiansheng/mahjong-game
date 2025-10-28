class_name MainMenuUI
extends ScreenBase

# 主菜单UI
# 游戏启动时显示的首个界面

# 信号
signal start_game_pressed
signal settings_pressed
signal quit_pressed

# UI组件
var title_label: Label
var start_button: Button
var settings_button: Button
var quit_button: Button
var version_label: Label

func _ready() -> void:
	"""初始化主菜单"""
	super()
	
	# 设置背景
	modulate = Color.WHITE
	
	# 创建标题
	title_label = Label.new()
	title_label.text = "🀄 麻将游戏"
	title_label.add_theme_font_size_override("font_size", 64)
	title_label.anchor_left = 0.5
	title_label.anchor_top = 0.2
	title_label.offset_left = -150
	title_label.offset_top = 0
	add_child(title_label)
	
	# 创建开始按钮
	start_button = Button.new()
	start_button.text = "开始游戏"
	start_button.custom_minimum_size = Vector2(200, 60)
	start_button.anchor_left = 0.5
	start_button.anchor_top = 0.4
	start_button.offset_left = -100
	start_button.offset_top = 0
	start_button.pressed.connect(_on_start_pressed)
	add_child(start_button)
	
	# 创建设置按钮
	settings_button = Button.new()
	settings_button.text = "设置"
	settings_button.custom_minimum_size = Vector2(200, 60)
	settings_button.anchor_left = 0.5
	settings_button.anchor_top = 0.55
	settings_button.offset_left = -100
	settings_button.offset_top = 0
	settings_button.pressed.connect(_on_settings_pressed)
	add_child(settings_button)
	
	# 创建退出按钮
	quit_button = Button.new()
	quit_button.text = "退出"
	quit_button.custom_minimum_size = Vector2(200, 60)
	quit_button.anchor_left = 0.5
	quit_button.anchor_top = 0.7
	quit_button.offset_left = -100
	quit_button.offset_top = 0
	quit_button.pressed.connect(_on_quit_pressed)
	add_child(quit_button)
	
	# 创建版本标签
	version_label = Label.new()
	version_label.text = "v0.1.0 - Week 9"
	version_label.add_theme_font_size_override("font_size", 12)
	version_label.anchor_left = 1.0
	version_label.anchor_top = 1.0
	version_label.offset_left = -150
	version_label.offset_top = -30
	add_child(version_label)
	
	print("MainMenuUI: 已初始化")

func on_enter() -> void:
	"""进入主菜单时的回调"""
	print("MainMenuUI: 进入主菜单")
	# 可以在这里播放背景音乐

func on_exit() -> void:
	"""离开主菜单时的回调"""
	print("MainMenuUI: 离开主菜单")

func _on_start_pressed() -> void:
	"""开始游戏按钮被按下"""
	print("MainMenuUI: 开始游戏")
	start_game_pressed.emit()

func _on_settings_pressed() -> void:
	"""设置按钮被按下"""
	print("MainMenuUI: 打开设置")
	settings_pressed.emit()

func _on_quit_pressed() -> void:
	"""退出按钮被按下"""
	print("MainMenuUI: 退出游戏")
	quit_pressed.emit()
	get_tree().quit()

func show_announcement(text: String) -> void:
	"""显示公告"""
	print("MainMenuUI: 公告 - %s" % text)
