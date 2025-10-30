## 成就系统 - 核心管理类
## 管理游戏中所有的成就
## 提供成就注册、解锁、查询等功能

class_name AchievementSystem
extends Node

# ============ 数据存储 ============
var achievements: Dictionary = {} # id -> Achievement
var achievements_by_category: Dictionary = {} # category -> [Achievement]
var player_achievements_data: Dictionary = {} # 用于持久化的数据

# ============ 统计数据 ============
var total_points: int = 0
var total_unlocked: int = 0

# ============ 信号 ============
signal achievement_unlocked(achievement: Achievement)
signal progress_updated(achievement_id: String, progress: int)
signal category_completed(category: String)
signal all_achievements_loaded()


# ============ 初始化 ============

func _ready() -> void:
	"""初始化系统"""
	print("[AchievementSystem] 系统初始化完成")


# ============ 成就注册 ============

func register_achievement(achievement: Achievement) -> void:
	"""注册成就

	参数:
		achievement: Achievement 对象
	"""
	if achievements.has(achievement.id):
		print("[AchievementSystem] 警告: 成就 %s 已存在" % achievement.id)
		return

	achievements[achievement.id] = achievement

	# 按分类分组
	if not achievements_by_category.has(achievement.category):
		achievements_by_category[achievement.category] = []
	achievements_by_category[achievement.category].append(achievement)

	# 连接信号
	achievement.unlocked.connect(_on_achievement_unlocked.bind(achievement))
	achievement.progress_changed.connect(_on_achievement_progress_changed.bind(achievement.id))

	print("[AchievementSystem] 成就已注册: %s (%s)" % [achievement.name, achievement.id])


func register_achievements(achievement_list: Array) -> void:
	"""批量注册成就

	参数:
		achievement_list: Achievement 对象数组
	"""
	for achievement in achievement_list:
		register_achievement(achievement)


# ============ 成就解锁/更新 ============

func unlock_achievement(achievement_id: String) -> bool:
	"""解锁成就

	参数:
		achievement_id: 成就ID

	返回:
		bool: 是否成功解锁
	"""
	if not achievements.has(achievement_id):
		print("[AchievementSystem] 错误: 成就 %s 不存在" % achievement_id)
		return false

	var achievement = achievements[achievement_id]
	if not achievement.is_unlocked:
		achievement.unlock()
		_update_statistics()
		return true

	return false


func update_achievement_progress(achievement_id: String, amount: int) -> void:
	"""更新成就进度

	参数:
		achievement_id: 成就ID
		amount: 增加的进度数值
	"""
	if not achievements.has(achievement_id):
		print("[AchievementSystem] 错误: 成就 %s 不存在" % achievement_id)
		return

	var achievement = achievements[achievement_id]
	if achievement.update_progress(amount):
		achievement_unlocked.emit(achievement)
		_update_statistics()


func set_achievement_progress(achievement_id: String, progress: int) -> void:
	"""直接设置成就进度

	参数:
		achievement_id: 成就ID
		progress: 新的进度值
	"""
	if not achievements.has(achievement_id):
		print("[AchievementSystem] 错误: 成就 %s 不存在" % achievement_id)
		return

	var achievement = achievements[achievement_id]
	if achievement.set_progress(progress):
		achievement_unlocked.emit(achievement)
		_update_statistics()


# ============ 成就查询 ============

func get_achievement(achievement_id: String) -> Achievement:
	"""获取成就对象

	参数:
		achievement_id: 成就ID

	返回:
		Achievement 对象，不存在返回 null
	"""
	return achievements.get(achievement_id, null)


func get_all_achievements() -> Array:
	"""获取所有成就"""
	return achievements.values()


func get_unlocked_achievements() -> Array:
	"""获取所有已解锁的成就"""
	var unlocked = []
	for achievement in achievements.values():
		if achievement.is_unlocked:
			unlocked.append(achievement)
	return unlocked


func get_locked_achievements() -> Array:
	"""获取所有未解锁的成就"""
	var locked = []
	for achievement in achievements.values():
		if not achievement.is_unlocked:
			locked.append(achievement)
	return locked


func get_achievements_by_category(category: String) -> Array:
	"""获取指定分类的所有成就

	参数:
		category: 分类名称

	返回:
		成就数组
	"""
	return achievements_by_category.get(category, [])


func get_category_progress(category: String) -> Dictionary:
	"""获取分类进度

	参数:
		category: 分类名称

	返回:
		包含 total, unlocked, percent 的字典
	"""
	if not achievements_by_category.has(category):
		return {"total": 0, "unlocked": 0, "percent": 0.0}

	var achievements_in_category = achievements_by_category[category]
	var total = achievements_in_category.size()
	var unlocked = 0

	for achievement in achievements_in_category:
		if achievement.is_unlocked:
			unlocked += 1

	return {
		"total": total,
		"unlocked": unlocked,
		"percent": float(unlocked) / float(total) if total > 0 else 0.0
	}


# ============ 统计信息 ============

func get_total_points() -> int:
	"""获取总成就点数（仅已解锁的）"""
	return total_points


func get_unlocked_count() -> int:
	"""获取已解锁成就数量"""
	return total_unlocked


func get_total_count() -> int:
	"""获取总成就数量"""
	return achievements.size()


func get_completion_percent() -> float:
	"""获取完成度百分比"""
	if achievements.size() == 0:
		return 0.0
	return float(total_unlocked) / float(achievements.size())


func get_statistics() -> Dictionary:
	"""获取统计信息"""
	var category_stats = {}
	for category in achievements_by_category.keys():
		category_stats[category] = get_category_progress(category)

	return {
		"total_achievements": achievements.size(),
		"unlocked_count": total_unlocked,
		"total_points": total_points,
		"completion_percent": get_completion_percent(),
		"by_category": category_stats
	}


# ============ JSON 导入导出 ============

func export_to_json() -> String:
	"""导出所有成就为 JSON"""
	var data = []
	for achievement in achievements.values():
		data.append(achievement.to_dict())
	return JSON.stringify(data)


func import_from_json(json_data: String) -> bool:
	"""从 JSON 导入成就数据

	参数:
		json_data: JSON 字符串

	返回:
		bool: 是否导入成功
	"""
	var data = JSON.parse_string(json_data)
	if data == null:
		print("[AchievementSystem] 错误: JSON 解析失败")
		return false

	if not data is Array:
		print("[AchievementSystem] 错误: JSON 数据不是数组")
		return false

	for item in data:
		if achievements.has(item["id"]):
			var achievement = achievements[item["id"]]
			achievement.from_dict(item)

	_update_statistics()
	print("[AchievementSystem] 成就数据已导入")
	return true


# ============ 内部辅助函数 ============

func _on_achievement_unlocked(achievement: Achievement) -> void:
	"""成就解锁事件处理"""
	_update_statistics()
	achievement_unlocked.emit(achievement)
	print("[AchievementSystem] 成就已解锁: %s" % achievement.name)


func _on_achievement_progress_changed(achievement_id: String, progress: int) -> void:
	"""成就进度变化事件处理"""
	progress_updated.emit(achievement_id, progress)


func _update_statistics() -> void:
	"""更新统计数据"""
	total_points = 0
	total_unlocked = 0

	for achievement in achievements.values():
		if achievement.is_unlocked:
			total_points += achievement.reward_points
			total_unlocked += 1


# ============ 调试信息 ============

func print_summary() -> String:
	"""获取系统摘要信息"""
	var summary = "=== 成就系统摘要 ===\n"
	summary += "总成就数: %d\n" % achievements.size()
	summary += "已解锁: %d\n" % total_unlocked
	summary += "完成度: %.1f%%\n" % (get_completion_percent() * 100)
	summary += "总点数: %d\n" % total_points

	summary += "\n按分类统计:\n"
	for category in achievements_by_category.keys():
		var progress = get_category_progress(category)
		summary += "  %s: %d/%d (%.0f%%)\n" % [
			category,
			progress["unlocked"],
			progress["total"],
			progress["percent"] * 100
		]

	return summary


func print_achievements() -> void:
	"""打印所有成就信息"""
	print(print_summary())
	print("\n详细成就列表:")
	for achievement in achievements.values():
		print("  %s" % achievement.get_display_text())
