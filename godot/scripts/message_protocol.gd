class_name MessageProtocol
extends Node

# 消息类型定义
enum MessageType {
	CONNECT_REQUEST = 0,
	CONNECT_RESPONSE = 1,
	PLAYER_ACTION = 2,
	GAME_STATE_UPDATE = 3,
	CHAT_MESSAGE = 4,
	DISCONNECT = 5,
	HEARTBEAT = 6,
	HEARTBEAT_RESPONSE = 7,
	ERROR = 8
}

# 消息类
class Message:
	var type: int
	var sender_id: String
	var timestamp: float
	var data: Dictionary
	var sequence_id: int = 0
	
	func _init(p_type: int, p_sender_id: String = "", p_data: Dictionary = {}) -> void:
		type = p_type
		sender_id = p_sender_id
		timestamp = Time.get_ticks_msec()
		data = p_data
	
	func to_dict() -> Dictionary:
		return {
			"type": type,
			"sender_id": sender_id,
			"timestamp": timestamp,
			"data": data,
			"sequence_id": sequence_id
		}

# 静态消息计数器
var message_counter: int = 0

func _ready() -> void:
	print("========== 消息协议系统初始化 ==========")
	print("✓ MessageProtocol已初始化")

func create_message(msg_type: int, sender_id: String = "", data: Dictionary = {}) -> Message:
	"""创建新消息"""
	var msg = Message.new(msg_type, sender_id, data)
	msg.sequence_id = message_counter
	message_counter += 1
	return msg

func serialize_message(msg: Message) -> String:
	"""序列化消息为JSON字符串"""
	var msg_dict = msg.to_dict()
	return JSON.stringify(msg_dict)

func deserialize_message(json_string: String) -> Message:
	"""从JSON字符串反序列化消息"""
	var json = JSON.new()
	var parsed = json.parse_string(json_string)
	
	if parsed is String:
		print("✗ 消息解析失败: ", parsed)
		return null
	
	if parsed is Dictionary:
		var msg_dict = parsed
		var msg = Message.new(
			msg_dict.get("type", 0),
			msg_dict.get("sender_id", ""),
			msg_dict.get("data", {})
		)
		msg.timestamp = msg_dict.get("timestamp", 0.0)
		msg.sequence_id = msg_dict.get("sequence_id", 0)
		return msg
	
	return null

func validate_message(msg: Message) -> bool:
	"""验证消息有效性"""
	if msg == null:
		return false
	
	# 检查消息类型有效性
	if msg.type < 0 or msg.type > 8:
		print("✗ 无效的消息类型: ", msg.type)
		return false
	
	# 检查时间戳有效性
	if msg.timestamp <= 0:
		print("✗ 无效的时间戳: ", msg.timestamp)
		return false
	
	return true

func create_connect_request(player_name: String = "玩家") -> Message:
	"""创建连接请求消息"""
	var data = {
		"player_name": player_name,
		"version": "0.5.0",
		"client_id": str(randi())
	}
	return create_message(MessageType.CONNECT_REQUEST, "", data)

func create_connect_response(player_id: String, session_id: String) -> Message:
	"""创建连接响应消息"""
	var data = {
		"player_id": player_id,
		"session_id": session_id,
		"status": "success"
	}
	return create_message(MessageType.CONNECT_RESPONSE, player_id, data)

func create_player_action(player_id: String, action_type: String, action_data: Dictionary) -> Message:
	"""创建玩家操作消息"""
	var data = {
		"action_type": action_type,
		"action_data": action_data
	}
	return create_message(MessageType.PLAYER_ACTION, player_id, data)

func create_game_state_update(player_id: String, state_data: Dictionary) -> Message:
	"""创建游戏状态更新消息"""
	return create_message(MessageType.GAME_STATE_UPDATE, player_id, state_data)

func create_chat_message(player_id: String, chat_text: String) -> Message:
	"""创建聊天消息"""
	var data = {
		"text": chat_text,
		"player_id": player_id
	}
	return create_message(MessageType.CHAT_MESSAGE, player_id, data)

func create_disconnect_message(player_id: String) -> Message:
	"""创建断开消息"""
	var data = {
		"player_id": player_id,
		"reason": "玩家主动断开"
	}
	return create_message(MessageType.DISCONNECT, player_id, data)

func create_heartbeat(player_id: String = "") -> Message:
	"""创建心跳消息"""
	var data = {
		"timestamp": Time.get_ticks_msec()
	}
	return create_message(MessageType.HEARTBEAT, player_id, data)

func create_heartbeat_response(player_id: String, original_timestamp: float) -> Message:
	"""创建心跳响应"""
	var data = {
		"timestamp": original_timestamp,
		"response_time": Time.get_ticks_msec()
	}
	return create_message(MessageType.HEARTBEAT_RESPONSE, player_id, data)

func create_error_message(error_text: String) -> Message:
	"""创建错误消息"""
	var data = {
		"error": error_text,
		"error_time": Time.get_ticks_msec()
	}
	return create_message(MessageType.ERROR, "", data)

func get_message_type_name(msg_type: int) -> String:
	"""获取消息类型名称"""
	match msg_type:
		MessageType.CONNECT_REQUEST:
			return "连接请求"
		MessageType.CONNECT_RESPONSE:
			return "连接响应"
		MessageType.PLAYER_ACTION:
			return "玩家操作"
		MessageType.GAME_STATE_UPDATE:
			return "游戏状态"
		MessageType.CHAT_MESSAGE:
			return "聊天消息"
		MessageType.DISCONNECT:
			return "断开消息"
		MessageType.HEARTBEAT:
			return "心跳"
		MessageType.HEARTBEAT_RESPONSE:
			return "心跳响应"
		MessageType.ERROR:
			return "错误"
		_:
			return "未知"

func print_message_info(msg: Message) -> void:
	"""打印消息信息"""
	if msg == null:
		print("消息为空")
		return
	
	print("\n========== 消息信息 ==========")
	print("类型: ", get_message_type_name(msg.type))
	print("发送者: ", msg.sender_id)
	print("时间戳: ", msg.timestamp)
	print("序列号: ", msg.sequence_id)
	print("数据: ", msg.data)
	print("=============================\n")
