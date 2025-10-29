class_name NotificationUI
extends CanvasLayer

## 依赖
var notification_center: NotificationCenter

## UI 组件
var notification_list: VBoxContainer
var scroll_container: ScrollContainer
var main_panel: PanelContainer

## 显示配置
var is_showing: bool = false
var current_notifications: Dictionary = {}  # {notification_id: UI_item}

## 动画配置
const SLIDE_IN_DURATION = 0.3
const SLIDE_OUT_DURATION = 0.3
const NOTIFICATION_HEIGHT = 80
const MAX_VISIBLE_NOTIFICATIONS = 5
const AUTO_HIDE_DELAY = 5.0


## 信号
signal notification_clicked(notification: Notification)
signal notification_dismissed(notification_id: String)


## 初始化
func _ready() -> void:
	"""初始化通知 UI"""
	_create_ui()
	_setup_styles()
	print("[NotificationUI] Initialized successfully")


## 公共方法

func set_notification_center(center: NotificationCenter) -> void:
	"""设置通知中心"""
	notification_center = center
	if notification_center:
		notification_center.notification_received.connect(_on_notification_received)
		notification_center.notification_read.connect(_on_notification_read)
		notification_center.unread_count_changed.connect(_on_unread_count_changed)
		print("[NotificationUI] Connected to notification center")


func show_ui() -> void:
	"""显示通知 UI"""
	main_panel.visible = true
	is_showing = true
	_refresh_list()
	_animate_in()
	print("[NotificationUI] UI shown")


func hide_ui() -> void:
	"""隐藏通知 UI"""
	_animate_out()
	is_showing = false
	print("[NotificationUI] UI hidden")


func toggle_ui() -> void:
	"""切换通知 UI"""
	if is_showing:
		hide_ui()
	else:
		show_ui()


func display_toast(notification: Notification) -> void:
	"""显示通知吐司 (短暂提示)"""
	var toast = _create_toast_item(notification)
	scroll_container.add_child(toast)

	# 自动隐藏
	await get_tree().create_timer(AUTO_HIDE_DELAY).timeout

	if is_instance_valid(toast):
		_animate_toast_out(toast)
		await get_tree().create_timer(SLIDE_OUT_DURATION).timeout
		toast.queue_free()


func add_notification_visual(notification: Notification) -> void:
	"""添加通知到 UI"""
	if current_notifications.has(notification.notification_id):
		return  # 已存在

	var item = _create_notification_item(notification)
	notification_list.add_child(item)
	current_notifications[notification.notification_id] = item

	# 动画显示
	_animate_item_in(item)


func remove_notification_visual(notification_id: String) -> void:
	"""从 UI 中移除通知"""
	if not current_notifications.has(notification_id):
		return

	var item = current_notifications[notification_id]
	_animate_item_out(item)
	await get_tree().create_timer(SLIDE_OUT_DURATION).timeout
	item.queue_free()
	current_notifications.erase(notification_id)
	notification_dismissed.emit(notification_id)


func clear_all_visual() -> void:
	"""清空所有通知 UI"""
	for item in notification_list.get_children():
		item.queue_free()
	current_notifications.clear()


## 私有方法 - UI 创建

func _create_ui() -> void:
	"""创建 UI 组件"""
	# 创建主面板
	main_panel = PanelContainer.new()
	main_panel.custom_minimum_size = Vector2(400, 600)
	main_panel.position = Vector2(get_viewport_rect().size.x - 420, 20)
	main_panel.visible = false
	add_child(main_panel)

	# 创建主容器
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 5)
	main_panel.add_child(main_vbox)

	# 创建标题栏
	var title_hbox = HBoxContainer.new()
	main_vbox.add_child(title_hbox)

	var title = Label.new()
	title.text = "📢 通知"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(title)

	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(hide_ui)
	title_hbox.add_child(close_btn)

	# 创建滚动容器和列表
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll_container)

	notification_list = VBoxContainer.new()
	notification_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notification_list.add_theme_constant_override("separation", 5)
	scroll_container.add_child(notification_list)


func _setup_styles() -> void:
	"""设置样式"""
	# 面板样式
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.08, 0.95)
	panel_style.set_border_enabled_all(true)
	panel_style.set_border_width_all(2)
	panel_style.border_color = Color(0.3, 0.6, 1.0, 0.8)
	panel_style.set_corner_radius_all(10)
	main_panel.add_theme_stylebox_override("panel", panel_style)


## 项目创建

func _create_notification_item(notification: Notification) -> PanelContainer:
	"""创建通知项"""
	var item = PanelContainer.new()
	item.custom_minimum_size = Vector2(0, NOTIFICATION_HEIGHT)

	# 背景样式
	var style = StyleBoxFlat.new()
	style.bg_color = notification.get_priority_color().lightened(0.3)
	style.set_corner_radius_all(5)
	item.add_theme_stylebox_override("panel", style)

	# 容器
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	item.add_child(hbox)

	# 图标
	var icon_label = Label.new()
	icon_label.text = notification.get_icon_emoji()
	icon_label.add_theme_font_size_override("font_size", 24)
	hbox.add_child(icon_label)

	# 内容
	var content_vbox = VBoxContainer.new()
	hbox.add_child(content_vbox)

	var title_label = Label.new()
	title_label.text = notification.title
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	content_vbox.add_child(title_label)

	var content_label = Label.new()
	content_label.text = notification.content
	content_label.add_theme_font_size_override("font_size", 10)
	content_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	content_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	content_vbox.add_child(content_label)

	var time_label = Label.new()
	time_label.text = notification.get_time_ago()
	time_label.add_theme_font_size_override("font_size", 8)
	time_label.add_theme_color_override("font_color", Color.GRAY)
	content_vbox.add_child(time_label)

	# 按钮容器
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 5)
	hbox.add_child(btn_hbox)

	# 查看按钮
	var view_btn = Button.new()
	view_btn.text = "查看"
	view_btn.custom_minimum_size = Vector2(50, 30)
	view_btn.pressed.connect(func():
		notification_center.mark_as_read(notification.notification_id)
		notification_clicked.emit(notification)
	)
	btn_hbox.add_child(view_btn)

	# 关闭按钮
	var close_btn = Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(func():
		remove_notification_visual(notification.notification_id)
	)
	btn_hbox.add_child(close_btn)

	return item


func _create_toast_item(notification: Notification) -> PanelContainer:
	"""创建吐司项"""
	var item = PanelContainer.new()
	item.custom_minimum_size = Vector2(300, 60)

	# 背景样式
	var style = StyleBoxFlat.new()
	style.bg_color = notification.get_priority_color().lightened(0.2)
	style.set_corner_radius_all(8)
	item.add_theme_stylebox_override("panel", style)

	# 容器
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	item.add_child(hbox)

	# 图标
	var icon = Label.new()
	icon.text = notification.get_icon_emoji()
	icon.add_theme_font_size_override("font_size", 20)
	hbox.add_child(icon)

	# 文本
	var text = Label.new()
	text.text = notification.content
	text.add_theme_font_size_override("font_size", 10)
	text.add_theme_color_override("font_color", Color.WHITE)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD
	hbox.add_child(text)

	return item


## 动画

func _animate_in() -> void:
	"""面板显示动画"""
	var tween = create_tween()
	tween.set_ease(Tween.EaseType.EASE_OUT)
	tween.set_trans(Tween.TransitionType.TRANS_BACK)
	tween.tween_property(main_panel, "position", Vector2(get_viewport_rect().size.x - 420, 20), SLIDE_IN_DURATION)


func _animate_out() -> void:
	"""面板隐藏动画"""
	var tween = create_tween()
	tween.set_ease(Tween.EaseType.EASE_IN)
	tween.set_trans(Tween.TransitionType.TRANS_BACK)
	tween.tween_property(main_panel, "position", Vector2(get_viewport_rect().size.x + 10, 20), SLIDE_OUT_DURATION)
	await tween.finished
	main_panel.visible = false


func _animate_item_in(item: Control) -> void:
	"""项目显示动画"""
	item.position.x = -item.custom_minimum_size.x
	var tween = create_tween()
	tween.set_ease(Tween.EaseType.EASE_OUT)
	tween.tween_property(item, "position:x", 0, SLIDE_IN_DURATION)


func _animate_item_out(item: Control) -> void:
	"""项目隐藏动画"""
	var tween = create_tween()
	tween.set_ease(Tween.EaseType.EASE_IN)
	tween.tween_property(item, "position:x", -item.custom_minimum_size.x, SLIDE_OUT_DURATION)


func _animate_toast_out(item: Control) -> void:
	"""吐司隐藏动画"""
	var tween = create_tween()
	tween.set_ease(Tween.EaseType.EASE_IN)
	tween.tween_property(item, "modulate", Color(1, 1, 1, 0), SLIDE_OUT_DURATION)


## 列表刷新

func _refresh_list() -> void:
	"""刷新通知列表"""
	if not notification_center:
		return

	# 清空现有
	for child in notification_list.get_children():
		child.queue_free()
	current_notifications.clear()

	# 添加最近通知
	var notifications = notification_center.get_recent_notifications(notification_center.current_user_id, MAX_VISIBLE_NOTIFICATIONS)
	for notif in notifications:
		add_notification_visual(notif)


## 信号处理

func _on_notification_received(notification: Notification) -> void:
	"""收到新通知时"""
	add_notification_visual(notification)
	display_toast(notification)


func _on_notification_read(notification_id: String) -> void:
	"""通知被标记为已读时"""
	if current_notifications.has(notification_id):
		var item = current_notifications[notification_id]
		# 更新样式 (可选)


func _on_unread_count_changed(count: int) -> void:
	"""未读数量变化时"""
	# 更新 UI (例如徽章)
	pass


## 调试

func print_summary() -> void:
	"""打印摘要"""
	print("\n=== 通知 UI 摘要 ===")
	print("显示状态: %s" % ("显示中" if is_showing else "隐藏"))
	print("显示通知: %d" % current_notifications.size())
	if notification_center:
		print("未读通知: %d" % notification_center.total_unread)
	print("==================\n")
