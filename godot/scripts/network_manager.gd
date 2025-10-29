# 网络管理器 - 处理网络连接和通信
class_name NetworkManager
extends Node

# 网络状态
enum NetworkState {
	DISCONNECTED = 0,
	CONNECTING = 1,
	CONNECTED = 2,
	RECONNECTING = 3,
	ERROR = 4
}

# 网络配置
const SERVER_URL = "ws://localhost:8080"
const RECONNECT_DELAY = 5.0
const MAX_RECONNECT_ATTEMPTS = 5
const MESSAGE_TIMEOUT = 30.0

# 网络状态
var state: NetworkState = NetworkState.DISCONNECTED
var websocket: WebSocketPeer
var player_id: String = ""
var room_id: String = ""
var reconnect_attempts: int = 0

# 消息队列
var message_queue: Array = []
var pending_messages: Dictionary = {}
var message_id_counter: int = 0

# 信号
signal connected()
signal disconnected()
signal message_received(message: Dictionary)
signal error_occurred(error_code: int, error_message: String)
signal reconnecting(attempt: int)

func _ready() -> void:
	set_process(true)
	print("[NetworkManager] 初始化完成")

func _process(delta: float) -> void:
	if websocket and websocket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		websocket.poll()

		# 处理接收的消息
		while websocket.get_available_packet_count() > 0:
			_handle_received_message()

	# 清理超时消息
	_cleanup_timeout_messages(delta)

# 连接到服务器
func connect_to_server() -> bool:
	if state != NetworkState.DISCONNECTED:
		print("[NetworkManager] 已经在连接或已连接")
		return false

	print("[NetworkManager] 正在连接到 %s" % SERVER_URL)
	state = NetworkState.CONNECTING

	websocket = WebSocketPeer.new()
	var error = websocket.connect_to_url(SERVER_URL)

	if error != OK:
		print("[NetworkManager] 连接失败: %d" % error)
		state = NetworkState.ERROR
		error_occurred.emit(error, "Failed to connect")
		return false

	return true

# 断开连接
func disconnect_from_server() -> void:
	if websocket:
		websocket.close()
	state = NetworkState.DISCONNECTED
	reconnect_attempts = 0
	print("[NetworkManager] 已断开连接")

# 发送消息
func send_message(message_type: String, data: Dictionary = {}) -> int:
	var message = {
		"type": message_type,
		"player_id": player_id,
		"room_id": room_id,
		"timestamp": Time.get_ticks_msec(),
		"id": message_id_counter,
		"data": data
	}

	message_id_counter += 1

	if state == NetworkState.CONNECTED and websocket:
		var json_str = JSON.stringify(message)
		var error = websocket.send_text(json_str)

		if error != OK:
			print("[NetworkManager] 发送消息失败: %d" % error)
			return -1

		# 跟踪待处理消息
		pending_messages[message["id"]] = {
			"type": message_type,
			"timestamp": Time.get_ticks_msec(),
			"timeout": MESSAGE_TIMEOUT
		}

		return message["id"]
	else:
		print("[NetworkManager] 未连接，消息入队")
		message_queue.append(message)
		return -1

# 处理接收的消息
func _handle_received_message() -> void:
	if not websocket:
		return

	var packet = websocket.get_message()
	if packet == null:
		return

	var json = JSON.new()
	var parse_error = json.parse(packet)

	if parse_error != OK:
		print("[NetworkManager] JSON 解析失败")
		return

	var message = json.get_data()

	# 根据消息类型处理
	match message.get("type", ""):
		"CONNECT_ACK":
			_on_connect_ack(message)
		"MESSAGE":
			message_received.emit(message)
		"ERROR":
			_on_error_message(message)
		"PONG":
			_on_pong(message)
		_:
			print("[NetworkManager] 未知消息类型: %s" % message.get("type", ""))

# 连接确认
func _on_connect_ack(message: Dictionary) -> void:
	print("[NetworkManager] 连接成功")
	state = NetworkState.CONNECTED
	player_id = message.get("player_id", "")
	reconnect_attempts = 0
	connected.emit()

	# 发送待处理消息
	_send_queued_messages()

# 错误消息处理
func _on_error_message(message: Dictionary) -> void:
	var error_code = message.get("code", -1)
	var error_msg = message.get("message", "Unknown error")
	print("[NetworkManager] 服务器错误: %d - %s" % [error_code, error_msg])
	error_occurred.emit(error_code, error_msg)

# 心跳响应
func _on_pong(message: Dictionary) -> void:
	pass

# 发送排队的消息
func _send_queued_messages() -> void:
	for message in message_queue:
		var json_str = JSON.stringify(message)
		websocket.send_text(json_str)
	message_queue.clear()

# 清理超时消息
func _cleanup_timeout_messages(delta: float) -> void:
	var to_remove = []
	for msg_id in pending_messages:
		pending_messages[msg_id]["timeout"] -= delta
		if pending_messages[msg_id]["timeout"] < 0:
			to_remove.append(msg_id)

	for msg_id in to_remove:
		print("[NetworkManager] 消息 %d 超时" % msg_id)
		pending_messages.erase(msg_id)

# 获取连接状态
func check_connected() -> bool:
	return state == NetworkState.CONNECTED

# 获取网络状态字符串
func get_state_string() -> String:
	match state:
		NetworkState.DISCONNECTED:
			return "已断开"
		NetworkState.CONNECTING:
			return "连接中"
		NetworkState.CONNECTED:
			return "已连接"
		NetworkState.RECONNECTING:
			return "重新连接中"
		NetworkState.ERROR:
			return "错误"
		_:
			return "未知"

# 心跳检测
func send_heartbeat() -> void:
	send_message("PING", {})

# 调试信息
func print_status() -> void:
	print("\n=== 网络管理器状态 ===")
	print("连接状态: %s" % get_state_string())
	print("玩家ID: %s" % player_id)
	print("房间ID: %s" % room_id)
	print("待处理消息: %d" % pending_messages.size())
	print("消息队列: %d" % message_queue.size())
