extends Control

func _ready():
	print("MainSimple loaded successfully")
	
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.3, 0.2, 1.0)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	
	var label = Label.new()
	label.text = "麻将游戏主界面\n\n游戏加载成功！\n\n按 ESC 返回登录"
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_left = 0.5
	label.anchor_top = 0.5
	label.anchor_right = 0.5
	label.anchor_bottom = 0.5
	label.offset_left = -300
	label.offset_top = -100
	label.offset_right = 300
	label.offset_bottom = 100
	add_child(label)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().change_scene_to_file("res://scenes/wechat_login_new.tscn")
