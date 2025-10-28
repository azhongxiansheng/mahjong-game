class_name UIManager

# UI管理器
# 负责所有UI界面的管理和切换

var screens: Dictionary = {}           # screen_name -> ScreenBase
var current_screen: String = ""        # 当前显示的界面名称
var transition_duration: float = 0.3

func _init() -> void:
	"""初始化UI管理器"""
	print("UIManager: 已初始化")

func register_screen(screen_name: String, screen: ScreenBase) -> void:
	"""注册UI界面"""
	if screen_name in screens:
		print("UIManager: 界面已存在 %s" % screen_name)
		return
	
	screens[screen_name] = screen
	print("UIManager: 界面已注册 %s" % screen_name)

func show_screen(screen_name: String) -> void:
	"""显示指定界面"""
	if screen_name not in screens:
		print("UIManager: 界面不存在 %s" % screen_name)
		return
	
	# 隐藏当前界面
	if current_screen != "" and current_screen in screens:
		screens[current_screen].hide_screen()
	
	# 显示新界面
	current_screen = screen_name
	screens[screen_name].show_screen()
	print("UIManager: 显示界面 %s" % screen_name)

func hide_screen(screen_name: String) -> void:
	"""隐藏指定界面"""
	if screen_name not in screens:
		print("UIManager: 界面不存在 %s" % screen_name)
		return
	
	if current_screen == screen_name:
		current_screen = ""
	
	screens[screen_name].hide_screen()
	print("UIManager: 隐藏界面 %s" % screen_name)

func transition_to(next_screen_name: String) -> void:
	"""过渡到下一个界面"""
	if next_screen_name not in screens:
		print("UIManager: 界面不存在 %s" % next_screen_name)
		return
	
	if current_screen != "" and current_screen in screens:
		screens[current_screen].hide_screen()
	
	current_screen = next_screen_name
	screens[next_screen_name].show_screen()
	print("UIManager: 过渡到界面 %s" % next_screen_name)

func get_screen(screen_name: String) -> ScreenBase:
	"""获取指定界面"""
	return screens.get(screen_name, null)

func get_current_screen() -> ScreenBase:
	"""获取当前界面"""
	if current_screen == "":
		return null
	return screens.get(current_screen, null)

func get_all_screens() -> Array:
	"""获取所有已注册的界面"""
	return screens.values()

func has_screen(screen_name: String) -> bool:
	"""检查界面是否存在"""
	return screen_name in screens

func get_screen_count() -> int:
	"""获取已注册的界面数量"""
	return screens.size()

func list_screens() -> void:
	"""列出所有已注册的界面"""
	print("UIManager: 已注册的界面:")
	for screen_name in screens.keys():
		var marker = " <- 当前" if screen_name == current_screen else ""
		print("  - %s%s" % [screen_name, marker])
