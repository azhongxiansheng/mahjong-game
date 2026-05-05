## 成就追踪系统 - 事件监听和自动触发
## 监听游戏事件，自动检测和更新成就

class_name AchievementTracker
extends Node

# ============ 系统引用 ============
var achievement_system: AchievementSystem
var game_stats: Dictionary = {}

# ============ 游戏统计 ============
var current_win_streak: int = 0          # 当前连胜数
var total_wins: int = 0                  # 总胜利数
var total_losses: int = 0                # 总失败数
var highest_score: int = 0               # 最高单局分数
var total_games: int = 0                 # 总游戏数
var total_play_time: int = 0             # 总游戏时间（秒）
var max_win_streak: int = 0              # 最高连胜数

# ============ 缓存数据 ============
var achievement_unlock_history: Array = [] # 解锁历史


# ============ 初始化 ============

func _ready() -> void:
	"""初始化追踪器"""
	print("[AchievementTracker] 追踪器初始化完成")


# ============ 系统配置 ============

func set_achievement_system(system: AchievementSystem) -> void:
	"""设置关联的成就系统

	参数:
		system: AchievementSystem 实例
	"""
	achievement_system = system
	if achievement_system:
		achievement_system.achievement_unlocked.connect(_on_achievement_unlocked)
		print("[AchievementTracker] 已连接到成就系统")


# ============ 游戏事件处理 ============

func on_game_started() -> void:
	"""游戏开始事件"""
	print("[AchievementTracker] 游戏开始")


func on_game_completed(result: Dictionary) -> void:
	"""游戏完成事件

	参数:
		result: 包含游戏结果的字典
		{
			"is_victory": bool,
			"score": int,
			"players": Array,
			"rank": int (玩家排名),
			"play_time": int (游戏时长，秒)
		}
	"""
	if result == null:
		return

	var is_victory = result.get("is_victory", false)
	var score = result.get("score", 0)
	var play_time = result.get("play_time", 0)
	var rank = result.get("rank", 0)

	total_games += 1
	total_play_time += play_time

	if is_victory:
		total_wins += 1
		current_win_streak += 1
		max_win_streak = max(max_win_streak, current_win_streak)
		_check_win_achievements()
	else:
		total_losses += 1
		current_win_streak = 0
		_check_loss_achievements()

	if score > highest_score:
		highest_score = score
		_check_score_achievements()

	print("[AchievementTracker] 游戏完成: 胜利=%s, 分数=%d, 连胜=%d" % [is_victory, score, current_win_streak])


func on_player_level_up(player_id: String, new_level: int) -> void:
	"""玩家升级事件"""
	if achievement_system:
		achievement_system.update_achievement_progress("level_10", 1)


# ============ 成就检测 ============

func _check_win_achievements() -> void:
	"""检查胜利相关的成就"""
	if achievement_system == null:
		return

	# 首次胜利
	if total_wins == 1:
		achievement_system.unlock_achievement("first_win")

	# 胜利数里程碑
	if total_wins == 10:
		achievement_system.unlock_achievement("10_wins")
	if total_wins == 50:
		achievement_system.unlock_achievement("50_wins")
	if total_wins == 100:
		achievement_system.unlock_achievement("100_wins")
	if total_wins == 500:
		achievement_system.unlock_achievement("500_wins")
	if total_wins == 1000:
		achievement_system.unlock_achievement("1000_wins")

	# 连胜成就
	if current_win_streak == 3:
		achievement_system.unlock_achievement("win_streak_3")
	if current_win_streak == 5:
		achievement_system.unlock_achievement("win_streak_5")
	if current_win_streak == 10:
		achievement_system.unlock_achievement("win_streak_10")
	if current_win_streak == 20:
		achievement_system.unlock_achievement("win_streak_20")


func _check_loss_achievements() -> void:
	"""检查失败相关的成就"""
	if achievement_system == null:
		return

	# 这里可以添加失败相关的成就
	# 例如: 经历过失败、不怕失败等


func _check_score_achievements() -> void:
	"""检查分数相关的成就"""
	if achievement_system == null:
		return

	# 分数里程碑
	if highest_score >= 1000:
		achievement_system.unlock_achievement("score_1000")
	if highest_score >= 5000:
		achievement_system.unlock_achievement("score_5000")
	if highest_score >= 10000:
		achievement_system.unlock_achievement("score_10000")
	if highest_score >= 20000:
		achievement_system.unlock_achievement("score_20000")
	if highest_score >= 50000:
		achievement_system.unlock_achievement("score_50000")


# ============ 手动触发 ============

func unlock_achievement(achievement_id: String) -> void:
	"""手动解锁成就

	参数:
		achievement_id: 成就ID
	"""
	if achievement_system:
		achievement_system.unlock_achievement(achievement_id)


func update_achievement(achievement_id: String, amount: int) -> void:
	"""手动更新成就进度

	参数:
		achievement_id: 成就ID
		amount: 增加的进度数值
	"""
	if achievement_system:
		achievement_system.update_achievement_progress(achievement_id, amount)


# ============ 统计信息 ============

func get_stats() -> Dictionary:
	"""获取游戏统计数据"""
	var win_rate = 0.0
	if total_games > 0:
		win_rate = float(total_wins) / float(total_games)

	return {
		"total_wins": total_wins,
		"total_losses": total_losses,
		"total_games": total_games,
		"win_rate": win_rate,
		"highest_score": highest_score,
		"current_streak": current_win_streak,
		"max_streak": max_win_streak,
		"total_play_time": total_play_time
	}


func get_summary() -> String:
	"""获取统计摘要"""
	var stats = get_stats()
	var summary = "=== 游戏统计摘要 ===\n"
	summary += "总游戏数: %d\n" % stats["total_games"]
	summary += "胜利: %d, 失败: %d\n" % [stats["total_wins"], stats["total_losses"]]
	summary += "胜率: %.1f%%\n" % (stats["win_rate"] * 100)
	summary += "最高分: %d\n" % stats["highest_score"]
	summary += "当前连胜: %d\n" % stats["current_streak"]
	summary += "最高连胜: %d\n" % stats["max_streak"]
	summary += "总游戏时间: %d 分钟\n" % (stats["total_play_time"] / 60)

	return summary


# ============ 事件处理 ============

func _on_achievement_unlocked(achievement: Achievement) -> void:
	"""成就解锁事件处理"""
	achievement_unlock_history.append({
		"id": achievement.id,
		"name": achievement.name,
		"timestamp": Time.get_ticks_msec() / 1000.0,
		"reward_points": achievement.reward_points
	})

	print("[AchievementTracker] 成就已解锁: %s" % achievement.name)


# ============ 调试 ============

func print_stats() -> void:
	"""打印统计信息"""
	print(get_summary())


func print_unlock_history() -> void:
	"""打印解锁历史"""
	print("\n=== 成就解锁历史 ===")
	for unlock_info in achievement_unlock_history:
		print("  %s: %s (获得 %d 点)" % [
			unlock_info["name"],
			unlock_info["id"],
			unlock_info["reward_points"]
		])
