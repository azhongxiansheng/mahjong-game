class_name NetworkMessage

# 网络消息定义类
# 定义所有可能的消息类型和结构

## 消息类型枚举
enum MessageType {
	# 连接相关
	LOGIN,              # 玩家登录
	LOGOUT,             # 玩家登出
	PING,               # 心跳检测
	PONG,               # 心跳响应
	
	# 房间相关
	ROOM_LIST,          # 获取房间列表
	CREATE_ROOM,        # 创建房间
	JOIN_ROOM,          # 加入房间
	LEAVE_ROOM,         # 离开房间
	ROOM_STATE,         # 房间状态更新
	PLAYER_JOINED,      # 玩家加入
	PLAYER_LEFT,        # 玩家离开
	
	# 游戏相关
	GAME_START,         # 游戏开始
	GAME_STATE,         # 游戏状态更新
	PLAYER_ACTION,      # 玩家操作（抽卡、出牌等）
	DEAL_CARDS,         # 分配初始手牌
	DRAW_CARD,          # 抽卡
	DISCARD_CARD,       # 出牌
	HU,                 # 胡牌
	GAME_END,           # 游戏结束
	
	# 其他
	ERROR,              # 错误消息
	ACK,                # 确认消息
}

# 消息结构
class Message:
	var type: MessageType
	var player_id: int
	var room_id: String
	var data: Dictionary
	var timestamp: int
	
	func _init(p_type: MessageType, p_player_id: int = -1, p_room_id: String = "", p_data: Dictionary = {}):
		type = p_type
		player_id = p_player_id
		room_id = p_room_id
		data = p_data
		timestamp = Time.get_ticks_msec()
	
	# 转换为 JSON 字符串
	func to_json() -> String:
		var obj = {
			"type": type,
			"player_id": player_id,
			"room_id": room_id,
			"data": data,
			"timestamp": timestamp
		}
		return JSON.stringify(obj)
	
	# 从 JSON 字符串解析
	static func from_json(json_str: String) -> Message:
		var json = JSON.new()
		if json.parse(json_str) != OK:
			return null
		
		var obj = json.data
		var msg = Message.new(obj.get("type", 0), obj.get("player_id", -1), obj.get("room_id", ""), obj.get("data", {}))
		msg.timestamp = obj.get("timestamp", 0)
		return msg

# 创建特定消息的辅助函数

static func create_login(player_id: int, player_name: String) -> Message:
	"""创建登录消息"""
	return Message.new(MessageType.LOGIN, player_id, "", {"name": player_name})

static func create_room_state(room_id: String, players: Array, state: String) -> Message:
	"""创建房间状态消息"""
	return Message.new(MessageType.ROOM_STATE, -1, room_id, {"players": players, "state": state})

static func create_player_action(player_id: int, room_id: String, action_type: String, action_data: Dictionary) -> Message:
	"""创建玩家操作消息"""
	var data = {"action": action_type}
	data.merge(action_data)
	return Message.new(MessageType.PLAYER_ACTION, player_id, room_id, data)

static func create_discard_card(player_id: int, room_id: String, card: CardData) -> Message:
	"""创建出牌消息"""
	return Message.new(MessageType.DISCARD_CARD, player_id, room_id, {
		"card": {"suit": card.suit, "number": card.number}
	})

static func create_draw_card(player_id: int, room_id: String, card: CardData) -> Message:
	"""创建抽卡消息"""
	return Message.new(MessageType.DRAW_CARD, player_id, room_id, {
		"card": {"suit": card.suit, "number": card.number}
	})

static func create_hu(player_id: int, room_id: String, fan: int, hu_type: String) -> Message:
	"""创建胡牌消息"""
	return Message.new(MessageType.HU, player_id, room_id, {
		"fan": fan,
		"type": hu_type
	})

static func create_error(error_code: int, error_msg: String) -> Message:
	"""创建错误消息"""
	return Message.new(MessageType.ERROR, -1, "", {
		"code": error_code,
		"message": error_msg
	})

static func create_ack(message_timestamp: int) -> Message:
	"""创建确认消息"""
	return Message.new(MessageType.ACK, -1, "", {
		"ack_timestamp": message_timestamp
	})

# 获取消息类型名称
static func get_type_name(msg_type: MessageType) -> String:
	"""获取消息类型的字符串名称"""
	match msg_type:
		MessageType.LOGIN: return "LOGIN"
		MessageType.LOGOUT: return "LOGOUT"
		MessageType.ROOM_STATE: return "ROOM_STATE"
		MessageType.PLAYER_ACTION: return "PLAYER_ACTION"
		MessageType.DISCARD_CARD: return "DISCARD_CARD"
		MessageType.HU: return "HU"
		MessageType.ERROR: return "ERROR"
		_: return "UNKNOWN"
