# 网络客户端 - 处理高级客户端逻辑
class_name NetworkClient
extends Node

# 客户端状态
enum ClientState {
	IDLE = 0,
	CONNECTING = 1,
	CONNECTED = 2,
	IN_ROOM = 3,
	IN_GAME = 4
}

var network_manager: NetworkManager
var state: ClientState = ClientState.IDLE
var player_id: String = ""
var room_id: String = ""
var current_room: Dictionary = {}
var other_players: Dictionary = {}

# 信号
signal client_connected()
signal client_disconnected()
signal room_joined(room_info: Dictionary)
signal room_left()
signal game_started()
signal game_ended(result: Dictionary)
signal player_action_received(player_id: String, action: Dictionary)
signal error_occurred(error_code: int, error_message: String)

func _ready() -> void:
	network_manager = NetworkManager.new()
	add_child(network_manager)
	
	# 连接网络管理器的信号
	network_manager.connected.connect(_on_network_connected)
	network_manager.disconnected.connect(_on_network_disconnected)
	network_manager.message_received.connect(_on_message_received)
	network_manager.error_occurred.connect(_on_network_error)
	
	print("[NetworkClient] 初始化完成")

# 连接到服务器
func connect_to_server() -> bool:
	if state != ClientState.IDLE:
		print("[NetworkClient] 已连接或正在连接")
		return false
	
	state = ClientState.CONNECTING
	return network_manager.connect_to_server()

# 断开连接
func disconnect_from_server() -> void:
	if state == ClientState.IDLE:
		return
	
	# 发送断开消息
	if room_id != "":
		leave_room()
	
	network_manager.disconnect_from_server()
	state = ClientState.IDLE
	client_disconnected.emit()

# 创建房间
func create_room(room_name: String, max_players: int = 4) -> bool:
	if state != ClientState.CONNECTED:
		print("[NetworkClient] 未连接")
		return false
	
	var data = {
		"room_name": room_name,
		"max_players": max_players
	}
	
	network_manager.send_message(NetworkMessage.MessageType.CREATE_ROOM, data)
	return true

# 加入房间
func join_room(room_id_param: String) -> bool:
	if state != ClientState.CONNECTED:
		print("[NetworkClient] 未连接")
		return false
	
	room_id = room_id_param
	var msg = NetworkMessage.create_join_room_message(player_id, room_id)
	network_manager.send_message(msg.type, msg.data)
	return true

# 离开房间
func leave_room() -> bool:
	if state != ClientState.IN_ROOM and state != ClientState.IN_GAME:
		return false
	
	var msg = NetworkMessage.create_leave_room_message(player_id, room_id)
	network_manager.send_message(msg.type, msg.data)
	
	room_id = ""
	state = ClientState.CONNECTED
	room_left.emit()
	return true

# 出牌
func play_card(card: CardData) -> bool:
	if state != ClientState.IN_GAME:
		print("[NetworkClient] 游戏未进行中")
		return false
	
	var card_data = {
		"suit": card.suit,
		"number": card.number
	}
	
	var msg = NetworkMessage.create_play_card_message(player_id, room_id, card_data)
	network_manager.send_message(msg.type, msg.data)
	return true

# 宣布胜牌
func declare_win(win_data: Dictionary) -> bool:
	if state != ClientState.IN_GAME:
		return false
	
	var msg = NetworkMessage.create_win_message(player_id, room_id, win_data)
	network_manager.send_message(msg.type, msg.data)
	return true

# 发送聊天消息
func send_chat_message(text: String) -> bool:
	if state < ClientState.CONNECTED:
		return false
	
	var msg = NetworkMessage.create_chat_message(player_id, room_id, text)
	network_manager.send_message(msg.type, msg.data)
	return true

# 网络连接成功
func _on_network_connected() -> void:
	print("[NetworkClient] 网络已连接")
	state = ClientState.CONNECTED
	client_connected.emit()

# 网络断开连接
func _on_network_disconnected() -> void:
	print("[NetworkClient] 网络已断开")
	state = ClientState.IDLE

# 处理接收的消息
func _on_message_received(message: Dictionary) -> void:
	var msg_type = message.get("type", "")
	var data = message.get("data", {})
	
	match msg_type:
		NetworkMessage.MessageType.ROOM_STATE:
			_handle_room_state(data)
		NetworkMessage.MessageType.PLAYER_JOINED:
			_handle_player_joined(data)
		NetworkMessage.MessageType.PLAYER_LEFT:
			_handle_player_left(data)
		NetworkMessage.MessageType.GAME_START:
			_handle_game_start(data)
		NetworkMessage.MessageType.PLAY_CARD:
			_handle_player_action(message.get("player_id", ""), data)
		NetworkMessage.MessageType.WIN:
			_handle_win(data)
		NetworkMessage.MessageType.GAME_END:
			_handle_game_end(data)
		NetworkMessage.MessageType.CHAT:
			_handle_chat(message.get("player_id", ""), data)

# 处理房间状态更新
func _handle_room_state(data: Dictionary) -> void:
	current_room = data
	other_players = data.get("players", {})
	
	if state == ClientState.CONNECTED:
		state = ClientState.IN_ROOM
		room_joined.emit(current_room)

# 处理玩家加入
func _handle_player_joined(data: Dictionary) -> void:
	var joined_player_id = data.get("player_id", "")
	other_players[joined_player_id] = data
	print("[NetworkClient] 玩家加入: %s" % joined_player_id)

# 处理玩家离开
func _handle_player_left(data: Dictionary) -> void:
	var left_player_id = data.get("player_id", "")
	if left_player_id in other_players:
		other_players.erase(left_player_id)
	print("[NetworkClient] 玩家离开: %s" % left_player_id)

# 处理游戏开始
func _handle_game_start(data: Dictionary) -> void:
	state = ClientState.IN_GAME
	game_started.emit()

# 处理玩家操作
func _handle_player_action(player_id: String, action: Dictionary) -> void:
	player_action_received.emit(player_id, action)

# 处理胜牌
func _handle_win(data: Dictionary) -> void:
	print("[NetworkClient] 玩家胜牌: %s" % data.get("player_id", ""))

# 处理游戏结束
func _handle_game_end(data: Dictionary) -> void:
	state = ClientState.IN_ROOM
	game_ended.emit(data)

# 处理聊天消息
func _handle_chat(player_id: String, data: Dictionary) -> void:
	print("[NetworkClient] [%s]: %s" % [player_id, data.get("text", "")])

# 处理网络错误
func _on_network_error(error_code: int, error_message: String) -> void:
	print("[NetworkClient] 网络错误: %d - %s" % [error_code, error_message])
	error_occurred.emit(error_code, error_message)

# 获取客户端状态
func get_state_string() -> String:
	match state:
		ClientState.IDLE:
			return "空闲"
		ClientState.CONNECTING:
			return "连接中"
		ClientState.CONNECTED:
			return "已连接"
		ClientState.IN_ROOM:
			return "在房间中"
		ClientState.IN_GAME:
			return "游戏中"
		_:
			return "未知"

# 打印客户端状态
func print_status() -> void:
	print("\n=== 网络客户端状态 ===")
	print("状态: %s" % get_state_string())
	print("玩家ID: %s" % player_id)
	print("房间ID: %s" % room_id)
	print("其他玩家: %d" % other_players.size())
