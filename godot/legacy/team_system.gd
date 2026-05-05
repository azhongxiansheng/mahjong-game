class_name TeamSystem
extends Node

## 战队集合
var teams: Dictionary = {}              # {team_id: Team}
var player_teams: Dictionary = {}       # {player_id: [team_ids]}
var team_invitations: Dictionary = {}   # {player_id: [team_ids]}

## 统计数据
var total_teams: int = 0
var total_players: int = 0

## 信号
signal team_created(team: Team)
signal team_disbanded(team_id: String)
signal member_joined(team_id: String, player_id: String)
signal member_left(team_id: String, player_id: String)
signal team_updated(team_id: String)
signal invitation_sent(team_id: String, player_id: String)
signal invitation_accepted(team_id: String, player_id: String)


## 初始化
func _ready() -> void:
	"""初始化战队系统"""
	print("[TeamSystem] Initialized successfully")


## 战队创建和删除

func create_team(team_id: String, team_name: String, leader_id: String, leader_name: String) -> Team:
	"""创建战队"""
	if teams.has(team_id):
		push_error("[TeamSystem] Team already exists: %s" % team_id)
		return null

	var team = Team.new(team_id, team_name, leader_id, leader_name)
	team.add_member(leader_id, leader_name, Team.TeamRole.LEADER)

	teams[team_id] = team
	total_teams = teams.size()

	# 添加到玩家战队列表
	if not player_teams.has(leader_id):
		player_teams[leader_id] = []
	if not player_teams[leader_id].has(team_id):
		player_teams[leader_id].append(team_id)

	team_created.emit(team)
	print("[TeamSystem] Team created: %s" % team_name)
	return team


func disband_team(team_id: String) -> bool:
	"""解散战队"""
	if not teams.has(team_id):
		return false

	var team = teams[team_id]

	# 从所有成员的列表中移除
	for member in team.get_all_members():
		if player_teams.has(member.player_id):
			player_teams[member.player_id].erase(team_id)

	teams.erase(team_id)
	total_teams = teams.size()

	team_disbanded.emit(team_id)
	print("[TeamSystem] Team disbanded: %s" % team.team_name)
	return true


## 战队查询

func get_team(team_id: String) -> Team:
	"""获取战队"""
	return teams.get(team_id, null)


func get_all_teams() -> Array:
	"""获取所有战队"""
	return teams.values()


func get_player_teams(player_id: String) -> Array:
	"""获取玩家所在的所有战队"""
	var player_team_ids = player_teams.get(player_id, [])
	var result = []
	for team_id in player_team_ids:
		if teams.has(team_id):
			result.append(teams[team_id])
	return result


func get_team_count() -> int:
	"""获取战队总数"""
	return teams.size()


func has_team(team_id: String) -> bool:
	"""检查战队是否存在"""
	return teams.has(team_id)


## 成员管理

func add_member_to_team(team_id: String, player_id: String, player_name: String, role: int = Team.TeamRole.MEMBER) -> bool:
	"""添加成员到战队"""
	if not teams.has(team_id):
		return false

	var team = teams[team_id]
	if not team.add_member(player_id, player_name, role):
		return false

	# 添加到玩家战队列表
	if not player_teams.has(player_id):
		player_teams[player_id] = []
	if not player_teams[player_id].has(team_id):
		player_teams[player_id].append(team_id)

	member_joined.emit(team_id, player_id)
	team_updated.emit(team_id)
	print("[TeamSystem] Member joined team: %s -> %s" % [player_name, team.team_name])
	return true


func remove_member_from_team(team_id: String, player_id: String) -> bool:
	"""从战队中移除成员"""
	if not teams.has(team_id):
		return false

	var team = teams[team_id]
	if not team.remove_member(player_id):
		return false

	# 从玩家战队列表中移除
	if player_teams.has(player_id):
		player_teams[player_id].erase(team_id)

	member_left.emit(team_id, player_id)
	team_updated.emit(team_id)

	# 如果队长离开，自动解散
	if player_id == team.leader_id:
		disband_team(team_id)

	print("[TeamSystem] Member left team: %s" % player_id)
	return true


func get_team_members(team_id: String) -> Array:
	"""获取战队成员"""
	if not teams.has(team_id):
		return []
	return teams[team_id].get_all_members()


func get_member_count(team_id: String) -> int:
	"""获取战队成员数"""
	if not teams.has(team_id):
		return 0
	return teams[team_id].member_count


## 邀请系统

func send_invitation(team_id: String, player_id: String) -> bool:
	"""发送加入邀请"""
	if not teams.has(team_id):
		return false

	if not team_invitations.has(player_id):
		team_invitations[player_id] = []

	if not team_invitations[player_id].has(team_id):
		team_invitations[player_id].append(team_id)

	invitation_sent.emit(team_id, player_id)
	print("[TeamSystem] Invitation sent: team %s -> player %s" % [team_id, player_id])
	return true


func accept_invitation(team_id: String, player_id: String, player_name: String) -> bool:
	"""接受邀请加入战队"""
	if not team_invitations.has(player_id):
		return false

	if not team_invitations[player_id].has(team_id):
		return false

	# 添加成员
	var result = add_member_to_team(team_id, player_id, player_name)

	# 移除邀请
	team_invitations[player_id].erase(team_id)

	if result:
		invitation_accepted.emit(team_id, player_id)

	return result


func reject_invitation(team_id: String, player_id: String) -> bool:
	"""拒绝邀请"""
	if not team_invitations.has(player_id):
		return false

	team_invitations[player_id].erase(team_id)
	return true


func get_pending_invitations(player_id: String) -> Array:
	"""获取待确认邀请"""
	if not team_invitations.has(player_id):
		return []

	var result = []
	for team_id in team_invitations[player_id]:
		if teams.has(team_id):
			result.append(teams[team_id])
	return result


## 排行榜

func get_top_teams(limit: int = 10) -> Array:
	"""获取评分最高的战队"""
	var all_teams = teams.values()
	all_teams.sort_custom(func(a, b): return a.rating > b.rating)
	return all_teams.slice(0, min(limit, all_teams.size()))


func get_teams_by_level(min_level: int, max_level: int = 999) -> Array:
	"""按等级范围获取战队"""
	var result = []
	for team in teams.values():
		if team.level >= min_level and team.level <= max_level:
			result.append(team)
	return result


func get_teams_by_size(min_members: int, max_members: int = 999) -> Array:
	"""按成员数范围获取战队"""
	var result = []
	for team in teams.values():
		if team.member_count >= min_members and team.member_count <= max_members:
			result.append(team)
	return result


## 统计

func get_statistics() -> Dictionary:
	"""获取统计信息"""
	var total_members = 0
	var max_team_size = 0
	var total_fund = 0

	for team in teams.values():
		total_members += team.member_count
		max_team_size = max(max_team_size, team.member_count)
		total_fund += team.team_fund

	var avg_team_size = 0
	if teams.size() > 0:
		avg_team_size = total_members / teams.size()

	return {
		"total_teams": teams.size(),
		"total_members": total_members,
		"avg_team_size": avg_team_size,
		"max_team_size": max_team_size,
		"total_fund": total_fund,
		"pending_invitations": team_invitations.size()
	}


func print_summary() -> void:
	"""打印摘要"""
	print("\n=== 战队系统摘要 ===")
	print("总战队数: %d" % teams.size())

	var stats = get_statistics()
	print("总成员数: %d" % stats["total_members"])
	print("平均队伍大小: %d" % stats["avg_team_size"])
	print("最大队伍大小: %d" % stats["max_team_size"])
	print("总基金: %d" % stats["total_fund"])
	print("待处理邀请: %d" % stats["pending_invitations"])
	print("==================\n")


## 导出和导入

func to_json(limit: int = 100) -> String:
	"""导出为 JSON"""
	var data = {
		"teams": [],
		"timestamp": Time.get_ticks_msec()
	}

	for team in teams.values().slice(0, limit):
		data["teams"].append(team.to_dict())

	return JSON.stringify(data)


func from_json(json_string: String) -> bool:
	"""从 JSON 导入"""
	var json = JSON.new()
	var error = json.parse(json_string)

	if error:
		push_error("[TeamSystem] JSON parse error")
		return false

	var data = json.data

	if not data.has("teams"):
		return false

	# 清空现有战队
	teams.clear()
	player_teams.clear()

	# 加载战队
	for team_data in data["teams"]:
		var team = Team.new(team_data["team_id"], team_data["team_name"],
		                     team_data["leader_id"], team_data["leader_name"])
		team.from_dict(team_data)
		teams[team.team_id] = team

		# 建立玩家索引
		for member in team.get_all_members():
			if not player_teams.has(member.player_id):
				player_teams[member.player_id] = []
			if not player_teams[member.player_id].has(team.team_id):
				player_teams[member.player_id].append(team.team_id)

	total_teams = teams.size()
	print("[TeamSystem] Loaded from JSON: %d teams" % total_teams)
	return true
