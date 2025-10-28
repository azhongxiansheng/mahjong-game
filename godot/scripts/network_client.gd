class_name NetworkClient

# 网络客户端类
# 使用 WebSocketPeer 与游戏服务器通信

## 状态枚举
enum ConnectionState {
	DISCONNECTED,   # 未连接
	CONNECTING,     # 连接中
	CONNECTED,      # 已连接
	RECONNECTING,   # 重连中
	FAILED,         # 连接失败
}

var websocket: WebSocketPeer
var server_url: String = "ws://localhost:8080"
var connection_state: ConnectionState = ConnectionState.DISCONNECTED
var player_id: int = -1
var player_name: String = ""

# 消息队列
var message_queue: Array[NetworkMessage.Message] = []
var max_queue_size: int = 100

# 重连相关
var reconnect_attempts: int = 0
var max_reconnect_attempts: int = 5
var reconnect_delay: float = 2.0
var last_reconnect_time: float = 0.0

# 信号
signal connected
signal disconnected
signal message_received(message: NetworkMessage.Message)
signal error(error_msg: String)

func _init(p_server_url: String = "ws://localhost:8080"):
	"""初始化网络客户端"""
	server_url = p_server_url
	websocket = WebSocketPeer.new()

func connect_to_server(p_player_id: int, p_player_name: String) -> bool:
	"""连接到服务器"""
	if connection_state == ConnectionState.CONNECTING or connection_state == ConnectionState.CONNECTED:
		print("NetworkClient: 已在连接状态")
		return false
	
	player_id = p_player_id
	player_name = p_player_name
	connection_state = ConnectionState.CONNECTING
	
	var error_code = websocket.connect_to_url(server_url)
	if error_code != OK:
		print("NetworkClient: 连接失败 - %s" % error_code)
		connection_state = ConnectionState.FAILED
		self.error.emit("连接失败: %s" % error_code)
		return false
	
	print("✓ NetworkClient: 连接中... (%s)" % server_url)
	return true

func disconnect_from_server() -> void:
	"""断开与服务器的连接"""
	if websocket:
		websocket.close()
	connection_state = ConnectionState.DISCONNECTED
	print("✓ NetworkClient: 已断开连接")
	disconnected.emit()

func send_message(message: NetworkMessage.Message) -> bool:
	"""发送消息到服务器"""
	if connection_state != ConnectionState.CONNECTED:
		print("NetworkClient: 未连接，无法发送消息")
		return false
	
	var json_str = message.to_json()
	var send_error = websocket.send_text(json_str)
	if send_error != OK:
		print("NetworkClient: 发送消息失败 - %s" % send_error)
		return false
	
	print("📤 NetworkClient: 发送 %s" % NetworkMessage.get_type_name(message.type))
	return true

func _process(_delta: float) -> void:
	"""每帧处理网络事件"""
	if websocket == null:
		return
	
	websocket.poll()
	
	# 处理 WebSocket 状态
	var state = websocket.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			if connection_state != ConnectionState.CONNECTED:
				connection_state = ConnectionState.CONNECTED
				reconnect_attempts = 0
				print("✓ NetworkClient: 已连接到服务器")
				connected.emit()
				# 发送登录消息
				_send_login()
		
		WebSocketPeer.STATE_CLOSED:
			if connection_state == ConnectionState.CONNECTED or connection_state == ConnectionState.CONNECTING:
				print("✗ NetworkClient: 连接已断开")
				connection_state = ConnectionState.DISCONNECTED
				disconnected.emit()
	
	# 处理接收到的消息
	while websocket.get_available_packet_count() > 0:
		var packet = websocket.get_message()
		if packet is String:
			_handle_message(packet)

# 私有方法

func _send_login() -> void:
	"""发送登录消息"""
	var msg = NetworkMessage.create_login(player_id, player_name)
	send_message(msg)

func _handle_message(json_str: String) -> void:
	"""处理接收到的消息"""
	var message = NetworkMessage.Message.from_json(json_str)
	if message == null:
		print("NetworkClient: 无效的消息格式")
		return
	
	print("📥 NetworkClient: 收到 %s" % NetworkMessage.get_type_name(message.type))
	
	# 添加到消息队列
	if message_queue.size() < max_queue_size:
		message_queue.append(message)
	
	# 发出信号
	message_received.emit(message)

func get_connection_state_name() -> String:
	"""获取连接状态的字符串名称"""
	match connection_state:
		ConnectionState.DISCONNECTED: return "未连接"
		ConnectionState.CONNECTING: return "连接中"
		ConnectionState.CONNECTED: return "已连接"
		ConnectionState.RECONNECTING: return "重连中"
		ConnectionState.FAILED: return "连接失败"
		_: return "未知"

func check_connected() -> bool:
	"""检查是否已连接"""
	return connection_state == ConnectionState.CONNECTED

func get_next_message() -> NetworkMessage.Message:
	"""获取队列中的下一条消息"""
	if message_queue.is_empty():
		return null
	return message_queue.pop_front()

func clear_message_queue() -> void:
	"""清空消息队列"""
	message_queue.clear()

func get_status_string() -> String:
	"""获取客户端状态字符串"""
	return "NetworkClient [%s] - Player:%s (%d)" % [
		get_connection_state_name(),
		player_name,
		player_id
	]
