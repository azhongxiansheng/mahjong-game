class_name DatabaseManager

# 数据库管理器
# 使用JSON文件实现简单的数据持久化
# 注：生产环境建议使用SQLite或其他数据库

var data_dir: String = "user://"  # Godot用户目录
var users_file: String = "users.json"
var records_file: String = "game_records.json"
var stats_file: String = "player_stats.json"

var users: Dictionary = {}       # user_id -> User
var game_records: Array = []     # GameRecord数组
var player_stats: Dictionary = {}  # user_id -> PlayerStats

func _init() -> void:
	"""初始化数据库管理器"""
	print("DatabaseManager: 已初始化")
	load_all_data()

func load_all_data() -> void:
	"""加载所有数据"""
	load_users()
	load_game_records()
	load_player_stats()
	print("DatabaseManager: 所有数据已加载")

func save_all_data() -> void:
	"""保存所有数据"""
	save_users()
	save_game_records()
	save_player_stats()
	print("DatabaseManager: 所有数据已保存")

# ========== 用户管理 ==========

func register_user(username: String, email: String, password: String) -> bool:
	"""注册新用户"""
	# 检查用户名是否已存在
	for user in users.values():
		if user.username == username:
			print("DatabaseManager: 用户名已存在 %s" % username)
			return false
	
	var new_user = User.new(username, email)
	new_user.set_password(password)
	users[new_user.user_id] = new_user
	
	# 为新用户创建统计记录
	player_stats[new_user.user_id] = PlayerStats.new(new_user.user_id)
	
	save_all_data()
	print("DatabaseManager: 用户已注册 %s" % username)
	return true

func login_user(username: String, password: String) -> User:
	"""用户登录"""
	for user in users.values():
		if user.username == username:
			if user.verify_password(password):
				user.update_last_login()
				save_users()
				print("DatabaseManager: 用户已登录 %s" % username)
				return user
			else:
				print("DatabaseManager: 密码错误")
				return null
	
	print("DatabaseManager: 用户不存在 %s" % username)
	return null

func get_user(user_id: String) -> User:
	"""获取用户"""
	return users.get(user_id, null)

func user_exists(username: String) -> bool:
	"""检查用户是否存在"""
	for user in users.values():
		if user.username == username:
			return true
	return false

func save_users() -> void:
	"""保存用户数据"""
	var user_data: Array = []
	for user in users.values():
		user_data.append(user.get_user_info())
	
	var json_str = JSON.stringify(user_data)
	var file = FileAccess.open(data_dir + users_file, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		print("DatabaseManager: 用户数据已保存到 %s" % users_file)

func load_users() -> void:
	"""加载用户数据"""
	if not FileAccess.file_exists(data_dir + users_file):
		print("DatabaseManager: 用户文件不存在，将创建新文件")
		return
	
	var file = FileAccess.open(data_dir + users_file, FileAccess.READ)
	if file:
		var json_str = file.get_as_text()
		var json = JSON.new()
		var parse_result = json.parse(json_str)
		
		if parse_result == OK and json.data is Array:
			for user_data in json.data:
				var user = User.from_dict(user_data)
				users[user.user_id] = user
			print("DatabaseManager: 已加载 %d 个用户" % users.size())

# ========== 游戏记录管理 ==========

func save_game_record(record: GameRecord) -> void:
	"""保存游戏记录"""
	game_records.append(record)
	
	# 更新玩家统计
	if record.user_id in player_stats:
		player_stats[record.user_id].record_game(record.result, record.fan)
	
	save_all_data()
	print("DatabaseManager: 游戏记录已保存")

func get_user_records(user_id: String, limit: int = -1) -> Array:
	"""获取用户的游戏记录"""
	var user_records: Array = []
	for record in game_records:
		if record.user_id == user_id:
			user_records.append(record)
	
	# 按时间倒序排列
	user_records.sort_custom(func(a: GameRecord, b: GameRecord) -> bool:
		return a.timestamp > b.timestamp
	)
	
	# 限制数量
	if limit > 0 and user_records.size() > limit:
		user_records.resize(limit)
	
	return user_records

func save_game_records() -> void:
	"""保存游戏记录"""
	var records_data: Array = []
	for record in game_records:
		records_data.append(record.get_record_info())
	
	var json_str = JSON.stringify(records_data)
	var file = FileAccess.open(data_dir + records_file, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		print("DatabaseManager: 游戏记录已保存到 %s" % records_file)

func load_game_records() -> void:
	"""加载游戏记录"""
	if not FileAccess.file_exists(data_dir + records_file):
		print("DatabaseManager: 游戏记录文件不存在")
		return
	
	var file = FileAccess.open(data_dir + records_file, FileAccess.READ)
	if file:
		var json_str = file.get_as_text()
		var json = JSON.new()
		var parse_result = json.parse(json_str)
		
		if parse_result == OK and json.data is Array:
			for record_data in json.data:
				var record = GameRecord.from_dict(record_data)
				game_records.append(record)
			print("DatabaseManager: 已加载 %d 条游戏记录" % game_records.size())

# ========== 玩家统计管理 ==========

func get_player_stats(user_id: String) -> PlayerStats:
	"""获取玩家统计"""
	return player_stats.get(user_id, null)

func get_leaderboard(limit: int = 100) -> Array:
	"""获取排行榜"""
	var leaders: Array = []
	for stats in player_stats.values():
		leaders.append(stats)
	
	# 按评级倒序排列
	leaders.sort_custom(func(a: PlayerStats, b: PlayerStats) -> bool:
		return a.rating > b.rating
	)
	
	# 限制数量
	if limit > 0 and leaders.size() > limit:
		leaders.resize(limit)
	
	# 设置排名
	for i in range(leaders.size()):
		leaders[i].ranking = i + 1
	
	return leaders

func save_player_stats() -> void:
	"""保存玩家统计"""
	var stats_data: Array = []
	for stats in player_stats.values():
		stats_data.append(stats.get_stats_info())
	
	var json_str = JSON.stringify(stats_data)
	var file = FileAccess.open(data_dir + stats_file, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		print("DatabaseManager: 玩家统计已保存到 %s" % stats_file)

func load_player_stats() -> void:
	"""加载玩家统计"""
	if not FileAccess.file_exists(data_dir + stats_file):
		print("DatabaseManager: 玩家统计文件不存在")
		return
	
	var file = FileAccess.open(data_dir + stats_file, FileAccess.READ)
	if file:
		var json_str = file.get_as_text()
		var json = JSON.new()
		var parse_result = json.parse(json_str)
		
		if parse_result == OK and json.data is Array:
			for stats_data in json.data:
				var stats = PlayerStats.from_dict(stats_data)
				player_stats[stats.user_id] = stats
			print("DatabaseManager: 已加载 %d 条玩家统计" % player_stats.size())

func get_database_stats() -> Dictionary:
	"""获取数据库统计"""
	return {
		"users_count": users.size(),
		"records_count": game_records.size(),
		"stats_count": player_stats.size()
	}
