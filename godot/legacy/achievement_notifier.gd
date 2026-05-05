## 成就通知系统 - 显示成就解锁通知
## 处理成就解锁时的通知展示和动画效果

class_name AchievementNotifier
extends CanvasLayer

# ============ 节点引用 ============
@onready var notification_panel = $NotificationPanel
@onready var title_label = $NotificationPanel/VBoxContainer/TitleLabel
@onready var description_label = $NotificationPanel/VBoxContainer/DescriptionLabel
@onready var reward_label = $NotificationPanel/VBoxContainer/RewardLabel
@onready var icon_rect = $NotificationPanel/IconRect

# ============ 显示配置 ============
var notification_duration: float = 3.0   # 通知显示时长（秒）
var animation_speed: float = 0.3         # 动画速度（秒）
var queue: Array = []                    # 待显示的通知队列
var is_showing: bool = false            # 是否正在显示

# ============ 动画变量 ============
var current_tween: Tween


# ============ 初始化 ============

func _ready() -> void:
	"""初始化通知系统"""
	layer = 100  # 高优先级显示
	hide_notification()
	print("[AchievementNotifier] 通知系统初始化完成")


# ============ 通知管理 ============

func show_achievement(achievement: Achievement) -> void:
	"""显示成就解锁通知

	参数:
		achievement: 已解锁的成就对象
	"""
	# 如果正在显示，添加到队列
	if is_showing:
		queue.append(achievement)
		return

	# 显示通知
	_display_notification(achievement)


func _display_notification(achievement: Achievement) -> void:
	"""显示单个通知

	参数:
		achievement: 成就对象
	"""
	is_showing = true

	# 更新UI内容
	title_label.text = "🏆 " + achievement.name
	description_label.text = achievement.description
	reward_label.text = "✓ +%d 成就点数" % achievement.reward_points

	# 设置图标背景颜色（根据稀有度）
	_set_rarity_color(achievement.rarity)

	# 显示和动画
	visible = true
	_play_show_animation()

	# 自动隐藏
	await get_tree().create_timer(notification_duration).timeout
	_play_hide_animation()

	# 检查队列
	if queue.size() > 0:
		var next_achievement = queue.pop_front()
		_display_notification(next_achievement)
	else:
		is_showing = false


func _set_rarity_color(rarity: String) -> void:
	"""根据稀有度设置颜色

	参数:
		rarity: 稀有度字符串
	"""
	var color = Color.WHITE

	match rarity:
		"common":
			color = Color(0.8, 0.8, 0.8, 0.9)  # 灰色
		"uncommon":
			color = Color(0.0, 1.0, 0.0, 0.9)  # 绿色
		"rare":
			color = Color(0.0, 0.5, 1.0, 0.9)  # 蓝色
		"epic":
			color = Color(1.0, 0.0, 1.0, 0.9)  # 紫色
		"legendary":
			color = Color(1.0, 0.8, 0.0, 0.9)  # 金色

	# 设置背景颜色
	if notification_panel and notification_panel.has_node("BackPanel"):
		notification_panel.get_node("BackPanel").self_modulate = color


# ============ 动画效果 ============

func _play_show_animation() -> void:
	"""播放显示动画"""
	if current_tween:
		current_tween.kill()

	current_tween = create_tween()
	current_tween.set_trans(Tween.TRANS_BACK)
	current_tween.set_ease(Tween.EASE_OUT)

	# 从右边滑入
	notification_panel.position.x = 500
	current_tween.tween_property(notification_panel, "position:x", 0, animation_speed)

	# 淡入
	notification_panel.modulate.a = 0.0
	var tween2 = create_tween()
	tween2.tween_property(notification_panel, "modulate:a", 1.0, animation_speed)


func _play_hide_animation() -> void:
	"""播放隐藏动画"""
	if current_tween:
		current_tween.kill()

	current_tween = create_tween()
	current_tween.set_trans(Tween.TRANS_BACK)
	current_tween.set_ease(Tween.EASE_IN)

	# 向右滑出
	current_tween.tween_property(notification_panel, "position:x", 500, animation_speed)

	# 淡出
	var tween2 = create_tween()
	tween2.tween_property(notification_panel, "modulate:a", 0.0, animation_speed)

	await tween2.finished
	visible = false


# ============ UI 控制 ============

func hide_notification() -> void:
	"""立即隐藏通知"""
	if current_tween:
		current_tween.kill()

	visible = false
	is_showing = false
	queue.clear()


func clear_queue() -> void:
	"""清空通知队列"""
	queue.clear()


# ============ 调试 ============

func test_notification() -> void:
	"""测试通知显示"""
	var test_achievement = Achievement.new("test", "测试成就")
	test_achievement.description = "这是一个测试通知"
	test_achievement.rarity = "epic"
	test_achievement.reward_points = 500

	show_achievement(test_achievement)


func print_queue_status() -> void:
	"""打印队列状态"""
	print("[AchievementNotifier] 队列中有 %d 个通知待显示" % queue.size())
	print("  当前显示状态: %s" % ("显示中" if is_showing else "就绪"))
