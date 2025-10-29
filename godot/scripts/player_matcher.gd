# 玩家配对系统 - 处理玩家匹配和队列管理
class_name PlayerMatcher

# 配对模式
enum MatchMode {
	CASUAL = 0,      # 休闲模式
	RANKED = 1,      # 排位模式
	FRIEND = 2       # 好友模式
}

# 玩家等级
enum PlayerRank {
	BRONZE = 0,      # 青铜
	SILVER = 1,      # 白银
	GOLD = 2,        # 黄金
	PLATINUM = 3,    # 铂金
	DIAMOND = 4,     # 钻石
	MASTER = 5       # 大师
}

# 玩家队列项
class QueueItem:
	var player_id: String
	var player_name: String
	var rank: int = PlayerRank.BRONZE
	var skill_level: float = 1.0
	var queue_time: int = 0
	var mode: int = MatchMode.CASUAL
	var preferred_players: Array = []  # 偏好的玩家列表
	
	func _init(id: String, name: String, m: int = MatchMode.CASUAL) -> void:
		player_id = id
		player_name = name
		mode = m
		queue_time = Time.get_ticks_msec()
	
	func get_wait_time() -> int:
		return Time.get_ticks_msec() - queue_time
	
	func to_dict() -> Dictionary:
		return {
			"player_id": player_id,
			"player_name": player_name,
			"rank": rank,
			"skill_level": skill_level,
			"wait_time": get_wait_time()
		}

# 队列管理
var _queue: Array = []                # QueueItem列表
var _casual_queue: Array = []         # 休闲队列
var _ranked_queue: Array = []         # 排位队列
var _waiting_players: Dictionary = {} # player_id -> QueueItem
var _match_history: Array = []        # 最近的配对记录

# 配置
const MAX_QUEUE_SIZE = 1000
const MATCH_TIMEOUT = 30000           # 30秒
const SKILL_TOLERANCE = 0.5           # 技能差异容限

# 信号
signal player_queued(player_info: Dictionary)
signal player_dequeued(player_id: String)
signal match_found(players: Array)
signal match_failed(player_id: String, reason: String)

# 加入配对队列
func join_queue(player_id: String, player_name: String, mode: int = MatchMode.CASUAL) -> bool:
	if _waiting_players.size() >= MAX_QUEUE_SIZE:
		print("[PlayerMatcher] 队列已满")
		return false
	
	if player_id in _waiting_players:
		print("[PlayerMatcher] 玩家已在队列中: %s" % player_id)
		return false
	
	var queue_item = QueueItem.new(player_id, player_name, mode)
	_waiting_players[player_id] = queue_item
	_queue.append(queue_item)
	
	if mode == MatchMode.CASUAL:
		_casual_queue.append(queue_item)
	else:
		_ranked_queue.append(queue_item)
	
	print("[PlayerMatcher] 玩家加入队列: %s (模式: %s)" % [player_id, MatchMode.keys()[mode]])
	player_queued.emit(queue_item.to_dict())
	
	return true

# 离开配对队列
func leave_queue(player_id: String) -> bool:
	if player_id not in _waiting_players:
		return false
	
	var queue_item = _waiting_players[player_id]
	
	_queue.erase(queue_item)
	if queue_item.mode == MatchMode.CASUAL:
		_casual_queue.erase(queue_item)
	else:
		_ranked_queue.erase(queue_item)
	
	_waiting_players.erase(player_id)
	
	print("[PlayerMatcher] 玩家离开队列: %s" % player_id)
	player_dequeued.emit(player_id)
	
	return true

# 尝试配对
func try_match() -> bool:
	# 优先处理排位队列
	if _ranked_queue.size() >= 4:
		var matched = _match_ranked()
		if matched:
			return true
	
	# 然后处理休闲队列
	if _casual_queue.size() >= 4:
		var matched = _match_casual()
		if matched:
			return true
	
	return false

# 排位配对逻辑
func _match_ranked() -> bool:
	if _ranked_queue.size() < 2:
		return false
	
	# 按等级和技能等级排序
	_ranked_queue.sort_custom(func(a, b): return a.rank > b.rank)
	
	var matched_players = []
	var base_item = _ranked_queue[0]
	matched_players.append(base_item)
	
	# 寻找技能接近的玩家
	for i in range(1, _ranked_queue.size()):
		var item = _ranked_queue[i]
		var skill_diff = abs(item.skill_level - base_item.skill_level)
		
		if skill_diff <= SKILL_TOLERANCE:
			matched_players.append(item)
			if matched_players.size() >= 4:
				break
	
	if matched_players.size() >= 2:
		_create_match(matched_players, MatchMode.RANKED)
		return true
	
	return false

# 休闲配对逻辑
func _match_casual() -> bool:
	if _casual_queue.size() < 2:
		return false
	
	var matched_players = []
	for i in range(min(4, _casual_queue.size())):
		matched_players.append(_casual_queue[i])
	
	if matched_players.size() >= 2:
		_create_match(matched_players, MatchMode.CASUAL)
		return true
	
	return false

# 创建配对
func _create_match(matched_players: Array, mode: int) -> void:
	var match_info = {
		"player_ids": [],
		"player_names": [],
		"mode": mode,
		"timestamp": Time.get_ticks_msec()
	}
	
	for item in matched_players:
		match_info["player_ids"].append(item.player_id)
		match_info["player_names"].append(item.player_name)
		
		# 从队列中移除
		_waiting_players.erase(item.player_id)
		_queue.erase(item)
		
		if item.mode == MatchMode.CASUAL:
			_casual_queue.erase(item)
		else:
			_ranked_queue.erase(item)
	
	_match_history.append(match_info)
	
	print("[PlayerMatcher] 配对成功: %d个玩家" % matched_players.size())
	match_found.emit(match_info["player_ids"])

# 更新玩家技能等级
func update_player_skill(player_id: String, skill_level: float) -> bool:
	if player_id not in _waiting_players:
		return false
	
	_waiting_players[player_id].skill_level = skill_level
	return true

# 更新玩家排名
func update_player_rank(player_id: String, rank: int) -> bool:
	if player_id not in _waiting_players:
		return false
	
	_waiting_players[player_id].rank = rank
	return true

# 获取队列状态
func get_queue_status() -> Dictionary:
	return {
		"total_queue": _queue.size(),
		"casual_queue": _casual_queue.size(),
		"ranked_queue": _ranked_queue.size(),
		"match_history": _match_history.size()
	}

# 获取玩家在队列中的位置
func get_queue_position(player_id: String) -> int:
	for i in range(_queue.size()):
		if _queue[i].player_id == player_id:
			return i + 1
	return -1

# 获取玩家等待时间
func get_wait_time(player_id: String) -> int:
	if player_id not in _waiting_players:
		return 0
	
	return _waiting_players[player_id].get_wait_time()

# 是否在队列中
func is_in_queue(player_id: String) -> bool:
	return player_id in _waiting_players

# 获取队列列表
func get_queue_list() -> Array:
	var list = []
	for item in _queue:
		list.append(item.to_dict())
	return list

# 清空队列
func clear_queue() -> void:
	_queue.clear()
	_casual_queue.clear()
	_ranked_queue.clear()
	_waiting_players.clear()
	print("[PlayerMatcher] 队列已清空")

# 打印统计信息
func print_statistics() -> void:
	var status = get_queue_status()
	print("\n=== 玩家配对统计 ===")
	print("总队列数: %d" % status["total_queue"])
	print("休闲队列: %d" % status["casual_queue"])
	print("排位队列: %d" % status["ranked_queue"])
	print("配对记录: %d" % status["match_history"])
	print("====================\n")
