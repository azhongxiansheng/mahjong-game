# 大厅管理器 - 协调房间和玩家配对系统
class_name LobbyManager
extends Node

var room_manager: RoomManager
var player_matcher: PlayerMatcher
var network_client: NetworkClient

# 玩家信息缓存
var _player_info: Dictionary = {}   # player_id -> player_info
var _player_stats: Dictionary = {}  # player_id -> stats

# 信号
signal lobby_initialized()
signal player_info_updated(player_id: String)
signal room_list_updated(rooms: Array)
signal match_status_changed(status: String)

func _ready() -> void:
	# 初始化管理器
	room_manager = RoomManager.new()
	player_matcher = PlayerMatcher.new()

	# 连接信号
	room_manager.room_created.connect(_on_room_created)
	room_manager.player_joined_room.connect(_on_player_joined_room)
	room_manager.player_left_room.connect(_on_player_left_room)

	player_matcher.match_found.connect(_on_match_found)
	player_matcher.player_queued.connect(_on_player_queued)
	player_matcher.player_dequeued.connect(_on_player_dequeued)

	print("[LobbyManager] 大厅管理器已初始化")
	lobby_initialized.emit()

func _process(delta: float) -> void:
	# 定期尝试配对
	if randf() < 0.1:  # 10%概率每帧尝试
		player_matcher.try_match()

# ==================== 房间操作 ====================

func create_room(room_name: String, player_id: String, max_players: int = 4) -> String:
	var room_id = room_manager.create_room(room_name, player_id, max_players)

	# 房主自动加入
	var player_info = _get_or_create_player_info(player_id)
	room_manager.join_room(room_id, player_id, player_info)

	return room_id

func join_room(room_id: String, player_id: String) -> bool:
	var player_info = _get_or_create_player_info(player_id)
	return room_manager.join_room(room_id, player_id, player_info)

func leave_room(player_id: String) -> bool:
	return room_manager.leave_room(player_id)

func get_joinable_rooms() -> Array:
	return room_manager.get_joinable_rooms()

func get_room_info(room_id: String) -> Dictionary:
	var room = room_manager.get_room(room_id)
	if room:
		return room.to_dict()
	return {}

func start_room_game(room_id: String) -> bool:
	var room = room_manager.get_room(room_id)
	if not room:
		return false

	if room.get_player_count() < 2:
		print("[LobbyManager] 房间玩家不足")
		return false

	return room_manager.set_room_state(room_id, RoomManager.RoomState.PLAYING)

# ==================== 配对操作 ====================

func start_matchmaking(player_id: String, player_name: String, mode: int = PlayerMatcher.MatchMode.CASUAL) -> bool:
	# 先离开房间（如果在房间中）
	leave_room(player_id)

	# 加入匹配队列
	return player_matcher.join_queue(player_id, player_name, mode)

func cancel_matchmaking(player_id: String) -> bool:
	return player_matcher.leave_queue(player_id)

func get_queue_position(player_id: String) -> int:
	return player_matcher.get_queue_position(player_id)

func get_queue_wait_time(player_id: String) -> int:
	return player_matcher.get_wait_time(player_id)

func get_queue_status() -> Dictionary:
	return player_matcher.get_queue_status()

# ==================== 玩家信息 ====================

func update_player_info(player_id: String, info: Dictionary) -> void:
	_player_info[player_id] = info
	player_info_updated.emit(player_id)

func get_player_info(player_id: String) -> Dictionary:
	if player_id in _player_info:
		return _player_info[player_id]
	return {}

func _get_or_create_player_info(player_id: String) -> Dictionary:
	if player_id not in _player_info:
		_player_info[player_id] = {
			"player_id": player_id,
			"player_name": "Player_%s" % player_id.substr(0, 4),
			"rank": PlayerMatcher.PlayerRank.BRONZE,
			"skill_level": 1.0,
			"total_games": 0,
			"wins": 0
		}

	return _player_info[player_id]

func update_player_stats(player_id: String, games: int, wins: int) -> void:
	var info = _get_or_create_player_info(player_id)
	info["total_games"] = games
	info["wins"] = wins

	# 更新技能等级 (赢率)
	if games > 0:
		info["skill_level"] = float(wins) / float(games)

	player_info_updated.emit(player_id)

# ==================== 信号处理 ====================

func _on_room_created(room_info: Dictionary) -> void:
	print("[LobbyManager] 房间已创建: %s" % room_info["room_id"])
	room_list_updated.emit(get_joinable_rooms())

func _on_player_joined_room(room_id: String, player_id: String) -> void:
	print("[LobbyManager] 玩家已加入房间: %s" % player_id)
	room_list_updated.emit(get_joinable_rooms())

func _on_player_left_room(room_id: String, player_id: String) -> void:
	print("[LobbyManager] 玩家已离开房间: %s" % player_id)
	room_list_updated.emit(get_joinable_rooms())

func _on_player_queued(player_info: Dictionary) -> void:
	print("[LobbyManager] 玩家已加入匹配队列: %s" % player_info["player_id"])
	match_status_changed.emit("queued")

func _on_player_dequeued(player_id: String) -> void:
	print("[LobbyManager] 玩家已离开匹配队列: %s" % player_id)
	match_status_changed.emit("dequeued")

func _on_match_found(player_ids: Array) -> void:
	print("[LobbyManager] 配对成功: %d个玩家" % player_ids.size())

	# 创建房间并将所有玩家加入
	var room_id = create_room("Matched Game %d" % Time.get_ticks_msec(), player_ids[0])

	for i in range(1, player_ids.size()):
		join_room(room_id, player_ids[i])

	# 启动游戏
	start_room_game(room_id)

	match_status_changed.emit("matched")

# ==================== 统计信息 ====================

func get_lobby_statistics() -> Dictionary:
	var room_stats = room_manager.get_statistics()
	var queue_stats = player_matcher.get_queue_status()

	return {
		"rooms": room_stats,
		"queue": queue_stats,
		"players_online": _player_info.size()
	}

func print_lobby_status() -> void:
	print("\n╔════════════════════════════════════════╗")
	print("║ 🏛️  大厅管理器状态 ║")
	print("╚════════════════════════════════════════╝")

	var stats = get_lobby_statistics()
	print("\n【房间统计】")
	print("总房间数: %d" % stats["rooms"]["total_rooms"])
	print("等待中: %d" % stats["rooms"]["waiting_rooms"])
	print("在线玩家: %d" % stats["rooms"]["total_players"])

	print("\n【配对统计】")
	print("总队列数: %d" % stats["queue"]["total_queue"])
	print("休闲队列: %d" % stats["queue"]["casual_queue"])
	print("排位队列: %d" % stats["queue"]["ranked_queue"])

	print("\n【在线信息】")
	print("注册玩家: %d" % stats["players_online"])

	print("\n════════════════════════════════════════\n")
