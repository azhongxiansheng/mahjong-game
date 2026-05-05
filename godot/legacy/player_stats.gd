class_name PlayerStats

# 玩家统计管理类
# 记录玩家的游戏统计数据和排名信息

var user_id: String           # 用户ID
var total_games: int          # 总游戏数
var wins: int                 # 胜利次数
var losses: int               # 失败次数
var draws: int                # 平局次数
var total_fan: int            # 总番数
var max_fan: int              # 最高单局番数
var average_fan: float        # 平均番数
var win_rate: float           # 胜率（百分比）
var ranking: int              # 排名
var rating: float             # Elo评级分数
var created_at: int           # 统计创建时间

func _init(p_user_id: String = "") -> void:
	"""初始化玩家统计"""
	user_id = p_user_id
	total_games = 0
	wins = 0
	losses = 0
	draws = 0
	total_fan = 0
	max_fan = 0
	average_fan = 0.0
	win_rate = 0.0
	ranking = 0
	rating = 1600.0  # 初始Elo评级
	created_at = Time.get_ticks_msec()

func record_game(result: String, fan: int = 0) -> void:
	"""记录一场游戏"""
	total_games += 1
	total_fan += fan
	
	if fan > max_fan:
		max_fan = fan
	
	match result:
		"win":
			wins += 1
		"loss":
			losses += 1
		"draw":
			draws += 1
	
	_update_stats()

func _update_stats() -> void:
	"""更新计算的统计数据"""
	if total_games > 0:
		# 计算胜率
		win_rate = float(wins) / float(total_games) * 100.0
		
		# 计算平均番数
		average_fan = float(total_fan) / float(total_games)
	else:
		win_rate = 0.0
		average_fan = 0.0

func update_rating(opponent_rating: float, is_win: bool) -> void:
	"""根据Elo系统更新评级"""
	var K = 32  # 基础系数
	var expected_score = 1.0 / (1.0 + pow(10.0, (opponent_rating - rating) / 400.0))
	var actual_score = 1.0 if is_win else 0.0
	
	rating = rating + K * (actual_score - expected_score)
	print("PlayerStats: %s 的评级已更新为 %.2f" % [user_id, rating])

func get_stats_info() -> Dictionary:
	"""获取统计信息字典"""
	return {
		"user_id": user_id,
		"total_games": total_games,
		"wins": wins,
		"losses": losses,
		"draws": draws,
		"win_rate": win_rate,
		"total_fan": total_fan,
		"average_fan": average_fan,
		"max_fan": max_fan,
		"ranking": ranking,
		"rating": rating
	}

func get_summary_string() -> String:
	"""获取统计摘要字符串"""
	return "玩家%s: %d/%d胜 | 胜率%.1f%% | 平均%.1f番 | 评级%.0f" % [
		user_id,
		wins,
		total_games,
		win_rate,
		average_fan,
		rating
	]

func to_json() -> String:
	"""转换为JSON字符串"""
	return JSON.stringify(get_stats_info())

static func from_dict(data: Dictionary) -> PlayerStats:
	"""从字典创建统计对象"""
	var stats = PlayerStats.new(data.get("user_id", ""))
	stats.total_games = data.get("total_games", 0)
	stats.wins = data.get("wins", 0)
	stats.losses = data.get("losses", 0)
	stats.draws = data.get("draws", 0)
	stats.total_fan = data.get("total_fan", 0)
	stats.max_fan = data.get("max_fan", 0)
	stats.average_fan = data.get("average_fan", 0.0)
	stats.win_rate = data.get("win_rate", 0.0)
	stats.ranking = data.get("ranking", 0)
	stats.rating = data.get("rating", 1600.0)
	stats.created_at = data.get("created_at", stats.created_at)
	return stats
