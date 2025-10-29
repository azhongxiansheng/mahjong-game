## 成就系统 - 单个成就类
## 表示游戏中的一个成就
## 包含成就的基本信息、进度跟踪、解锁管理

class_name Achievement
extends RefCounted

# ============ 成就基础信息 ============
var id: String                 # 成就ID (如 "first_win")
var name: String               # 显示名称
var description: String        # 成就描述
var icon: String              # 图标路径 (可选)
var category: String          # 分类 (progress/oneshot/hidden/seasonal)
var rarity: String            # 稀有度 (common/uncommon/rare/epic/legendary)

# ============ 成就进度数据 ============
var is_unlocked: bool = false
var progress: int = 0          # 当前进度
var max_progress: int = 1      # 目标进度
var unlock_date: int = 0       # 解锁时间戳
var reward_points: int = 100   # 奖励成就点数
var reward_coin: int = 0       # 奖励金币
var reward_item: String = ""   # 奖励物品 (可选)

# ============ 成就条件数据 ============
var condition: String          # 条件描述 (如 "win_count")
var condition_value: int = 0   # 条件值

# ============ 信号 ============
signal progress_changed(new_progress: int)
signal unlocked()

# ============ 构造函数 ============
func _init(p_id: String, p_name: String) -> void:
	"""初始化成就

	参数:
		p_id: 成就ID
		p_name: 成就名称
	"""
	id = p_id
	name = p_name
	category = "oneshot"
	rarity = "common"


# ============ 成就进度管理 ============

func update_progress(amount: int) -> bool:
	"""更新成就进度

	参数:
		amount: 增加的进度数值

	返回:
		bool: 是否已解锁
	"""
	if is_unlocked:
		return false

	progress = min(progress + amount, max_progress)
	progress_changed.emit(progress)

	if progress >= max_progress:
		unlock()
		return true

	return false


func set_progress(new_progress: int) -> bool:
	"""直接设置成就进度

	参数:
		new_progress: 新的进度值

	返回:
		bool: 是否已解锁
	"""
	if is_unlocked:
		return false

	progress = min(new_progress, max_progress)
	progress_changed.emit(progress)

	if progress >= max_progress:
		unlock()
		return true

	return false


func unlock() -> void:
	"""解锁成就"""
	if not is_unlocked:
		is_unlocked = true
		unlock_date = int(Time.get_ticks_msec() / 1000)
		unlocked.emit()
		print("[Achievement] 成就已解锁: %s (%s)" % [name, id])


# ============ 成就信息查询 ============

func get_display_text() -> String:
	"""获取显示文本"""
	var status = "✓" if is_unlocked else "○"
	var progress_text = ""

	if max_progress > 1:
		progress_text = " [%d/%d]" % [progress, max_progress]

	return "[%s] %s%s - %s" % [status, name, progress_text, description]


func get_progress_percent() -> float:
	"""获取进度百分比 (0-1)"""
	if max_progress == 0:
		return 0.0
	return float(progress) / float(max_progress)


func get_tier_emoji() -> String:
	"""获取稀有度表情符号"""
	match rarity:
		"common":
			return "⚪"
		"uncommon":
			return "🟢"
		"rare":
			return "🔵"
		"epic":
			return "🟣"
		"legendary":
			return "🟡"
		_:
			return "⚪"


func get_category_name() -> String:
	"""获取分类名称"""
	match category:
		"progress":
			return "进度"
		"oneshot":
			return "一次性"
		"hidden":
			return "隐藏"
		"seasonal":
			return "季节"
		_:
			return "其他"


func get_stats() -> Dictionary:
	"""获取成就统计信息"""
	return {
		"id": id,
		"name": name,
		"category": category,
		"rarity": rarity,
		"is_unlocked": is_unlocked,
		"progress": progress,
		"max_progress": max_progress,
		"progress_percent": get_progress_percent(),
		"reward_points": reward_points,
		"reward_coin": reward_coin,
		"unlock_date": unlock_date
	}


# ============ 序列化 ============

func to_dict() -> Dictionary:
	"""转换为字典 (用于JSON序列化)"""
	return {
		"id": id,
		"name": name,
		"description": description,
		"category": category,
		"rarity": rarity,
		"is_unlocked": is_unlocked,
		"progress": progress,
		"max_progress": max_progress,
		"unlock_date": unlock_date,
		"reward_points": reward_points,
		"reward_coin": reward_coin
	}


func from_dict(data: Dictionary) -> void:
	"""从字典恢复 (用于JSON反序列化)"""
	if data.has("name"):
		name = data["name"]
	if data.has("description"):
		description = data["description"]
	if data.has("category"):
		category = data["category"]
	if data.has("rarity"):
		rarity = data["rarity"]
	if data.has("is_unlocked"):
		is_unlocked = data["is_unlocked"]
	if data.has("progress"):
		progress = data["progress"]
	if data.has("max_progress"):
		max_progress = data["max_progress"]
	if data.has("unlock_date"):
		unlock_date = data["unlock_date"]
	if data.has("reward_points"):
		reward_points = data["reward_points"]
	if data.has("reward_coin"):
		reward_coin = data["reward_coin"]
