class_name RegisterUI
extends ScreenBase

# 注册UI
# 用户账户创建界面

# 信号
signal register_success(user_id: String)

# UI组件
var title_label: Label
var username_input: LineEdit
var email_input: LineEdit
var password_input: LineEdit
var password_confirm_input: LineEdit
var register_button: Button
var back_button: Button
var error_label: Label
var info_label: Label

# 数据库引用
var db_manager: DatabaseManager

func _ready() -> void:
	"""初始化注册界面"""
	super()

	# 创建标题
	title_label = Label.new()
	title_label.text = "创建账户"
	title_label.add_theme_font_size_override("font_size", 48)
	title_label.anchor_left = 0.5
	title_label.anchor_top = 0.05
	title_label.offset_left = -80
	add_child(title_label)

	# 创建用户名标签和输入框
	var username_label = Label.new()
	username_label.text = "用户名:"
	username_label.anchor_left = 0.5
	username_label.anchor_top = 0.15
	username_label.offset_left = -250
	add_child(username_label)

	username_input = LineEdit.new()
	username_input.placeholder_text = "输入用户名 (3-20字符)"
	username_input.custom_minimum_size = Vector2(300, 40)
	username_input.anchor_left = 0.5
	username_input.anchor_top = 0.15
	username_input.offset_left = -150
	username_input.offset_top = 20
	add_child(username_input)

	# 创建邮箱标签和输入框
	var email_label = Label.new()
	email_label.text = "邮箱:"
	email_label.anchor_left = 0.5
	email_label.anchor_top = 0.28
	email_label.offset_left = -250
	add_child(email_label)

	email_input = LineEdit.new()
	email_input.placeholder_text = "输入邮箱地址"
	email_input.custom_minimum_size = Vector2(300, 40)
	email_input.anchor_left = 0.5
	email_input.anchor_top = 0.28
	email_input.offset_left = -150
	email_input.offset_top = 20
	add_child(email_input)

	# 创建密码标签和输入框
	var password_label = Label.new()
	password_label.text = "密码:"
	password_label.anchor_left = 0.5
	password_label.anchor_top = 0.41
	password_label.offset_left = -250
	add_child(password_label)

	password_input = LineEdit.new()
	password_input.placeholder_text = "输入密码 (6-50字符)"
	password_input.secret = true
	password_input.custom_minimum_size = Vector2(300, 40)
	password_input.anchor_left = 0.5
	password_input.anchor_top = 0.41
	password_input.offset_left = -150
	password_input.offset_top = 20
	add_child(password_input)

	# 创建密码确认标签和输入框
	var password_confirm_label = Label.new()
	password_confirm_label.text = "确认密码:"
	password_confirm_label.anchor_left = 0.5
	password_confirm_label.anchor_top = 0.54
	password_confirm_label.offset_left = -250
	add_child(password_confirm_label)

	password_confirm_input = LineEdit.new()
	password_confirm_input.placeholder_text = "再次输入密码"
	password_confirm_input.secret = true
	password_confirm_input.custom_minimum_size = Vector2(300, 40)
	password_confirm_input.anchor_left = 0.5
	password_confirm_input.anchor_top = 0.54
	password_confirm_input.offset_left = -150
	password_confirm_input.offset_top = 20
	add_child(password_confirm_input)

	# 创建错误标签
	error_label = Label.new()
	error_label.text = ""
	error_label.add_theme_color_override("font_color", Color.RED)
	error_label.anchor_left = 0.5
	error_label.anchor_top = 0.65
	error_label.offset_left = -150
	add_child(error_label)

	# 创建信息标签
	info_label = Label.new()
	info_label.text = "密码需包含大小写字母和数字"
	info_label.add_theme_font_size_override("font_size", 10)
	info_label.anchor_left = 0.5
	info_label.anchor_top = 0.67
	info_label.offset_left = -150
	add_child(info_label)

	# 创建注册按钮
	register_button = Button.new()
	register_button.text = "创建账户"
	register_button.custom_minimum_size = Vector2(150, 50)
	register_button.anchor_left = 0.5
	register_button.anchor_top = 0.75
	register_button.offset_left = -200
	register_button.pressed.connect(_on_register_pressed)
	add_child(register_button)

	# 创建返回按钮
	back_button = Button.new()
	back_button.text = "返回登录"
	back_button.custom_minimum_size = Vector2(150, 50)
	back_button.anchor_left = 0.5
	back_button.anchor_top = 0.75
	back_button.offset_left = 50
	back_button.pressed.connect(_on_back_pressed)
	add_child(back_button)

	print("RegisterUI: 已初始化")

func on_enter() -> void:
	"""进入注册界面时的回调"""
	print("RegisterUI: 进入注册界面")
	clear_inputs()
	clear_error()

func on_exit() -> void:
	"""离开注册界面时的回调"""
	print("RegisterUI: 离开注册界面")

func _on_register_pressed() -> void:
	"""注册按钮被按下"""
	var username = username_input.text.strip_edges()
	var email = email_input.text.strip_edges()
	var password = password_input.text
	var password_confirm = password_confirm_input.text

	# 验证输入
	var error = _validate_registration(username, email, password, password_confirm)
	if error != "":
		show_error(error)
		return

	# 调用数据库注册
	if db_manager.register_user(username, email, password):
		show_message("✓ 注册成功！即将返回登录...")
		await get_tree().create_timer(1.5).timeout
		register_success.emit(db_manager.get_user(username).user_id if db_manager.get_user(username) else "")
	else:
		show_error("✗ 用户名已存在，请换一个")

func _on_back_pressed() -> void:
	"""返回按钮被按下"""
	print("RegisterUI: 返回登录界面")
	back_pressed.emit()

func _validate_registration(username: String, email: String, password: String, password_confirm: String) -> String:
	"""验证注册数据"""
	# 检查用户名
	if FormValidator.is_empty(username):
		return "请输入用户名"
	if not FormValidator.is_valid_username(username):
		return "用户名格式不正确 (3-20字符，字母开头)"

	# 检查邮箱
	if FormValidator.is_empty(email):
		return "请输入邮箱"
	if not FormValidator.is_valid_email(email):
		return "邮箱格式不正确"

	# 检查密码
	if FormValidator.is_empty(password):
		return "请输入密码"
	if not FormValidator.is_valid_password(password):
		return "密码强度不足 (需要大小写字母和数字)"

	# 检查密码确认
	if FormValidator.is_empty(password_confirm):
		return "请确认密码"

	if password != password_confirm:
		return "两次输入的密码不一致"

	return ""

func clear_inputs() -> void:
	"""清空输入框"""
	username_input.text = ""
	email_input.text = ""
	password_input.text = ""
	password_confirm_input.text = ""

func clear_error() -> void:
	"""清空错误消息"""
	error_label.text = ""

func show_error(error: String) -> void:
	"""显示错误消息"""
	error_label.text = error
	print("RegisterUI: 错误 - %s" % error)

func show_message(message: String, _duration: float = 2.0) -> void:
	"""显示成功消息"""
	error_label.text = message
	error_label.add_theme_color_override("font_color", Color.GREEN)
	print("RegisterUI: %s" % message)

func set_database_manager(db: DatabaseManager) -> void:
	"""设置数据库管理器"""
	db_manager = db
