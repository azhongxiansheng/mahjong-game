## 成就UI系统 - 成就列表展示和交互
## 显示成就列表、进度条、分类标签等

class_name AchievementUI
extends CanvasLayer

# ============ 节点引用 ============
@onready var panel = $Panel
@onready var title_label = $Panel/VBoxContainer/TitleLabel
@onready var tab_container = $Panel/VBoxContainer/TabContainer
@onready var scroll_container = $Panel/VBoxContainer/ScrollContainer
@onready var achievement_list = $Panel/VBoxContainer/ScrollContainer/VBoxContainer
@onready var close_button = $Panel/VBoxContainer/HBoxContainer/CloseButton
@onready var stats_label = $Panel/VBoxContainer/HBoxContainer/StatsLabel

# ============ 系统引用 ============
var achievement_system: AchievementSystem
var notifier: AchievementNotifier

# ============ UI 配置 ============
var current_category: String = "all"
var current_entries: Array = []
var is_visible_ui: bool = false
var entry_height: float = 60.0
var entry_spacing: float = 5.0

# ============ 显示配置 ============
const ENTRY_BACKGROUND_COLOR = Color(0.1, 0.1, 0.1, 0.5)
const ENTRY_HIGHLIGHT_COLOR = Color(0.2, 0.3, 0.5, 0.8)
const UNLOCKED_COLOR = Color(0.2, 1.0, 0.2, 0.8)


# ============ 初始化 ============

func _ready() -> void:
	"""初始化 UI"""
	layer = 50
	_setup_ui()
	_setup_tabs()
	_connect_signals()
	hide_achievements()
	print("[AchievementUI] UI 系统初始化完成")


func _setup_ui() -> void:
	"""设置 UI 组件"""
	if close_button:
		close_button.pressed.connect(_on_close_pressed)
	
	panel.modulate = Color.WHITE
	panel.modulate.a = 0.95


func _setup_tabs() -> void:
	"""设置标签页"""
	if not tab_container:
		return
	
	# 清空默认标签
	for i in range(tab_container.get_tab_count()):
		tab_container.remove_child(tab_container.get_child(0))
	
	# 添加标签页
	var categories = ["all", "progress", "oneshot", "hidden", "seasonal"]
	var labels = ["全部", "进度类", "一次性", "隐藏", "季节"]
	
	for i in range(categories.size()):
		var tab = Control.new()
		tab_container.add_child(tab)
		tab_container.set_tab_title(i, labels[i])
	
	tab_container.tab_changed.connect(_on_tab_changed)


func _connect_signals() -> void:
	"""连接信号"""
	if achievement_system:
		achievement_system.achievement_unlocked.connect(_on_achievement_unlocked)
		achievement_system.progress_updated.connect(_on_progress_updated)


# ============ 系统配置 ============

func set_achievement_system(system: AchievementSystem) -> void:
	"""设置成就系统引用
	
	参数:
		system: AchievementSystem 实例
	"""
	achievement_system = system
	if achievement_system:
		achievement_system.achievement_unlocked.connect(_on_achievement_unlocked)
		achievement_system.progress_updated.connect(_on_progress_updated)
		print("[AchievementUI] 已连接到成就系统")


func set_notifier(notifier_instance: AchievementNotifier) -> void:
	"""设置通知系统引用
	
	参数:
		notifier_instance: AchievementNotifier 实例
	"""
	notifier = notifier_instance
	print("[AchievementUI] 已连接到通知系统")


# ============ 成就列表更新 ============

func refresh_achievements() -> void:
	"""刷新成就列表"""
	if not achievement_system:
		return
	
	_clear_list()
	_update_achievement_list()
	_update_stats()


func _update_achievement_list() -> void:
	"""更新成就列表显示"""
	if not achievement_system:
		return
	
	# 根据当前分类获取成就
	var achievements: Array
	if current_category == "all":
		achievements = achievement_system.get_all_achievements()
	else:
		achievements = achievement_system.get_achievements_by_category(current_category)
	
	# 按解锁状态和名称排序
	achievements.sort_custom(func(a, b):
		if a.is_unlocked != b.is_unlocked:
			return a.is_unlocked  # 已解锁的在前
		return a.name < b.name
	)
	
	current_entries = achievements
	
	# 创建条目
	for achievement in achievements:
		_create_entry_item(achievement)


func _create_entry_item(achievement: Achievement) -> PanelContainer:
	"""创建单个成就条目
	
	参数:
		achievement: Achievement 对象
	
	返回:
		PanelContainer 节点
	"""
	var panel_container = PanelContainer.new()
	panel_container.custom_minimum_size = Vector2(0, entry_height)
	
	var color = ENTRY_BACKGROUND_COLOR
	if achievement.is_unlocked:
		color = UNLOCKED_COLOR
	
	var style_box = StyleBoxFlat.new()
	style_box.bg_color = color
	style_box.corner_radius_top_left = 5
	style_box.corner_radius_top_right = 5
	style_box.corner_radius_bottom_right = 5
	style_box.corner_radius_bottom_left = 5
	
	var style_box_stylebox = StyleBoxFlat.new()
	style_box_stylebox.set("panel", style_box)
	
	var h_box = HBoxContainer.new()
	h_box.add_theme_constant_override("separation", 10)
	
	# 稀有度图标
	var rarity_label = Label.new()
	rarity_label.text = achievement.get_tier_emoji()
	rarity_label.custom_minimum_size = Vector2(30, 0)
	h_box.add_child(rarity_label)
	
	# 成就名称
	var name_label = Label.new()
	name_label.text = achievement.name
	name_label.custom_minimum_size = Vector2(150, 0)
	h_box.add_child(name_label)
	
	# 进度条
	if achievement.max_progress > 1:
		var progress_bar = ProgressBar.new()
		progress_bar.value = achievement.get_progress_percent() * 100
		progress_bar.custom_minimum_size = Vector2(150, 20)
		progress_bar.show_percentage = false
		h_box.add_child(progress_bar)
	
	# 进度文本
	var progress_text = Label.new()
	if achievement.max_progress > 1:
		progress_text.text = "%d/%d" % [achievement.progress, achievement.max_progress]
	else:
		progress_text.text = "✓" if achievement.is_unlocked else "⏳"
	progress_text.custom_minimum_size = Vector2(50, 0)
	h_box.add_child(progress_text)
	
	# 奖励信息
	var reward_label = Label.new()
	reward_label.text = "+%d" % achievement.reward_points
	reward_label.custom_minimum_size = Vector2(60, 0)
	reward_label.add_theme_font_size_override("font_size", 14)
	h_box.add_child(reward_label)
	
	panel_container.add_child(h_box)
	achievement_list.add_child(panel_container)
	
	return panel_container


func _update_stats() -> void:
	"""更新统计信息"""
	if not achievement_system:
		return
	
	var stats = achievement_system.get_statistics()
	var text = "📊 成就: %d/%d | 完成度: %.0f%% | 总点数: %d" % [
		stats["unlocked_count"],
		stats["total_achievements"],
		stats["completion_percent"] * 100,
		stats["total_points"]
	]
	
	stats_label.text = text


func _clear_list() -> void:
	"""清空成就列表"""
	for child in achievement_list.get_children():
		child.queue_free()


# ============ 标签页切换 ============

func _on_tab_changed(tab: int) -> void:
	"""标签页切换事件"""
	var categories = ["all", "progress", "oneshot", "hidden", "seasonal"]
	if tab < categories.size():
		current_category = categories[tab]
		refresh_achievements()
		print("[AchievementUI] 切换到标签页: %s" % current_category)


# ============ 成就事件 ============

func _on_achievement_unlocked(achievement: Achievement) -> void:
	"""成就解锁事件"""
	if notifier:
		notifier.show_achievement(achievement)
	
	# 刷新列表（如果 UI 可见）
	if is_visible_ui:
		refresh_achievements()


func _on_progress_updated(achievement_id: String, progress: int) -> void:
	"""进度更新事件"""
	# 可以在这里添加进度条更新逻辑
	pass


# ============ UI 显示/隐藏 ============

func show_achievements() -> void:
	"""显示成就 UI"""
	is_visible_ui = true
	visible = true
	refresh_achievements()
	print("[AchievementUI] 成就 UI 已显示")


func hide_achievements() -> void:
	"""隐藏成就 UI"""
	is_visible_ui = false
	visible = false
	print("[AchievementUI] 成就 UI 已隐藏")


func toggle_achievements() -> void:
	"""切换成就 UI 显示/隐藏"""
	if is_visible_ui:
		hide_achievements()
	else:
		show_achievements()


func _on_close_pressed() -> void:
	"""关闭按钮事件"""
	hide_achievements()


# ============ 查询和统计 ============

func get_summary() -> String:
	"""获取摘要信息"""
	if not achievement_system:
		return "无"
	
	var stats = achievement_system.get_statistics()
	return "成就: %d/%d | 完成度: %.0f%%" % [
		stats["unlocked_count"],
		stats["total_achievements"],
		stats["completion_percent"] * 100
	]


func print_summary() -> void:
	"""打印摘要"""
	print("[AchievementUI] %s" % get_summary())
