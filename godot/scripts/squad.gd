class_name Squad
extends RefCounted

## 组队状态
enum SquadStatus {
	ACTIVE,      # 活跃
	WAITING,     # 等待
	DISBANDED,   # 已解散
	IN_GAME      # 游戏中
}

## 组队基础信息
var squad_id: String                   # 组队 ID
var squad_name: String                 # 组队名称
var leader_id: String                  # 队长 ID
var leader_name: String                # 队长名称
var team_id: String = ""               # 所属战队 ID (可选)

## 成员管理
var members: Dictionary = {}            # {player_id: member_info}
var member_count: int = 0              # 成员数量
var max_members: int = 4               # 最大成员数

## 状态和时间
var status: SquadStatus = SquadStatus.ACTIVE
var created_at: int = 0
var disbanded_at: int = 0
var games_played: int = 0
var wins: int = 0


## 初始化
func _init(p_id: String, p_name: String, p_leader_id: String, p_leader_name: String) -> void:
	"""初始化组队"""
	squad_id = p_id
	squad_name = p_name
	leader_id = p_leader_id
	leader_name = p_leader_name
	created_at = int(Time.get_ticks_msec() / 1000)

	# 添加队长
	add_member(leader_id, leader_name)


## 成员操作

func add_member(player_id: String, player_name: String) -> bool:
	"""添加成员"""
	if members.has(player_id):
		return false

	if member_count >= max_members:
		return false

	members[player_id] = {
		"player_id": player_id,
		"player_name": player_name,
		"joined_at": int(Time.get_ticks_msec() / 1000)
	}
	member_count = members.size()
	return true


func remove_member(player_id: String) -> bool:
	"""移除成员"""
	if not members.has(player_id):
		return false

	members.erase(player_id)
	member_count = members.size()

	# 如果队长离开，解散
	if player_id == leader_id:
		status = SquadStatus.DISBANDED
		disbanded_at = int(Time.get_ticks_msec() / 1000)

	return true


func get_all_members() -> Array:
	"""获取所有成员"""
	return members.values()


func has_member(player_id: String) -> bool:
	"""检查是否有该成员"""
	return members.has(player_id)


func is_full() -> bool:
	"""检查是否已满"""
	return member_count >= max_members


## 统计

func get_win_rate() -> float:
	"""获取胜率"""
	if games_played == 0:
		return 0.0
	return float(wins) / float(games_played)


func record_game_result(won: bool) -> void:
	"""记录游戏结果"""
	games_played += 1
	if won:
		wins += 1


## 显示方法

func get_display_text() -> String:
	"""获取显示文本"""
	var status_text = _get_status_text()
	return "%s (%s) - %d/%d 成员" % [squad_name, status_text, member_count, max_members]


func _get_status_text() -> String:
	"""获取状态文本"""
	match status:
		SquadStatus.ACTIVE:
			return "活跃"
		SquadStatus.WAITING:
			return "等待"
		SquadStatus.IN_GAME:
			return "游戏中"
		SquadStatus.DISBANDED:
			return "已解散"
		_:
			return "未知"


## 序列化

func to_dict() -> Dictionary:
	"""转换为字典"""
	var members_data = []
	for member in members.values():
		members_data.append(member)

	return {
		"squad_id": squad_id,
		"squad_name": squad_name,
		"leader_id": leader_id,
		"leader_name": leader_name,
		"team_id": team_id,
		"members": members_data,
		"status": status,
		"created_at": created_at,
		"disbanded_at": disbanded_at,
		"games_played": games_played,
		"wins": wins
	}


func from_dict(data: Dictionary) -> void:
	"""从字典恢复"""
	if data.has("squad_id"):
		squad_id = data["squad_id"]
	if data.has("squad_name"):
		squad_name = data["squad_name"]
	if data.has("leader_id"):
		leader_id = data["leader_id"]
	if data.has("leader_name"):
		leader_name = data["leader_name"]
	if data.has("team_id"):
		team_id = data["team_id"]
	if data.has("status"):
		status = data["status"]
	if data.has("created_at"):
		created_at = data["created_at"]
	if data.has("disbanded_at"):
		disbanded_at = data["disbanded_at"]
	if data.has("games_played"):
		games_played = data["games_played"]
	if data.has("wins"):
		wins = data["wins"]

	# 加载成员
	members.clear()
	if data.has("members"):
		for member_data in data["members"]:
			members[member_data["player_id"]] = member_data

	member_count = members.size()
