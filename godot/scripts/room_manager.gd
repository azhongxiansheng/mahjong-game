# 房间管理器 - 处理房间创建、管理和玩家配对
class_name RoomManager

# 房间状态
enum RoomState {
	WAITING = 0,      # 等待中
	READY = 1,        # 准备就绪
	PLAYING = 2,      # 游戏中
	FINISHED = 3      # 已结束
}

# 房间信息类
class Room:
	var room_id: String
	var room_name: String
	var host_id: String
	var state: int = RoomState.WAITING
	var max_players: int = 4
	var players: Dictionary = {}      # player_id -> player_info
	var created_time: int = 0
	var started_time: int = 0
	var round_score: Dictionary = {}  # player_id -> score
	
	func _init(id: String, name: String, host_id_param: String, max_p: int = 4) -> void:
		room_id = id
		room_name = name
		host_id = host_id_param
		max_players = max_p
		created_time = Time.get_ticks_msec()
	
	func add_player(player_id: String, player_info: Dictionary) -> bool:
		if players.size() >= max_players:
			return false
		players[player_id] = player_info
		return true
	
	func remove_player(player_id: String) -> void:
		if player_id in players:
			players.erase(player_id)
	
	func get_player_count() -> int:
		return players.size()
	
	func is_full() -> bool:
		return players.size() >= max_players
	
	func is_ready() -> bool:
		return players.size() >= 2 and state == RoomState.READY
	
	func to_dict() -> Dictionary:
		return {
			"room_id": room_id,
			"room_name": room_name,
			"host_id": host_id,
			"state": state,
			"player_count": players.size(),
			"max_players": max_players,
			"players": players
		}

# 房间管理
var _rooms: Dictionary = {}        # room_id -> Room
var _player_rooms: Dictionary = {} # player_id -> room_id
var _room_id_counter: int = 1000

# 信号
signal room_created(room_info: Dictionary)
signal room_destroyed(room_id: String)
signal player_joined_room(room_id: String, player_id: String)
signal player_left_room(room_id: String, player_id: String)
signal room_state_changed(room_id: String, new_state: int)

# 创建房间
func create_room(room_name: String, host_id: String, max_players: int = 4) -> String:
	var room_id = "room_%d" % _room_id_counter
	_room_id_counter += 1
	
	var room = Room.new(room_id, room_name, host_id, max_players)
	_rooms[room_id] = room
	_player_rooms[host_id] = room_id
	
	print("[RoomManager] 房间已创建: %s (主持人: %s)" % [room_id, host_id])
	room_created.emit(room.to_dict())
	
	return room_id

# 加入房间
func join_room(room_id: String, player_id: String, player_info: Dictionary) -> bool:
	if room_id not in _rooms:
		print("[RoomManager] 房间不存在: %s" % room_id)
		return false
	
	var room = _rooms[room_id]
	if not room.add_player(player_id, player_info):
		print("[RoomManager] 无法加入房间: %s (已满)" % room_id)
		return false
	
	_player_rooms[player_id] = room_id
	print("[RoomManager] 玩家加入房间: %s -> %s" % [player_id, room_id])
	player_joined_room.emit(room_id, player_id)
	
	return true

# 离开房间
func leave_room(player_id: String) -> bool:
	if player_id not in _player_rooms:
		return false
	
	var room_id = _player_rooms[player_id]
	var room = _rooms[room_id]
	
	room.remove_player(player_id)
	_player_rooms.erase(player_id)
	
	print("[RoomManager] 玩家离开房间: %s <- %s" % [room_id, player_id])
	player_left_room.emit(room_id, player_id)
	
	# 如果房间为空，销毁房间
	if room.get_player_count() == 0:
		_rooms.erase(room_id)
		room_destroyed.emit(room_id)
	
	return true

# 设置房间状态
func set_room_state(room_id: String, new_state: int) -> bool:
	if room_id not in _rooms:
		return false
	
	var room = _rooms[room_id]
	room.state = new_state
	
	if new_state == RoomState.PLAYING:
		room.started_time = Time.get_ticks_msec()
	
	room_state_changed.emit(room_id, new_state)
	return true

# 获取房间信息
func get_room(room_id: String) -> Room:
	if room_id in _rooms:
		return _rooms[room_id]
	return null

# 获取玩家的房间
func get_player_room(player_id: String) -> Room:
	if player_id in _player_rooms:
		var room_id = _player_rooms[player_id]
		return get_room(room_id)
	return null

# 获取所有房间列表
func get_room_list() -> Array:
	var room_list = []
	for room_id in _rooms.keys():
		var room = _rooms[room_id]
		if room.state == RoomState.WAITING:  # 只返回等待中的房间
			room_list.append(room.to_dict())
	return room_list

# 获取可加入的房间
func get_joinable_rooms() -> Array:
	var joinable = []
	for room_id in _rooms.keys():
		var room = _rooms[room_id]
		if room.state == RoomState.WAITING and not room.is_full():
			joinable.append(room.to_dict())
	return joinable

# 更新圆形得分
func update_round_score(room_id: String, player_id: String, score: int) -> bool:
	if room_id not in _rooms:
		return false
	
	var room = _rooms[room_id]
	room.round_score[player_id] = score
	return true

# 获取房间得分
func get_room_scores(room_id: String) -> Dictionary:
	if room_id not in _rooms:
		return {}
	
	return _rooms[room_id].round_score.duplicate()

# 获取房间统计
func get_statistics() -> Dictionary:
	var total_rooms = _rooms.size()
	var waiting_rooms = 0
	var total_players = 0
	
	for room_id in _rooms.keys():
		var room = _rooms[room_id]
		if room.state == RoomState.WAITING:
			waiting_rooms += 1
		total_players += room.get_player_count()
	
	return {
		"total_rooms": total_rooms,
		"waiting_rooms": waiting_rooms,
		"total_players": total_players
	}

# 打印状态
func print_status() -> void:
	var stats = get_statistics()
	print("\n=== 房间管理器状态 ===")
	print("总房间数: %d" % stats["total_rooms"])
	print("等待中: %d" % stats["waiting_rooms"])
	print("总玩家数: %d" % stats["total_players"])
	print("========================\n")
