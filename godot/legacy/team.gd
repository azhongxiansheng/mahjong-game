class_name Team
extends RefCounted

## 战队角色枚举
enum TeamRole {
	LEADER,        # 队长
	OFFICER,       # 官员
	MEMBER         # 成员
}

## 战队基础信息
var team_id: String                    # 战队 ID
var team_name: String                  # 战队名称
var leader_id: String                  # 队长 ID
var leader_name: String                # 队长名称
var description: String = ""           # 战队描述
var logo_url: String = ""              # Logo URL

## 战队数据
var level: int = 1                     # 战队等级
var experience: int = 0                # 战队经验
var wins: int = 0                      # 胜场数
var losses: int = 0                    # 负场数
var rating: int = 1000                 # 战队评分

## 成员管理
var members: Dictionary = {}            # {player_id: TeamMember}
var member_count: int = 0              # 成员数量
var max_members: int = 50              # 最大成员数

## 财务
var team_fund: int = 0                 # 战队基金
var total_contributed: int = 0         # 总贡献

## 时间戳
var founded_at: int = 0                # 创建时间
var updated_at: int = 0                # 更新时间


## 初始化
func _init(p_id: String, p_name: String, p_leader_id: String, p_leader_name: String) -> void:
	"""初始化战队"""
	team_id = p_id
	team_name = p_name
	leader_id = p_leader_id
	leader_name = p_leader_name
	founded_at = int(Time.get_ticks_msec() / 1000)
	updated_at = founded_at


## TeamMember 内部类
class TeamMember:
	var player_id: String
	var player_name: String
	var role: TeamRole = TeamRole.MEMBER
	var joined_at: int = 0
	var contribution: int = 0
	var level: int = 1
	var rating: int = 1000

	func _init(p_id: String, p_name: String) -> void:
		player_id = p_id
		player_name = p_name
		joined_at = int(Time.get_ticks_msec() / 1000)

	func get_role_string() -> String:
		match role:
			TeamRole.LEADER:
				return "队长"
			TeamRole.OFFICER:
				return "官员"
			TeamRole.MEMBER:
				return "成员"
			_:
				return "未知"


## 公共方法

func add_member(player_id: String, player_name: String, role: TeamRole = TeamRole.MEMBER) -> bool:
	"""添加成员"""
	if members.has(player_id):
		return false

	if member_count >= max_members:
		push_warning("[Team] Member limit reached")
		return false

	var member = TeamMember.new(player_id, player_name)
	member.role = role
	members[player_id] = member
	member_count = members.size()
	updated_at = int(Time.get_ticks_msec() / 1000)

	print("[Team] Member added: %s" % player_name)
	return true


func remove_member(player_id: String) -> bool:
	"""移除成员"""
	if not members.has(player_id):
		return false

	members.erase(player_id)
	member_count = members.size()
	updated_at = int(Time.get_ticks_msec() / 1000)

	print("[Team] Member removed: %s" % player_id)
	return true


func get_member(player_id: String) -> TeamMember:
	"""获取成员"""
	return members.get(player_id, null)


func get_all_members() -> Array:
	"""获取所有成员"""
	return members.values()


func has_member(player_id: String) -> bool:
	"""检查是否有该成员"""
	return members.has(player_id)


func set_member_role(player_id: String, new_role: TeamRole) -> bool:
	"""设置成员角色"""
	if not members.has(player_id):
		return false

	# 队长不能降级
	if members[player_id].role == TeamRole.LEADER and new_role != TeamRole.LEADER:
		return false

	members[player_id].role = new_role
	updated_at = int(Time.get_ticks_msec() / 1000)
	return true


## 统计方法

func get_win_rate() -> float:
	"""获取胜率"""
	var total = wins + losses
	if total == 0:
		return 0.0
	return float(wins) / float(total)


func get_level_progress() -> float:
	"""获取当前等级进度"""
	var exp_needed = 1000 * level
	return float(experience) / float(exp_needed)


func add_experience(amount: int) -> void:
	"""增加经验"""
	experience += amount
	var exp_needed = 1000 * level

	# 升级
	while experience >= exp_needed:
		experience -= exp_needed
		level += 1
		exp_needed = 1000 * level
		print("[Team] Level up! New level: %d" % level)


func add_win(rating_change: int = 16) -> void:
	"""添加胜利"""
	wins += 1
	rating += rating_change
	add_experience(50)
	updated_at = int(Time.get_ticks_msec() / 1000)


func add_loss(rating_change: int = -16) -> void:
	"""添加失败"""
	losses += 1
	rating = max(0, rating + rating_change)
	add_experience(10)
	updated_at = int(Time.get_ticks_msec() / 1000)


func contribute_to_fund(player_id: String, amount: int) -> bool:
	"""贡献到战队基金"""
	if not members.has(player_id):
		return false

	team_fund += amount
	total_contributed += amount
	members[player_id].contribution += amount
	updated_at = int(Time.get_ticks_msec() / 1000)

	print("[Team] Contribution: %s contributed %d" % [player_id, amount])
	return true


func withdraw_from_fund(amount: int) -> bool:
	"""从基金提取"""
	if team_fund < amount:
		return false

	team_fund -= amount
	updated_at = int(Time.get_ticks_msec() / 1000)
	return true


## 查询方法

func get_officers() -> Array:
	"""获取所有官员"""
	var officers = []
	for member in members.values():
		if member.role == TeamRole.OFFICER:
			officers.append(member)
	return officers


func get_top_contributors(limit: int = 10) -> Array:
	"""获取贡献最多的成员"""
	var contributors = members.values().duplicate()
	contributors.sort_custom(func(a, b): return a.contribution > b.contribution)
	return contributors.slice(0, min(limit, contributors.size()))


func get_display_text() -> String:
	"""获取显示文本"""
	var rate = "%.1f%%" % (get_win_rate() * 100)
	return "%s (Lv.%d ⭐%d) - 成员:%d/%d | 胜率:%s" % [
		team_name, level, rating, member_count, max_members, rate
	]


func get_summary() -> String:
	"""获取摘要"""
	var rate = "%.1f%%" % (get_win_rate() * 100)
	return """
	战队: %s
	等级: %d | 评分: %d | 胜率: %s
	成员: %d/%d | 资金: %d
	队长: %s
	创建时间: %s
	""" % [
		team_name, level, rating, rate,
		member_count, max_members, team_fund,
		leader_name,
		Time.get_datetime_dict_from_unix_time(founded_at)
	]


## 序列化

func to_dict() -> Dictionary:
	"""转换为字典"""
	var members_data = []
	for member in members.values():
		members_data.append({
			"player_id": member.player_id,
			"player_name": member.player_name,
			"role": member.role,
			"joined_at": member.joined_at,
			"contribution": member.contribution,
			"level": member.level,
			"rating": member.rating
		})

	return {
		"team_id": team_id,
		"team_name": team_name,
		"leader_id": leader_id,
		"leader_name": leader_name,
		"description": description,
		"logo_url": logo_url,
		"level": level,
		"experience": experience,
		"wins": wins,
		"losses": losses,
		"rating": rating,
		"members": members_data,
		"max_members": max_members,
		"team_fund": team_fund,
		"total_contributed": total_contributed,
		"founded_at": founded_at,
		"updated_at": updated_at
	}


func from_dict(data: Dictionary) -> void:
	"""从字典恢复"""
	if data.has("team_id"):
		team_id = data["team_id"]
	if data.has("team_name"):
		team_name = data["team_name"]
	if data.has("leader_id"):
		leader_id = data["leader_id"]
	if data.has("leader_name"):
		leader_name = data["leader_name"]
	if data.has("description"):
		description = data["description"]
	if data.has("logo_url"):
		logo_url = data["logo_url"]
	if data.has("level"):
		level = data["level"]
	if data.has("experience"):
		experience = data["experience"]
	if data.has("wins"):
		wins = data["wins"]
	if data.has("losses"):
		losses = data["losses"]
	if data.has("rating"):
		rating = data["rating"]
	if data.has("max_members"):
		max_members = data["max_members"]
	if data.has("team_fund"):
		team_fund = data["team_fund"]
	if data.has("total_contributed"):
		total_contributed = data["total_contributed"]
	if data.has("founded_at"):
		founded_at = data["founded_at"]
	if data.has("updated_at"):
		updated_at = data["updated_at"]

	# 加载成员
	members.clear()
	if data.has("members"):
		for member_data in data["members"]:
			var member = TeamMember.new(member_data["player_id"], member_data["player_name"])
			member.role = member_data.get("role", TeamRole.MEMBER)
			member.joined_at = member_data.get("joined_at", 0)
			member.contribution = member_data.get("contribution", 0)
			member.level = member_data.get("level", 1)
			member.rating = member_data.get("rating", 1000)
			members[member.player_id] = member

	member_count = members.size()
