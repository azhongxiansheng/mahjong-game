extends Control

var wechat_button: Button = null
var guest_button: Button = null
var title_label: Label = null
var subtitle_label: Label = null

func _ready():
	print("WeChatLogin._ready() started")
	
	# 安全获取节点
	title_label = get_node_or_null("CenterContainer/VBoxContainer/TitleLabel")
	subtitle_label = get_node_or_null("CenterContainer/VBoxContainer/SubtitleLabel")
	wechat_button = get_node_or_null("CenterContainer/VBoxContainer/WeChatButton")
	guest_button = get_node_or_null("CenterContainer/VBoxContainer/GuestButton")
	
	if not title_label:
		print("⚠ TitleLabel not found")
	if not subtitle_label:
		print("⚠ SubtitleLabel not found")
	if not wechat_button:
		print("⚠ WeChatButton not found")
	if not guest_button:
		print("⚠ GuestButton not found")
	
	# 连接按钮信号
	if wechat_button:
		wechat_button.pressed.connect(_on_wechat_login_pressed)
	if guest_button:
		guest_button.pressed.connect(_on_guest_login_pressed)
	
	print("微信登录页面加载完成")

func _on_wechat_login_pressed():
	print("点击微信登录")
	
	# 禁用按钮防止重复点击
	if wechat_button:
		wechat_button.disabled = true
		wechat_button.text = "登录中..."
	
	# TODO: 这里将来调用微信SDK进行实际登录
	# 现在模拟登录流程
	await get_tree().create_timer(0.5).timeout
	
	# 模拟登录成功，保存用户信息
	var user_data = {
		"user_id": "wx_" + str(Time.get_ticks_msec()),
		"nickname": "微信用户",
		"avatar": "",
		"login_type": "wechat"
	}
	GameManager.set_user_data(user_data)
	
	_transition_to_game()

func _on_guest_login_pressed():
	print("点击游客登录")
	
	# 禁用按钮
	if guest_button:
		guest_button.disabled = true
		guest_button.text = "登录中..."
	
	await get_tree().create_timer(0.3).timeout
	
	# 游客登录，生成临时ID
	var user_data = {
		"user_id": "guest_" + str(Time.get_ticks_msec()),
		"nickname": "游客" + str(randi() % 10000),
		"avatar": "",
		"login_type": "guest"
	}
	GameManager.set_user_data(user_data)
	
	_transition_to_game()

func _transition_to_game():
	print("登录成功，进入游戏...")
	get_tree().change_scene_to_file("res://scenes/loading_screen_new.tscn")
