class_name GameServer

# 游戏服务器类（模拟版）
# 用于管理房间、玩家和游戏流程

var rooms: Dictionary = {} # room_id -> GameRoom
var player_to_room: Dictionary = {} # player_id -> room_id
var next_room_id: int = 1

# 统计数据
var total_rooms_created: int = 0
var total_players_connected: int = 0

func _init():
	"""初始化游戏服务器"""
	print("✓ GameServer: 已启动")

func create_room(max_players: int = 4) -> GameRoom:
	"""创建新房间"""
	var room_id = "room_%04d" % next_room_id
	next_room_id += 1

	var room = GameRoom.new(room_id, max_players)
	rooms[room_id] = room
	total_rooms_created += 1

	print("✓ GameServer: 创建房间 %s" % room_id)

	return room

func player_join_room(player_id: String, room_id: String) -> bool:
	"""玩家加入房间"""
	if room_id not in rooms:
		print("GameServer: 房间不存在 %s" % room_id)
		return false

	if player_id in player_to_room:
		print("GameServer: 玩家已在其他房间中")
		return false

	var room = rooms[room_id]
	if room.add_player(player_id):
		player_to_room[player_id] = room_id
		total_players_connected += 1
		return true

	return false

func player_leave_room(player_id: String) -> bool:
	"""玩家离开房间"""
	if player_id not in player_to_room:
		return false

	var room_id = player_to_room[player_id]
	var room = rooms.get(room_id)

	if room:
		room.remove_player(player_id)

		# 如果房间空了，删除房间
		if room.is_empty():
			rooms.erase(room_id)
			print("GameServer: 房间已删除 %s" % room_id)

	player_to_room.erase(player_id)
	return true

func get_room(room_id: String) -> GameRoom:
	"""获取房间"""
	return rooms.get(room_id, null)

func get_player_room(player_id: String) -> GameRoom:
	"""获取玩家所在的房间"""
	var room_id = player_to_room.get(player_id)
	if room_id:
		return rooms.get(room_id)
	return null

func get_room_list() -> Array[GameRoom]:
	"""获取所有房间列表"""
	var room_list: Array[GameRoom] = []
	for room in rooms.values():
		room_list.append(room)
	return room_list

func get_available_rooms() -> Array[GameRoom]:
	"""获取有空位的房间"""
	var available: Array[GameRoom] = []
	for room in rooms.values():
		if room.room_state == GameRoom.RoomState.WAITING and not room.is_full():
			available.append(room)
	return available

func broadcast_message(message: NetworkMessage.Message, room_id: String = "") -> void:
	"""广播消息到房间（模拟）"""
	if room_id == "":
		# 广播到所有房间
		for room in rooms.values():
			_simulate_message_delivery(message, room.room_id)
	else:
		# 广播到特定房间
		_simulate_message_delivery(message, room_id)

func start_game_in_room(room_id: String) -> bool:
	"""在房间中开始游戏"""
	var room = get_room(room_id)
	if not room:
		return false

	return room.start_game()

func end_game_in_room(room_id: String) -> bool:
	"""结束房间中的游戏"""
	var room = get_room(room_id)
	if not room:
		return false

	return room.end_game()

func process_player_action(player_id: String, action: String, action_data: Dictionary) -> bool:
	"""处理玩家操作"""
	var room = get_player_room(player_id)
	if not room:
		print("GameServer: 玩家不在任何房间中 %s" % player_id)
		return false

	print("GameServer: 处理玩家 %s 的操作 %s" % [player_id, action])

	# 这里可以添加具体的操作处理逻辑
	match action:
		"discard_card":
			# 处理出牌
			pass
		"draw_card":
			# 处理抽卡
			pass
		"hu":
			# 处理胡牌
			pass

	return true

func get_server_stats() -> Dictionary:
	"""获取服务器统计数据"""
	var active_players = 0
	for player_id in player_to_room:
		active_players += 1

	return {
		"total_rooms_created": total_rooms_created,
		"active_rooms": rooms.size(),
		"active_players": active_players,
		"total_players_connected": total_players_connected
	}

func get_status_string() -> String:
	"""获取服务器状态字符串"""
	var stats = get_server_stats()
	return "GameServer [活跃房间: %d, 活跃玩家: %d, 总房间: %d]" % [
		stats["active_rooms"],
		stats["active_players"],
		stats["total_rooms_created"]
	]

# 私有方法

func _simulate_message_delivery(message: NetworkMessage.Message, room_id: String) -> void:
	"""模拟消息传递"""
	var room = rooms.get(room_id)
	if room:
		print("📢 GameServer: 广播消息 %s 到房间 %s" % [NetworkMessage.get_message_type_name(message.type), room_id])

func get_room_info_list() -> Array:
	"""获取所有房间的信息列表"""
	var info_list: Array = []
	for room in rooms.values():
		info_list.append(room.get_room_info())
	return info_list
