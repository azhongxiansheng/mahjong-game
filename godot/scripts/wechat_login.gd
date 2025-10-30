extends Control

var title_label: Label = null
var status_label: Label = null

func _ready():
	print("WeChatLogin._ready() started")
	
	# 安全获取节点
	title_label = get_node_or_null("CenterContainer/VBoxContainer/TitleLabel")
	status_label = get_node_or_null("CenterContainer/VBoxContainer/StatusLabel")
	
	if not title_label:
		print("⚠ TitleLabel not found")
	if not status_label:
		print("⚠ StatusLabel not found")
	
	print("WeChat Login page loaded")
	
	# 延迟2秒后自动跳转
	await get_tree().create_timer(2.0).timeout
	_on_login_success()

func _on_login_success():
	print("Login successful, transitioning to loading screen...")
	get_tree().change_scene_to_file("res://scenes/loading_screen_new.tscn")
