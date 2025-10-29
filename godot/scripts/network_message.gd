# 网络消息 - 定义消息类型和序列化
class_name NetworkMessage

# 消息类型
enum MessageType {
	# 连接相关
	CONNECT = "CONNECT",
	CONNECT_ACK = "CONNECT_ACK",
	DISCONNECT = "DISCONNECT",
	
	# 房间相关
	CREATE_ROOM = "CREATE_ROOM",
	JOIN_ROOM = "JOIN_ROOM",
	LEAVE_ROOM = "LEAVE_ROOM",
	ROOM_STATE = "ROOM_STATE",
	
	# 玩家相关
	PLAYER_JOINED = "PLAYER_JOINED",
	PLAYER_LEFT = "PLAYER_LEFT",
	PLAYER_STATE = "PLAYER_STATE",
	
	# 游戏相关
	GAME_START = "GAME_START",
	PLAY_CARD = "PLAY_CARD",
	DRAW_CARD = "DRAW_CARD",
	WIN = "WIN",
	GAME_END = "GAME_END",
	
	# 其他
	CHAT = "CHAT",
	PING = "PING",
	PONG = "PONG",
	ERROR = "ERROR"
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
	var type: String
	var player_id: String
	var room_id: String
	var timestamp: int
	var id: int
	var data: Dictionary
	
	func _init(msg_type: String, player_id: String = "", room_id: String = "", data: Dictionary = {}) -> void:
		self.type = msg_type
		self.player_id = player_id
		self.room_id = room_id
		self.timestamp = Time.get_ticks_msec()
		self.id = randi()
		self.data = data
	
	# 转换为字典
	func to_dict() -> Dictionary:
		return {
			"type": type,
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
		if type.is_empty():
			return false
		if type not in MessageType:
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
	var json = JSON.new()
	var error = json.parse(json_string)
	
	if error != OK:
		print("[NetworkMessage] JSON 解析失败")
		return null
	
	var dict = json.get_data()
	if dict is Dictionary:
		return dict_to_message(dict)
	
	return null

static func dict_to_message(dict: Dictionary) -> Message:
	var msg_type = dict.get("type", "")
	var player_id = dict.get("player_id", "")
	var room_id = dict.get("room_id", "")
	var data = dict.get("data", {})
	
	var message = Message.new(msg_type, player_id, room_id, data)
	message.timestamp = dict.get("timestamp", Time.get_ticks_msec())
	message.id = dict.get("id", randi())
	
	return message

# 获取消息类型名称
static func get_message_type_name(msg_type: String) -> String:
	match msg_type:
		MessageType.CONNECT:
			return "连接"
		MessageType.CONNECT_ACK:
			return "连接确认"
		MessageType.DISCONNECT:
			return "断开连接"
		MessageType.CREATE_ROOM:
			return "创建房间"
		MessageType.JOIN_ROOM:
			return "加入房间"
		MessageType.LEAVE_ROOM:
			return "离开房间"
		MessageType.PLAYER_JOINED:
			return "玩家加入"
		MessageType.PLAYER_LEFT:
			return "玩家离开"
		MessageType.PLAY_CARD:
			return "出牌"
		MessageType.WIN:
			return "胜牌"
		MessageType.CHAT:
			return "聊天"
		MessageType.PING:
			return "心跳"
		MessageType.PONG:
			return "心跳响应"
		MessageType.ERROR:
			return "错误"
		_:
			return "未知"

# 获取错误代码名称
static func get_error_name(error_code: int) -> String:
	match error_code:
		ErrorCode.SUCCESS:
			return "成功"
		ErrorCode.INVALID_MESSAGE:
			return "无效消息"
		ErrorCode.UNAUTHORIZED:
			return "未授权"
		ErrorCode.ROOM_NOT_FOUND:
			return "房间不存在"
		ErrorCode.PLAYER_NOT_FOUND:
			return "玩家不存在"
		ErrorCode.INVALID_STATE:
			return "无效状态"
		ErrorCode.SERVER_ERROR:
			return "服务器错误"
		_:
			return "未知错误"

# 验证消息字段
static func validate_message(message: Message) -> Dictionary:
	if not message.is_valid():
		return {
			"valid": false,
			"error": "消息类型无效"
		}
	
	# 根据消息类型进行特定的验证
	match message.type:
		MessageType.CONNECT:
			if message.player_id.is_empty():
				return {"valid": false, "error": "玩家ID不能为空"}
		MessageType.JOIN_ROOM:
			if message.player_id.is_empty():
				return {"valid": false, "error": "玩家ID不能为空"}
			if message.room_id.is_empty():
				return {"valid": false, "error": "房间ID不能为空"}
		MessageType.PLAY_CARD:
			if message.player_id.is_empty():
				return {"valid": false, "error": "玩家ID不能为空"}
			if not "suit" in message.data or not "number" in message.data:
				return {"valid": false, "error": "卡牌信息不完整"}
	
	return {"valid": true}

# 打印消息信息
static func print_message(message: Message) -> void:
	print("[Message] %s (ID: %s) - %s" % [
		get_message_type_name(message.type),
		message.id,
		message.player_id
	])
