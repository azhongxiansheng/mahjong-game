class_name NetworkManager
extends Node

# 网络状态
enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	RECONNECTING,
	ERROR
}

# 网络事件信号
signal connection_established()
signal connection_failed(reason: String)
signal connection_lost()
signal player_joined(player_id: String, player_data: Dictionary)
signal player_left(player_id: String)
signal message_received(message_type: int, data: Dictionary)
signal network_error(error_message: String)

# 网络配置
var server_ip: String = "127.0.0.1"
var server_port: int = 8888
var connection_timeout: int = 30
var reconnect_attempts: int = 3
var reconnect_delay: float = 2.0

# 网络状态
var current_state: int = ConnectionState.DISCONNECTED
var is_connected: bool = false
var current_player_id: String = ""
var session_id: String = ""

# 玩家管理
var other_players: Dictionary = {}  # player_id -> player_data
var max_players: int = 4
var local_player_data: Dictionary = {
	"name": "玩家",
	"id": "",
	"status": "online"
}

# 连接管理
var tcp_peer: StreamPeerTCP
var connection_attempt: int = 0
var last_connection_time: float = 0.0
var heartbeat_timer: float = 0.0
var heartbeat_interval: float = 5.0

# 消息队列
var message_queue: Array = []
var pending_messages: Dictionary = {}

func _ready() -> void:
	print("========== 网络管理系统初始化 ==========")
	tcp_peer = StreamPeerTCP.new()
	print("✓ NetworkManager已初始化")
	print("服务器地址: ", server_ip, ":", server_port)

func _process(delta: float) -> void:
	if current_state == ConnectionState.CONNECTED:
		heartbeat_timer += delta
		if heartbeat_timer >= heartbeat_interval:
			send_heartbeat()
			heartbeat_timer = 0.0
		
		# 处理接收的消息
		process_incoming_messages()
	
	elif current_state == ConnectionState.RECONNECTING:
		# 自动重连逻辑
		pass

func connect_to_server(ip: String = "", port: int = 0) -> bool:
	"""连接到游戏服务器"""
	if ip != "":
		server_ip = ip
	if port > 0:
		server_port = port
	
	print("\n========== 尝试连接服务器 ==========")
	print("目标服务器: ", server_ip, ":", server_port)
	
	if current_state == ConnectionState.CONNECTING:
		print("⚠ 已经在连接中...")
		return false
	
	set_state(ConnectionState.CONNECTING)
	connection_attempt += 1
	last_connection_time = Time.get_ticks_msec()
	
	var error = tcp_peer.connect_to_host(server_ip, server_port)
	
	if error != OK:
		print("✗ 连接失败 (错误码: ", error, ")")
		set_state(ConnectionState.ERROR)
		emit_signal("connection_failed", "无法连接到服务器")
		return false
	
	print("✓ 连接请求已发送...")
	
	# 等待连接建立
	await get_tree().create_timer(0.5).timeout
	
	if tcp_peer.is_connected_to_host():
		print("✓ 连接已建立!")
		set_state(ConnectionState.CONNECTED)
		is_connected = true
		connection_attempt = 0
		emit_signal("connection_established")
		return true
	else:
		print("✗ 连接超时")
		set_state(ConnectionState.ERROR)
		emit_signal("connection_failed", "连接超时")
		return false

func disconnect_from_server() -> void:
	"""断开与服务器的连接"""
	if current_state != ConnectionState.DISCONNECTED:
		print("========== 断开服务器连接 ==========")
		
		# 发送断开消息
		send_disconnect_message()
		
		tcp_peer.disconnect_from_host()
		set_state(ConnectionState.DISCONNECTED)
		is_connected = false
		other_players.clear()
		
		print("✓ 已断开连接")
		emit_signal("connection_lost")

func send_message(message_type: int, data: Dictionary = {}) -> bool:
	"""发送消息给服务器"""
	if not is_connected:
		print("⚠ 未连接到服务器，无法发送消息")
		return false
	
	var message = {
		"type": message_type,
		"sender_id": current_player_id,
		"timestamp": Time.get_ticks_msec(),
		"data": data
	}
	
	var json_string = JSON.stringify(message)
	var message_bytes = json_string.to_utf8_buffer()
	
	# 添加消息长度前缀
	var length_bytes = PackedByteArray()
	length_bytes.encode_u32(0, message_bytes.size())
	
	var full_message = length_bytes + message_bytes
	
	var error = tcp_peer.put_data(full_message)
	
	if error != OK:
		print("✗ 消息发送失败 (错误码: ", error, ")")
		emit_signal("network_error", "消息发送失败")
		return false
	
	return true

func process_incoming_messages() -> void:
	"""处理接收到的消息"""
	while tcp_peer.get_available_bytes() > 0:
		# 读取消息长度
		if tcp_peer.get_available_bytes() < 4:
			break
		
		var length_bytes = tcp_peer.get_data(4)
		var message_length = length_bytes.decode_u32(0)
		
		# 读取消息内容
		if tcp_peer.get_available_bytes() < message_length:
			break
		
		var message_bytes = tcp_peer.get_data(message_length)
		var message_string = message_bytes.get_string_from_utf8()
		
		try_parse_message(message_string)

func try_parse_message(json_string: String) -> void:
	"""尝试解析消息"""
	var json = JSON.new()
	var error = json.parse_string(json_string)
	
	if error is String:
		print("✗ 消息解析失败: ", error)
		return
	
	var message = error
	handle_message(message)

func handle_message(message: Dictionary) -> void:
	"""处理接收到的消息"""
	if not ("type" in message):
		return
	
	var msg_type = message.type
	var data = message.get("data", {})
	
	match msg_type:
		0:  # CONNECT_RESPONSE
			handle_connect_response(data)
		1:  # PLAYER_JOINED
			handle_player_joined(data)
		2:  # PLAYER_LEFT
			handle_player_left(data)
		3:  # GAME_STATE_UPDATE
			handle_game_state_update(data)
		7:  # HEARTBEAT_RESPONSE
			handle_heartbeat_response(data)
		_:
			emit_signal("message_received", msg_type, data)

func handle_connect_response(data: Dictionary) -> void:
	"""处理连接响应"""
	current_player_id = data.get("player_id", "")
	session_id = data.get("session_id", "")
	print("✓ 连接成功! 玩家ID: ", current_player_id)

func handle_player_joined(data: Dictionary) -> void:
	"""处理玩家加入"""
	var player_id = data.get("player_id", "")
	var player_data = data.get("player_data", {})
	
	other_players[player_id] = player_data
	print("✓ 玩家加入: ", player_id)
	emit_signal("player_joined", player_id, player_data)

func handle_player_left(data: Dictionary) -> void:
	"""处理玩家离开"""
	var player_id = data.get("player_id", "")
	
	if player_id in other_players:
		other_players.erase(player_id)
	
	print("✓ 玩家离开: ", player_id)
	emit_signal("player_left", player_id)

func handle_game_state_update(data: Dictionary) -> void:
	"""处理游戏状态更新"""
	# 将由GameStateSynchronizer处理
	emit_signal("message_received", 3, data)

func handle_heartbeat_response(data: Dictionary) -> void:
	"""处理心跳响应"""
	var latency = Time.get_ticks_msec() - data.get("timestamp", 0)
	# print("📊 网络延迟: ", latency, "ms")

func send_heartbeat() -> void:
	"""发送心跳消息"""
	send_message(7, {"timestamp": Time.get_ticks_msec()})

func send_disconnect_message() -> void:
	"""发送断开消息"""
	send_message(5, {"player_id": current_player_id})

func broadcast_to_other_players(message_type: int, data: Dictionary) -> void:
	"""广播消息给其他所有玩家"""
	data["broadcast"] = true
	send_message(message_type, data)

func add_player(player_id: String, player_data: Dictionary) -> void:
	"""添加本地玩家数据"""
	local_player_data = player_data
	local_player_data["id"] = player_id
	print("✓ 玩家信息已设置: ", player_id)

func get_all_connected_players() -> Array:
	"""获取所有已连接的玩家"""
	var players = []
	for player_id in other_players.keys():
		players.append({
			"id": player_id,
			"data": other_players[player_id]
		})
	return players

func is_player_connected(player_id: String) -> bool:
	"""检查玩家是否已连接"""
	return player_id in other_players or player_id == current_player_id

func get_player_count() -> int:
	"""获取当前连接的玩家数量"""
	return other_players.size() + 1  # +1 包括本地玩家

func set_state(new_state: int) -> void:
	"""设置网络状态"""
	if current_state != new_state:
		current_state = new_state
		print("🌐 网络状态: ", ConnectionState.keys()[new_state])

func get_connection_info() -> Dictionary:
	"""获取连接信息"""
	return {
		"is_connected": is_connected,
		"current_state": current_state,
		"player_id": current_player_id,
		"player_count": get_player_count(),
		"other_players": other_players.size(),
		"server": server_ip + ":" + str(server_port)
	}

func print_network_status() -> void:
	"""打印网络状态"""
	print("\n========== 网络状态 ==========")
	print("连接状态: ", is_connected)
	print("玩家ID: ", current_player_id)
	print("其他玩家: ", other_players.size())
	print("总玩家数: ", get_player_count())
	print("服务器: ", server_ip, ":", server_port)
	print("==============================\n")
