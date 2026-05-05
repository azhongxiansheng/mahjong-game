# 网络消息 - 定义消息类型和序列化
class_name NetworkMessage

# 消息类型 - 使用整数枚举
enum MessageType {
	# 连接相关
	CONNECT = 0,
	CONNECT_ACK = 1,
	DISCONNECT = 2,

	# 房间相关
	CREATE_ROOM = 3,
	JOIN_ROOM = 4,
	LEAVE_ROOM = 5,
	ROOM_STATE = 6,

	# 玩家相关
	PLAYER_JOINED = 7,
	PLAYER_LEFT = 8,
	PLAYER_STATE = 9,

	# 游戏相关
	GAME_START = 10,
	PLAY_CARD = 11,
	DRAW_CARD = 12,
	WIN = 13,
	GAME_END = 14,

	# 其他
	CHAT = 15,
	PING = 16,
	PONG = 17,
	ERROR = 18
}

# 消息类型名称映射
const MESSAGE_TYPE_NAMES = {
	0: "CONNECT",
	1: "CONNECT_ACK",
	2: "DISCONNECT",
	3: "CREATE_ROOM",
	4: "JOIN_ROOM",
	5: "LEAVE_ROOM",
	6: "ROOM_STATE",
	7: "PLAYER_JOINED",
	8: "PLAYER_LEFT",
	9: "PLAYER_STATE",
	10: "GAME_START",
	11: "PLAY_CARD",
	12: "DRAW_CARD",
	13: "WIN",
	14: "GAME_END",
	15: "CHAT",
	16: "PING",
	17: "PONG",
	18: "ERROR"
}

# 错误代码
enum ErrorCode {
	UNKNOWN = -1,
	SUCCESS = 0,
	INVALID_MESSAGE = 1,
	UNAUTHORIZED = 2,
	ROOM_NOT_FOUND = 3,
	PLAYER_NOT_FOUND = 4,
	INVALID_STATE = 5,
	SERVER_ERROR = 6
}

# 消息结构
class Message:
	var type: int
	var player_id: String
	var room_id: String
	var timestamp: int
	var id: int
	var data: Dictionary

	func _init(msg_type: int, player_id: String = "", room_id: String = "", data: Dictionary = {}) -> void:
		self.type = msg_type
		self.player_id = player_id
		self.room_id = room_id
		self.timestamp = Time.get_ticks_msec()
		self.id = randi()
		self.data = data

	# 转换为字典
	func to_dict() -> Dictionary:
		return {
			"type": MESSAGE_TYPE_NAMES.get(type, "UNKNOWN"),
			"player_id": player_id,
			"room_id": room_id,
			"timestamp": timestamp,
			"id": id,
			"data": data
		}

	# 转换为 JSON 字符串
	func to_json() -> String:
		return JSON.stringify(to_dict())

	# 验证消息有效性
	func is_valid() -> bool:
		if type < 0 or type > 18:
			return false
		if player_id.is_empty() and type != MessageType.ERROR:
			return false
		return true

# 静态方法 - 创建消息
static func create_connect_message(player_id: String) -> Message:
	return Message.new(MessageType.CONNECT, player_id, "", {})

static func create_disconnect_message(player_id: String, room_id: String) -> Message:
	return Message.new(MessageType.DISCONNECT, player_id, room_id, {})

static func create_join_room_message(player_id: String, room_id: String) -> Message:
	return Message.new(MessageType.JOIN_ROOM, player_id, room_id, {})

static func create_leave_room_message(player_id: String, room_id: String) -> Message:
	return Message.new(MessageType.LEAVE_ROOM, player_id, room_id, {})

static func create_play_card_message(player_id: String, room_id: String, card_data: Dictionary) -> Message:
	return Message.new(MessageType.PLAY_CARD, player_id, room_id, card_data)

static func create_win_message(player_id: String, room_id: String, win_data: Dictionary) -> Message:
	return Message.new(MessageType.WIN, player_id, room_id, win_data)

static func create_chat_message(player_id: String, room_id: String, text: String) -> Message:
	return Message.new(MessageType.CHAT, player_id, room_id, {"text": text})

static func create_ping_message(player_id: String) -> Message:
	return Message.new(MessageType.PING, player_id, "", {"timestamp": Time.get_ticks_msec()})

static func create_error_message(error_code: int, error_message: String) -> Message:
	return Message.new(MessageType.ERROR, "", "", {
		"code": error_code,
		"message": error_message
	})

# 静态方法 - 解析消息
static func parse_message(json_string: String) -> Message:
	var dict = JSON.parse_string(json_string)
	if dict == null:
		return null
	return dict_to_message(dict)

static func dict_to_message(dict: Dictionary) -> Message:
	var type_name = dict.get("type", "ERROR")
	var type_value = MessageType.ERROR

	# 查找类型值
	for key in MESSAGE_TYPE_NAMES.keys():
		if MESSAGE_TYPE_NAMES[key] == type_name:
			type_value = key
			break

	var msg = Message.new(
		type_value,
		dict.get("player_id", ""),
		dict.get("room_id", ""),
		dict.get("data", {})
	)
	msg.timestamp = dict.get("timestamp", 0)
	msg.id = dict.get("id", 0)
	return msg

static func get_message_type_name(msg_type: int) -> String:
	return MESSAGE_TYPE_NAMES.get(msg_type, "UNKNOWN")

static func get_error_name(error_code: int) -> String:
	match error_code:
		ErrorCode.SUCCESS:
			return "SUCCESS"
		ErrorCode.INVALID_MESSAGE:
			return "INVALID_MESSAGE"
		ErrorCode.UNAUTHORIZED:
			return "UNAUTHORIZED"
		ErrorCode.ROOM_NOT_FOUND:
			return "ROOM_NOT_FOUND"
		ErrorCode.PLAYER_NOT_FOUND:
			return "PLAYER_NOT_FOUND"
		ErrorCode.INVALID_STATE:
			return "INVALID_STATE"
		ErrorCode.SERVER_ERROR:
			return "SERVER_ERROR"
		_:
			return "UNKNOWN"

static func validate_message(message: Message) -> Dictionary:
	if not message.is_valid():
		return {
			"valid": false,
			"error": "Invalid message format"
		}
	return {
		"valid": true,
		"error": ""
	}

static func print_message(message: Message) -> void:
	print("[NetworkMessage] 类型: %s, 玩家: %s, 房间: %s, 数据: %s" % [
		MESSAGE_TYPE_NAMES.get(message.type, "UNKNOWN"),
		message.player_id,
		message.room_id,
		message.data
	])
