class_name GameRoom

# 游戏房间类
# 管理房间、玩家和游戏状态

## 房间状态枚举
enum RoomState {
	WAITING, # 等待玩家
	READY, # 准备开始
	PLAYING, # 游戏进行中
	FINISHED, # 游戏结束
	CLOSED, # 房间关闭
}

var room_id: String
var max_players: int = 4
var current_players: Array[String] = [] # 玩家ID列表
var room_state: RoomState = RoomState.WAITING
var created_at: int
var last_activity: int

# 游戏数据
var game_state: GameState
var player_hands: Dictionary = {} # player_id -> CardHand
var discard_pile: Array[CardData] = [] # 弃牌堆
var current_turn: int = 0 # 当前玩家轮次

func _init(p_room_id: String, p_max_players: int = 4):
	"""初始化房间"""
	room_id = p_room_id
	max_players = p_max_players
	created_at = Time.get_ticks_msec()
	last_activity = created_at
	game_state = GameState.new()

func add_player(player_id: String) -> bool:
	"""添加玩家到房间"""
	if current_players.size() >= max_players:
		print("GameRoom: 房间已满")
		return false

	if player_id in current_players:
		print("GameRoom: 玩家已在房间中")
		return false

	current_players.append(player_id)
	player_hands[player_id] = CardHand.new()
	print("✓ GameRoom: 玩家 %s 加入房间 (现有: %d/%d)" % [player_id, current_players.size(), max_players])

	_update_activity()

	# 如果房间满了，准备开始
	if current_players.size() == max_players:
		room_state = RoomState.READY
		print("✓ GameRoom: 房间已满，准备开始游戏")

	return true

func remove_player(player_id: String) -> bool:
	"""移除玩家"""
	if player_id not in current_players:
		return false

	current_players.erase(player_id)
	if player_id in player_hands:
		player_hands.erase(player_id)

	print("✓ GameRoom: 玩家 %s 离开房间" % player_id)
	_update_activity()

	# 如果房间为空，关闭
	if current_players.is_empty():
		room_state = RoomState.CLOSED
		print("✓ GameRoom: 房间已关闭")

	return true

func start_game() -> bool:
	"""开始游戏"""
	if room_state != RoomState.READY:
		print("GameRoom: 房间未准备好")
		return false

	if current_players.size() < 2:
		print("GameRoom: 玩家数不足")
		return false

	room_state = RoomState.PLAYING
	game_state.update_phase(GameState.GamePhase.PLAYING)
	current_turn = 0

	print("✓ GameRoom: 游戏已开始")
	_update_activity()

	return true

func end_game() -> bool:
	"""结束游戏"""
	if room_state != RoomState.PLAYING:
		return false

	room_state = RoomState.FINISHED
	game_state.update_phase(GameState.GamePhase.FINISHED)

	print("✓ GameRoom: 游戏已结束")
	_update_activity()

	return true

func add_card_to_hand(player_id: String, card: CardData) -> bool:
	"""添加卡牌到玩家手中"""
	if player_id not in player_hands:
		return false

	player_hands[player_id].add_card(card)
	return true

func get_player_hand(player_id: String) -> CardHand:
	"""获取玩家的手牌"""
	return player_hands.get(player_id, null)

func discard_card(player_id: String, card: CardData) -> bool:
	"""玩家出牌"""
	if player_id not in player_hands:
		return false

	var hand = player_hands[player_id]
	if hand.remove_card(card):
		discard_pile.append(card)
		return true

	return false

func next_turn() -> String:
	"""切换到下一个玩家"""
	if current_players.is_empty():
		return ""

	current_turn = (current_turn + 1) % current_players.size()
	return current_players[current_turn]

func get_current_player() -> String:
	"""获取当前玩家ID"""
	if current_players.is_empty():
		return ""
	return current_players[current_turn]

func get_room_info() -> Dictionary:
	"""获取房间信息"""
	return {
		"room_id": room_id,
		"state": room_state,
		"players": current_players,
		"player_count": current_players.size(),
		"max_players": max_players,
		"created_at": created_at,
		"current_turn": current_turn
	}

func get_status_string() -> String:
	"""获取房间状态字符串"""
	var state_name = "未知"
	match room_state:
		RoomState.WAITING: state_name = "等待"
		RoomState.READY: state_name = "准备"
		RoomState.PLAYING: state_name = "进行中"
		RoomState.FINISHED: state_name = "已结束"
		RoomState.CLOSED: state_name = "已关闭"

	return "房间 [%s] %s - %d/%d 玩家" % [room_id, state_name, current_players.size(), max_players]

func _update_activity() -> void:
	"""更新最后活动时间"""
	last_activity = Time.get_ticks_msec()

func is_full() -> bool:
	"""检查房间是否已满"""
	return current_players.size() >= max_players

func is_empty() -> bool:
	"""检查房间是否为空"""
	return current_players.is_empty()

func get_uptime_seconds() -> int:
	"""获取房间运行时间（秒）"""
	return (Time.get_ticks_msec() - created_at) / 1000
