class_name Season
extends RefCounted

## 赛季状态
enum SeasonStatus {
	UPCOMING,    # 即将开始
	ACTIVE,      # 活跃中
	ENDED,       # 已结束
	ARCHIVED     # 已归档
}

## 赛季基础信息
var season_id: int = 0                 # 赛季 ID
var season_number: int = 1             # 赛季号
var season_name: String = ""           # 赛季名称
var description: String = ""           # 赛季描述

## 赛季时间
var start_date: int = 0                # 开始时间
var end_date: int = 0                  # 结束时间
var created_at: int = 0                # 创建时间

## 赛季状态
var status: SeasonStatus = SeasonStatus.UPCOMING
var is_rewards_distributed: bool = false  # 奖励是否已发放

## 赛季数据
var total_players: int = 0             # 参加人数
var total_games: int = 0               # 比赛场数
var rankings: Dictionary = {}           # {player_id: ranking_info}

## 奖励信息
var rank_rewards: Dictionary = {}      # {rank: reward_amount}


## 初始化
func _init(p_number: int, p_name: String) -> void:
	"""初始化赛季"""
	season_number = p_number
	season_name = p_name
	season_id = p_number
	created_at = int(Time.get_ticks_msec() / 1000)

	# 初始化排名奖励
	_init_rank_rewards()


## 排名奖励初始化

func _init_rank_rewards() -> void:
	"""初始化排名奖励"""
	rank_rewards.clear()

	# 金字塔式奖励
	rank_rewards[1] = 1000    # 第一名 1000 钻石
	rank_rewards[2] = 500     # 第二名 500 钻石
	rank_rewards[3] = 300     # 第三名 300 钻石
	rank_rewards[4] = 200
	rank_rewards[5] = 100

	for i in range(6, 11):
		rank_rewards[i] = 50

	for i in range(11, 51):
		rank_rewards[i] = 10


## 赛季管理

func start_season() -> void:
	"""开始赛季"""
	start_date = int(Time.get_ticks_msec() / 1000)
	end_date = start_date + (30 * 86400)  # 30 天后结束
	status = SeasonStatus.ACTIVE
	print("[Season] Season %d started" % season_number)


func end_season() -> void:
	"""结束赛季"""
	end_date = int(Time.get_ticks_msec() / 1000)
	status = SeasonStatus.ENDED
	print("[Season] Season %d ended" % season_number)


func archive_season() -> void:
	"""归档赛季"""
	status = SeasonStatus.ARCHIVED
	print("[Season] Season %d archived" % season_number)


## 排名管理

func add_player_ranking(player_id: String, player_name: String, points: int = 0) -> bool:
	"""添加玩家排名"""
	if rankings.has(player_id):
		return false

	rankings[player_id] = {
		"player_id": player_id,
		"player_name": player_name,
		"points": points,
		"rank": 0,
		"reward_given": false
	}
	total_players += 1
	return true


func update_player_points(player_id: String, points: int) -> bool:
	"""更新玩家积分"""
	if not rankings.has(player_id):
		return false

	rankings[player_id]["points"] = points
	_recalculate_rankings()
	return true


func add_game(winner_id: String, loser_id: String) -> void:
	"""记录一场比赛"""
	total_games += 1

	# 更新获胜者积分
	if rankings.has(winner_id):
		rankings[winner_id]["points"] += 10

	# 更新失败者积分
	if rankings.has(loser_id):
		rankings[loser_id]["points"] = max(0, rankings[loser_id]["points"] - 5)

	_recalculate_rankings()


func _recalculate_rankings() -> void:
	"""重新计算排名"""
	var ranked_players = rankings.values()
	ranked_players.sort_custom(func(a, b): return a["points"] > b["points"])

	for i in range(ranked_players.size()):
		ranked_players[i]["rank"] = i + 1


## 奖励系统

func get_reward_for_rank(rank: int) -> int:
	"""获取排名奖励"""
	if rank_rewards.has(rank):
		return rank_rewards[rank]
	return 0  # 排名 50 以后没有奖励


func distribute_rewards() -> Dictionary:
	"""发放奖励"""
	var rewards_given = {}

	for player_id in rankings.keys():
		var player_info = rankings[player_id]
		var rank = player_info["rank"]
		var reward = get_reward_for_rank(rank)

		if reward > 0 and not player_info["reward_given"]:
			player_info["reward_given"] = true
			rewards_given[player_id] = reward

	is_rewards_distributed = true
	print("[Season] Rewards distributed for season %d" % season_number)
	return rewards_given


## 查询方法

func get_player_rank(player_id: String) -> int:
	"""获取玩家排名"""
	if not rankings.has(player_id):
		return -1
	return rankings[player_id]["rank"]


func get_player_points(player_id: String) -> int:
	"""获取玩家积分"""
	if not rankings.has(player_id):
		return 0
	return rankings[player_id]["points"]


func get_top_players(limit: int = 10) -> Array:
	"""获取排名前列玩家"""
	var ranked = rankings.values()
	ranked.sort_custom(func(a, b): return a["rank"] < b["rank"])
	return ranked.slice(0, min(limit, ranked.size()))


func get_season_duration() -> int:
	"""获取赛季时长 (秒)"""
	if status == SeasonStatus.UPCOMING:
		return 0

	var current = int(Time.get_ticks_msec() / 1000)
	if status == SeasonStatus.ACTIVE:
		return current - start_date
	else:
		return end_date - start_date


## 显示方法

func get_display_text() -> String:
	"""获取显示文本"""
	var status_text = _get_status_text()
	return "第 %d 赛季: %s (%s) - 参加者:%d | 比赛:%d" % [
		season_number, season_name, status_text, total_players, total_games
	]


func _get_status_text() -> String:
	"""获取状态文本"""
	match status:
		SeasonStatus.UPCOMING:
			return "即将开始"
		SeasonStatus.ACTIVE:
			return "进行中"
		SeasonStatus.ENDED:
			return "已结束"
		SeasonStatus.ARCHIVED:
			return "已归档"
		_:
			return "未知"


func get_summary() -> String:
	"""获取摘要"""
	var duration = get_season_duration()
	var duration_text = "%d 天 %d 小时" % [duration / 86400, (duration % 86400) / 3600]

	return """
	赛季: %d - %s
	状态: %s
	时长: %s
	参加者: %d
	比赛: %d
	奖励已发放: %s
	""" % [
		season_number, season_name,
		_get_status_text(),
		duration_text if status != SeasonStatus.UPCOMING else "未开始",
		total_players,
		total_games,
		"是" if is_rewards_distributed else "否"
	]


## 序列化

func to_dict() -> Dictionary:
	"""转换为字典"""
	var rankings_data = []
	for ranking in rankings.values():
		rankings_data.append(ranking)

	return {
		"season_id": season_id,
		"season_number": season_number,
		"season_name": season_name,
		"description": description,
		"status": status,
		"start_date": start_date,
		"end_date": end_date,
		"created_at": created_at,
		"total_players": total_players,
		"total_games": total_games,
		"rankings": rankings_data,
		"is_rewards_distributed": is_rewards_distributed,
		"rank_rewards": rank_rewards
	}


func from_dict(data: Dictionary) -> void:
	"""从字典恢复"""
	if data.has("season_id"):
		season_id = data["season_id"]
	if data.has("season_number"):
		season_number = data["season_number"]
	if data.has("season_name"):
		season_name = data["season_name"]
	if data.has("description"):
		description = data["description"]
	if data.has("status"):
		status = data["status"]
	if data.has("start_date"):
		start_date = data["start_date"]
	if data.has("end_date"):
		end_date = data["end_date"]
	if data.has("created_at"):
		created_at = data["created_at"]
	if data.has("total_players"):
		total_players = data["total_players"]
	if data.has("total_games"):
		total_games = data["total_games"]
	if data.has("is_rewards_distributed"):
		is_rewards_distributed = data["is_rewards_distributed"]

	# 加载排名
	rankings.clear()
	if data.has("rankings"):
		for ranking_data in data["rankings"]:
			rankings[ranking_data["player_id"]] = ranking_data

	# 加载奖励
	if data.has("rank_rewards"):
		rank_rewards = data["rank_rewards"].duplicate()
