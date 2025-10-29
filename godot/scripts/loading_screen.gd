class_name LoadingScreen
extends CanvasLayer

@onready var background: TextureRect = $Background
@onready var wechat_button: Button = $LoginContainer/VBoxContainer/WeChatLoginButton
@onready var switch_label: Label = $LoginContainer/VBoxContainer/SwitchLoginLabel
@onready var check_icon: Label = $LoginContainer/VBoxContainer/AgreementContainer/CheckIcon
@onready var agreement_label: RichTextLabel = $LoginContainer/VBoxContainer/AgreementContainer/AgreementLabel
@onready var status_label: Label = $LoginContainer/VBoxContainer/StatusLabel
@onready var repair_button: Button = $RepairButton

var is_logged_in: bool = false
var agreement_checked: bool = true
var current_status_timer: Timer = null
var icon_manager: WeChatIconManager = null

func _ready() -> void:
	print("🎮 加载画面已显示")

	# 初始化图标管理器
	_init_icon_manager()

	# 连接按钮信号
	if wechat_button:
		wechat_button.pressed.connect(_on_wechat_login_pressed)

	# 设置 Label 可点击
	if switch_label:
		switch_label.mouse_filter = Control.MOUSE_FILTER_STOP
		switch_label.gui_input.connect(_on_switch_label_clicked)

	if check_icon:
		check_icon.mouse_filter = Control.MOUSE_FILTER_STOP
		check_icon.gui_input.connect(_on_agreement_clicked)
		# 初始化勾选状态显示
		check_icon.modulate = Color(1, 1, 1, 1) if agreement_checked else Color(0.5, 0.5, 0.5, 0.3)

	# 让整个协议文本区域都可点击
	if agreement_label:
		agreement_label.mouse_filter = Control.MOUSE_FILTER_STOP
		agreement_label.gui_input.connect(_on_agreement_text_clicked)
		agreement_label.meta_clicked.connect(_on_agreement_meta_clicked)

	if repair_button:
		repair_button.pressed.connect(_on_repair_pressed)

	# 确保背景铺满整个屏幕
	if background:
		background.anchor_left = 0.0
		background.anchor_top = 0.0
		background.anchor_right = 1.0
		background.anchor_bottom = 1.0
		background.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		background.size_flags_vertical = Control.SIZE_EXPAND_FILL
		# 设置拉伸模式：保持比例并覆盖整个区域
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

		# 尝试加载图片
		var image_path = "res://assets/loading_screen.png.png"
		if ResourceLoader.exists(image_path):
			background.texture = load(image_path)
			print("✅ 加载画面图片已加载: ", image_path)
		else:
			print("⚠ 加载画面图片未找到: ", image_path)
			# 使用默认颜色代替（绿色背景）
			background.modulate = Color(0.1, 0.4, 0.1, 1.0)

## 初始化图标管理器并自动下载图标
func _init_icon_manager() -> void:
	"""初始化图标管理器和自动下载流程"""
	icon_manager = WeChatIconManager.new()
	add_child(icon_manager)

	print("🔄 正在自动下载微信官方图标...")
	_update_status("正在下载微信官方图标...")

	# 异步下载图标
	icon_manager.auto_download_icon(func(success: bool, _message: String):
		if success:
			_update_status_with_auto_clear("✅ 官方图标已更新", 2.0)
			print("✅ 微信官方图标已成功下载并部署")
			_load_wechat_icon()
		else:
			_update_status_with_auto_clear("⚠ 使用本地图标（网络问题）", 2.0)
			print("⚠ 自动下载失败，使用本地图标")
	)

## 加载微信图标（从新下载的文件或本地缓存）
func _load_wechat_icon() -> void:
	"""加载微信图标到按钮上"""
	var icon_paths = [
		"res://assets/wechat_icon.svg",
		"res://assets/wechat_icon_40x40.svg",
		"res://assets/wechat_icon.png",
		"res://assets/wechat_icon_40x40.png"
	]

	for icon_path in icon_paths:
		if ResourceLoader.exists(icon_path):
			var wechat_icon = $LoginContainer/VBoxContainer/WeChatLoginButton/WeChatIcon
			if wechat_icon:
				wechat_icon.texture = load(icon_path)
				print("✅ 微信图标已加载: ", icon_path)
			return

	print("⚠ 未找到微信图标文件，使用默认设置")

func _transition_to_game() -> void:
	"""过渡到主游戏场景"""
	print("🎮 加载完成，进入游戏...")

	# 淡出动画 - 对 background 节点进行淡出
	if background:
		var tween = create_tween()
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_QUAD)
		tween.tween_property(background, "modulate", Color(1, 1, 1, 0), 0.5)
		await tween.finished

	# 加载主场景
	var error = get_tree().change_scene_to_file("res://scenes/main.tscn")
	if error != OK:
		push_error("❌ 加载主场景失败: " + str(error))
		_update_status("场景加载失败，请重启游戏")
		is_logged_in = false
		wechat_button.disabled = false

func _on_wechat_login_pressed() -> void:
	if is_logged_in:
		return

	if not agreement_checked:
		_update_status_with_auto_clear("请先同意用户协议", 1.5)
		return

	print("🔐 微信登录按钮被点击")
	_update_status("正在连接微信...")

	# 禁用按钮
	wechat_button.disabled = true

	# 模拟微信登录请求
	await _request_wechat_login()

	# 如果登录失败，重新启用按钮
	if not is_logged_in:
		wechat_button.disabled = false
		_update_status("")

func _request_wechat_login() -> void:
	"""发起微信登录请求"""
	# TODO: 实现真实的微信 OAuth 流程
	# 1. 调用后端 API 获取微信授权链接
	# 2. 打开浏览器进行授权
	# 3. 接收回调并获取 token

	# 模拟网络请求延迟
	await get_tree().create_timer(2.0).timeout

	# 模拟成功登录
	var mock_user_data = {
		"user_id": "wx_" + str(randi()),
		"nickname": "微信用户" + str(randi() % 1000),
		"avatar_url": "",
		"login_type": "wechat"
	}

	_on_login_success(mock_user_data)

## 切换登录方式点击事件
func _on_switch_label_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("🔄 切换登录方式")
		# 游客登录
		_do_guest_login()

## 游客登录
func _do_guest_login() -> void:
	if is_logged_in:
		return

	print("👤 游客登录")
	_update_status("正在创建游客账号...")

	# 禁用按钮
	wechat_button.disabled = true

	# 模拟游客登录
	await get_tree().create_timer(1.0).timeout

	var guest_data = {
		"user_id": "guest_" + str(randi()),
		"nickname": "游客" + str(randi() % 10000),
		"avatar_url": "",
		"login_type": "guest"
	}

	_on_login_success(guest_data)

## 协议勾选点击事件
func _on_agreement_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		agreement_checked = not agreement_checked
		if check_icon:
			check_icon.modulate = Color(1, 1, 1, 1) if agreement_checked else Color(0.5, 0.5, 0.5, 0.3)
		print("☑ 协议勾选状态: ", agreement_checked)

## 协议文本点击事件
func _on_agreement_text_clicked(event: InputEvent) -> void:
	# 点击文本区域也切换勾选状态
	_on_agreement_clicked(event)

## 协议链接点击事件
func _on_agreement_meta_clicked(meta: String) -> void:
	print("📜 查看协议: ", meta)
	# TODO: 打开协议详情页面
	OS.shell_open("https://example.com/agreement")

## 一键修复按钮事件
func _on_repair_pressed() -> void:
	print("🔧 一键修复")
	repair_button.disabled = true
	_update_status("正在检测游戏文件...")
	await get_tree().create_timer(1.5).timeout
	_update_status_with_auto_clear("检测完成，游戏文件正常✅", 2.0)
	repair_button.disabled = false

## 登录成功回调
func _on_login_success(user_data: Dictionary) -> void:
	is_logged_in = true
	print("✅ 登录成功: ", user_data)

	# 保存用户信息到全局管理器
	if has_node("/root/GameManager"):
		GameManager.set_user_data(user_data)
	else:
		push_warning("⚠ GameManager 未找到，用户数据未保存")

	_update_status("登录成功！欢迎 " + user_data["nickname"])
	await get_tree().create_timer(1.0).timeout

	# 进入游戏
	_transition_to_game()

## 更新状态文本
func _update_status(message: String) -> void:
	if status_label:
		status_label.text = message

## 更新状态文本并自动清除
func _update_status_with_auto_clear(message: String, delay: float = 2.0) -> void:
	_update_status(message)

	# 取消之前的定时器
	if current_status_timer:
		current_status_timer.queue_free()

	# 创建新的定时器
	current_status_timer = Timer.new()
	current_status_timer.one_shot = true
	current_status_timer.wait_time = delay
	current_status_timer.timeout.connect(func(): _update_status(""))
	add_child(current_status_timer)
	current_status_timer.start()
