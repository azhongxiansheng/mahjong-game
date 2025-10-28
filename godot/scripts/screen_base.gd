class_name ScreenBase
extends Control

# UI界面基类
# 所有游戏界面都应继承自此类

# 信号
signal screen_shown
signal screen_hidden
signal back_pressed

# 属性
var is_visible_on_screen: bool = false
var animation_duration: float = 0.3

func _ready() -> void:
	"""初始化UI界面"""
	visible = false
	is_visible_on_screen = false
	print("ScreenBase (%s): 已初始化" % name)

func show_screen() -> void:
	"""显示界面（带动画）"""
	if is_visible_on_screen:
		return

	is_visible_on_screen = true
	visible = true

	# 播放淡入动画
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_OUT)
	modulate.a = 0.0
	tween.tween_property(self, "modulate:a", 1.0, animation_duration)

	on_enter()
	screen_shown.emit()
	print("ScreenBase (%s): 界面已显示" % name)

func hide_screen() -> void:
	"""隐藏界面（带动画）"""
	if not is_visible_on_screen:
		return

	is_visible_on_screen = false

	# 播放淡出动画
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, animation_duration)
	tween.tween_callback(func(): visible = false)

	on_exit()
	screen_hidden.emit()
	print("ScreenBase (%s): 界面已隐藏" % name)

func on_enter() -> void:
	"""界面显示时的回调 - 子类可覆盖"""
	pass

func on_exit() -> void:
	"""界面隐藏时的回调 - 子类可覆盖"""
	pass

func transition_to(next_screen: ScreenBase) -> void:
	"""过渡到下一个界面"""
	hide_screen()
	await get_tree().create_timer(animation_duration).timeout
	next_screen.show_screen()

func show_message(message: String, duration: float = 2.0) -> void:
	"""显示临时消息"""
	print("ScreenBase (%s): %s" % [name, message])

func show_error(error: String) -> void:
	"""显示错误消息"""
	print("ScreenBase (%s): 错误 - %s" % [name, error])

func _input(event: InputEvent) -> void:
	"""处理输入事件"""
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			back_pressed.emit()
			get_tree().root.set_input_as_handled()

func get_center_position() -> Vector2:
	"""获取屏幕中心位置"""
	return get_viewport_rect().get_center()

func create_button(text: String, callback: Callable, position: Vector2 = Vector2.ZERO) -> Button:
	"""创建一个按钮"""
	var button = Button.new()
	button.text = text
	button.pressed.connect(callback)
	if position != Vector2.ZERO:
		button.position = position
	add_child(button)
	return button

func create_label(text: String, position: Vector2 = Vector2.ZERO) -> Label:
	"""创建一个标签"""
	var label = Label.new()
	label.text = text
	if position != Vector2.ZERO:
		label.position = position
	add_child(label)
	return label
