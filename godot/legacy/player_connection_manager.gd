class_name PlayerConnectionManager
extends Node

# 连接状态
enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	PLAYING,
	DISCONNECTING,
	TIMEOUT
}

# 玩家连接类
class PlayerConnection:
	var player_id: String
	var player_name: String
	var state: int = ConnectionState.DISCONNECTED
	var connected_time: float = 0.0
	var last_heartbeat: float = 0.0
	var latency: float = 0.0
	var player_data: Dictionary = {}
	var is_local: bool = false
	
	func _init(p_id: String, p_name: String = "玩家") -> void:
		player_id = p_id
		player_name = p_name
		connected_time = Time.get_ticks_msec()
	
	func update_heartbeat() -> void:
		last_heartbeat = Time.get_ticks_msec()
	
	func get_connection_duration() -> float:
		"""获取连接时长（秒）"""
		return (Time.get_ticks_msec() - connected_time) / 1000.0
	
	func get_state_name() -> String:
		match state:
			ConnectionState.DISCONNECTED:
				return "已断开"
			ConnectionState.CONNECTING:
				return "连接中"
			ConnectionState.CONNECTED:
				return "已连接"
			ConnectionState.PLAYING:
				return "游戏中"
			ConnectionState.DISCONNECTING:
				return "断开中"
			ConnectionState.TIMEOUT:
				return "超时"
			_:
				return "未知"

# 连接管理系统
var connections: Dictionary = {}  # player_id -> PlayerConnection
var max_players: int = 4
var connection_timeout: int = 30  # 秒
var heartbeat_interval: int = 5   # 秒

# 统计数据
var total_connected: int = 0
var total_disconnected: int = 0
var connection_errors: int = 0

# 信号
signal player_connected(player_connection: PlayerConnection)
signal player_disconnected(player_id: String, reason: String)
signal player_state_changed(player_id: String, new_state: int)
signal connection_timeout_detected(player_id: String)
signal latency_updated(player_id: String, latency: float)

func _ready() -> void:
	print("========== 玩家连接管理器初始化 ==========")
	print("最大玩家数: ", max_players)
	print("连接超时: ", connection_timeout, "秒")
	print("心跳间隔: ", heartbeat_interval, "秒")

func _process(_delta: float) -> void:
	# 定期检查连接超时
	check_connection_timeouts()

func establish_connection(player_info: Dictionary) -> bool:
	"""建立新的玩家连接"""
	var player_id = player_info.get("player_id", "")
	var player_name = player_info.get("player_name", "玩家")
	
	if player_id == "":
		print("✗ 玩家ID为空")
		connection_errors += 1
		return false
	
	if player_id in connections:
		print("⚠ 玩家已存在: ", player_id)
		return false
	
	if connections.size() >= max_players:
		print("✗ 玩家数量已满")
		connection_errors += 1
		return false
	
	# 创建新连接
	var connection = PlayerConnection.new(player_id, player_name)
	connection.player_data = player_info
	connection.state = ConnectionState.CONNECTED
	connection.update_heartbeat()
	
	connections[player_id] = connection
	total_connected += 1
	
	print("✓ 玩家已连接: ", player_id, " (", player_name, ")")
	emit_signal("player_connected", connection)
	
	return true

func close_connection(player_id: String, reason: String = "玩家主动断开") -> void:
	"""关闭玩家连接"""
	if not (player_id in connections):
		print("⚠ 玩家连接不存在: ", player_id)
		return
	
	var connection = connections[player_id]
	connection.state = ConnectionState.DISCONNECTED
	
	connections.erase(player_id)
	total_disconnected += 1
	
	print("✓ 玩家已断开: ", player_id, " (", reason, ")")
	emit_signal("player_disconnected", player_id, reason)

func send_heartbeat_to_player(player_id: String) -> bool:
	"""向玩家发送心跳"""
	if not (player_id in connections):
		return false
	
	var connection = connections[player_id]
	connection.update_heartbeat()
	
	return true

func receive_heartbeat_response(player_id: String, latency: float) -> void:
	"""接收心跳响应"""
	if not (player_id in connections):
		return
	
	var connection = connections[player_id]
	connection.latency = latency
	connection.update_heartbeat()
	
	emit_signal("latency_updated", player_id, latency)

func check_connection_timeouts() -> void:
	"""检查连接是否超时"""
	var current_time = Time.get_ticks_msec()
	var timeout_ms = connection_timeout * 1000
	
	var timedout_players = []
	
	for player_id in connections.keys():
		var connection = connections[player_id]
		
		# 检查心跳超时
		if connection.state == ConnectionState.CONNECTED or connection.state == ConnectionState.PLAYING:
			var time_since_heartbeat = (current_time - connection.last_heartbeat) / 1000.0
			
			if time_since_heartbeat > connection_timeout:
				print("✗ 玩家连接超时: ", player_id, " (", int(time_since_heartbeat), "秒)")
				connection.state = ConnectionState.TIMEOUT
				timedout_players.append(player_id)
				emit_signal("connection_timeout_detected", player_id)

func change_player_state(player_id: String, new_state: int) -> bool:
	"""改变玩家连接状态"""
	if not (player_id in connections):
		return false
	
	var connection = connections[player_id]
	var old_state = connection.state
	connection.state = new_state
	
	if old_state != new_state:
		print("🔄 玩家状态变更: ", player_id, " ", connection.get_state_name())
		emit_signal("player_state_changed", player_id, new_state)
	
	return true

func get_all_connected_players() -> Array:
	"""获取所有已连接的玩家"""
	var players = []
	for player_id in connections.keys():
		var conn = connections[player_id]
		players.append({
			"player_id": player_id,
			"player_name": conn.player_name,
			"state": conn.state,
			"latency": conn.latency,
			"connection_duration": conn.get_connection_duration()
		})
	return players

func get_playing_players() -> Array:
	"""获取所有游戏中的玩家"""
	var players = []
	for player_id in connections.keys():
		var conn = connections[player_id]
		if conn.state == ConnectionState.PLAYING:
			players.append(player_id)
	return players

func is_player_connected(player_id: String) -> bool:
	"""检查玩家是否已连接"""
	if not (player_id in connections):
		return false
	
	var connection = connections[player_id]
	return connection.state != ConnectionState.DISCONNECTED

func get_player_connection(player_id: String) -> PlayerConnection:
	"""获取玩家连接对象"""
	if player_id in connections:
		return connections[player_id]
	return null

func get_player_latency(player_id: String) -> float:
	"""获取玩家延迟"""
	if player_id in connections:
		return connections[player_id].latency
	return -1.0

func get_player_state(player_id: String) -> int:
	"""获取玩家状态"""
	if player_id in connections:
		return connections[player_id].state
	return ConnectionState.DISCONNECTED

func get_connected_count() -> int:
	"""获取已连接玩家数量"""
	return connections.size()

func get_available_slots() -> int:
	"""获取可用玩家槽位"""
	return max(0, max_players - connections.size())

func can_add_player() -> bool:
	"""检查是否可以添加新玩家"""
	return connections.size() < max_players

func broadcast_to_all(callback: Callable) -> void:
	"""对所有已连接玩家执行回调"""
	for player_id in connections.keys():
		callback.call(player_id)

func get_connection_info() -> Dictionary:
	"""获取连接统计信息"""
	return {
		"connected_players": get_connected_count(),
		"available_slots": get_available_slots(),
		"total_connected": total_connected,
		"total_disconnected": total_disconnected,
		"connection_errors": connection_errors,
		"timeout_threshold": connection_timeout
	}

func print_connection_status() -> void:
	"""打印连接状态"""
	print("\n========== 玩家连接状态 ==========")
	print("已连接玩家: ", get_connected_count(), "/", max_players)
	print("可用槽位: ", get_available_slots())
	print("总连接数: ", total_connected)
	print("总断开数: ", total_disconnected)
	print("连接错误: ", connection_errors)
	
	if connections.size() > 0:
		print("\n玩家列表:")
		for player_id in connections.keys():
			var conn = connections[player_id]
			print("  - ", conn.player_name, " (", player_id, ")")
			print("    状态: ", conn.get_state_name())
			print("    延迟: ", int(conn.latency), "ms")
			print("    连接时长: ", int(conn.get_connection_duration()), "s")
	
	print("==================================\n")

func clear_all_connections() -> void:
	"""清除所有连接"""
	print("✓ 清除所有玩家连接")
	connections.clear()
	total_connected = 0
	total_disconnected = 0
	connection_errors = 0
