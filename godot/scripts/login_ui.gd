class_name LoginUI
extends ScreenBase

# 登录UI
# 用户认证界面

# 信号
signal login_pressed(username: String, password: String)
signal register_pressed
signal back_pressed

# UI组件
var title_label: Label
var username_input: LineEdit
var password_input: LineEdit
var login_button: Button
var register_button: Button
var back_button: Button
var error_label: Label

func _ready() -> void:
	"""初始化登录界面"""
	super()
	
	# 创建标题
	title_label = Label.new()
	title_label.text = "登录"
	title_label.add_theme_font_size_override("font_size", 48)
	title_label.anchor_left = 0.5
	title_label.anchor_top = 0.1
	title_label.offset_left = -80
	add_child(title_label)
	
	# 创建用户名标签
	var username_label = Label.new()
	username_label.text = "用户名:"
	username_label.anchor_left = 0.5
	username_label.anchor_top = 0.25
	username_label.offset_left = -250
	add_child(username_label)
	
	# 创建用户名输入框
	username_input = LineEdit.new()
	username_input.placeholder_text = "输入用户名"
	username_input.custom_minimum_size = Vector2(300, 40)
	username_input.anchor_left = 0.5
	username_input.anchor_top = 0.25
	username_input.offset_left = -150
	username_input.offset_top = 20
	add_child(username_input)
	
	# 创建密码标签
	var password_label = Label.new()
	password_label.text = "密码:"
	password_label.anchor_left = 0.5
	password_label.anchor_top = 0.4
	password_label.offset_left = -250
	add_child(password_label)
	
	# 创建密码输入框
	password_input = LineEdit.new()
	password_input.placeholder_text = "输入密码"
	password_input.secret = true
	password_input.custom_minimum_size = Vector2(300, 40)
	password_input.anchor_left = 0.5
	password_input.anchor_top = 0.4
	password_input.offset_left = -150
	password_input.offset_top = 20
	add_child(password_input)
	
	# 创建错误标签
	error_label = Label.new()
	error_label.text = ""
	error_label.add_theme_color_override("font_color", Color.RED)
	error_label.anchor_left = 0.5
	error_label.anchor_top = 0.52
	error_label.offset_left = -150
	add_child(error_label)
	
	# 创建登录按钮
	login_button = Button.new()
	login_button.text = "登录"
	login_button.custom_minimum_size = Vector2(150, 50)
	login_button.anchor_left = 0.5
	login_button.anchor_top = 0.6
	login_button.offset_left = -200
	login_button.pressed.connect(_on_login_pressed)
	add_child(login_button)
	
	# 创建注册按钮
	register_button = Button.new()
	register_button.text = "注册新账户"
	register_button.custom_minimum_size = Vector2(150, 50)
	register_button.anchor_left = 0.5
	register_button.anchor_top = 0.6
	register_button.offset_left = 50
	register_button.pressed.connect(_on_register_pressed)
	add_child(register_button)
	
	# 创建返回按钮
	back_button = Button.new()
	back_button.text = "返回"
	back_button.custom_minimum_size = Vector2(100, 40)
	back_button.anchor_left = 0.0
	back_button.anchor_top = 0.0
	back_button.offset_left = 10
	back_button.offset_top = 10
	back_button.pressed.connect(_on_back_pressed)
	add_child(back_button)
	
	print("LoginUI: 已初始化")

func on_enter() -> void:
	"""进入登录界面时的回调"""
	print("LoginUI: 进入登录界面")
	clear_inputs()
	clear_error()

func on_exit() -> void:
	"""离开登录界面时的回调"""
	print("LoginUI: 离开登录界面")

func _on_login_pressed() -> void:
	"""登录按钮被按下"""
	var username = username_input.text.strip_edges()
	var password = password_input.text
	
	# 验证输入
	if FormValidator.is_empty(username):
		show_error("请输入用户名")
		return
	
	if FormValidator.is_empty(password):
		show_error("请输入密码")
		return
	
	print("LoginUI: 尝试登录 - %s" % username)
	login_pressed.emit(username, password)

func _on_register_pressed() -> void:
	"""注册按钮被按下"""
	print("LoginUI: 打开注册界面")
	register_pressed.emit()

func _on_back_pressed() -> void:
	"""返回按钮被按下"""
	print("LoginUI: 返回主菜单")
	back_pressed.emit()

func clear_inputs() -> void:
	"""清空输入框"""
	username_input.text = ""
	password_input.text = ""

func clear_error() -> void:
	"""清空错误消息"""
	error_label.text = ""

func show_error(error: String) -> void:
	"""显示错误消息"""
	error_label.text = error
	print("LoginUI: 错误 - %s" % error)

func set_login_enabled(enabled: bool) -> void:
	"""设置登录按钮是否可用"""
	login_button.disabled = not enabled
