class_name MultiplayerGameFlow
extends Node

# 游戏流程状态
enum GameFlowState {
	LOBBY,
	WAITING_FOR_PLAYERS,
	GAME_START,
	PLAYING,
	ROUND_END,
	GAME_END,
	PAUSED
}

# 玩家操作类型
enum ActionType {
	DRAW,      # 抽牌
	PLAY,      # 出牌
	DISCARD,   # 弃牌
	HU,        # 胡牌
	PASS,      # 跳过
	TIMEOUT    # 超时
}

# 游戏回合类
class GameRound:
	var round_number: int = 0
	var current_player_index: int = 0
	var current_player_id: String = ""
	var current_action: String = "draw"  # "draw", "play", "discard"
	var action_timeout: float = 30.0
	var actions_history: Array = []
	var round_start_time: float = 0.0
	var action_start_time: float = 0.0

	func _init(p_round: int) -> void:
		round_number = p_round
		round_start_time = Time.get_ticks_msec()

	func start_action(player_id: String, action_type: String) -> void:
		action_start_time = Time.get_ticks_msec()
		current_player_id = player_id
		current_action = action_type

	func record_action(player_id: String, action_type: String, action_data: Dictionary) -> void:
		var action_record = {
			"player_id": player_id,
			"action_type": action_type,
			"action_data": action_data,
			"timestamp": Time.get_ticks_msec()
		}
		actions_history.append(action_record)

	func get_action_duration() -> float:
		return (Time.get_ticks_msec() - action_start_time) / 1000.0

	func get_round_duration() -> float:
		return (Time.get_ticks_msec() - round_start_time) / 1000.0

# 游戏结果
class GameResult:
	var winner_id: String = ""
	var winner_name: String = ""
	var total_rounds: int = 0
	var game_duration: float = 0.0
	var final_scores: Dictionary = {}  # player_id -> score
	var final_hands: Dictionary = {}   # player_id -> cards
	var winner_score: int = 0

# 游戏流程管理
var game_state: int = GameFlowState.LOBBY
var current_round: GameRound
var round_number: int = 0
var max_rounds: int = 8

# 玩家管理
var players: Array = []  # [player_id, ...]
var player_order: Array = []
var current_player_index: int = 0
var scores: Dictionary = {}  # player_id -> score

# 时间管理
var game_start_time: float = 0.0
var action_timer: float = 0.0
var action_timeout: float = 30.0

# 信号
signal game_started()
signal game_ended(result: GameResult)
signal round_started(round_number: int)
signal round_ended()
signal turn_started(player_id: String)
signal turn_ended(player_id: String)
signal action_required(player_id: String, action_type: String)
signal action_timeout_warning(player_id: String, remaining_time: float)
signal action_timeout(player_id: String)
signal player_hu(player_id: String, hu_type: String)
signal game_paused()
signal game_resumed()

func _ready() -> void:
	print("========== 多人游戏流程管理器初始化 ==========")
	print("最大回合数: ", max_rounds)
	print("操作超时: ", action_timeout, "秒")

func _process(delta: float) -> void:
	if game_state == GameFlowState.PLAYING and current_round:
		action_timer += delta

		# 检查操作超时
		if action_timer > action_timeout:
			handle_action_timeout()

func start_multiplayer_game(player_list: Array) -> bool:
	"""启动多人游戏"""
	print("\n========== 启动多人游戏 ==========")

	if player_list.size() < 2:
		print("✗ 玩家数量不足 (最少2人)")
		return false

	if player_list.size() > 4:
		print("✗ 玩家数量过多 (最多4人)")
		return false

	players = player_list.duplicate()
	player_order = players.duplicate()
	game_start_time = Time.get_ticks_msec()

	# 初始化分数
	for player_id in players:
		scores[player_id] = 0

	print("✓ 游戏启动，玩家数: ", players.size())
	print("玩家列表: ", players)

	set_game_state(GameFlowState.GAME_START)
	emit_signal("game_started")

	# 开始第一轮
	await get_tree().create_timer(1.0).timeout
	start_round()

	return true

func start_round() -> void:
	"""开始新回合"""
	round_number += 1

	if round_number > max_rounds:
		end_game()
		return

	current_round = GameRound.new(round_number)
	print("\n========== 开始第 ", round_number, " 回合 ==========")

	set_game_state(GameFlowState.PLAYING)
	emit_signal("round_started", round_number)

	# 重置玩家顺序
	current_player_index = (current_player_index + 1) % players.size()

	# 开始第一个玩家的回合
	await get_tree().create_timer(0.5).timeout
	start_player_turn()

func start_player_turn() -> void:
	"""开始单个玩家的回合"""
	var player_id = players[current_player_index]
	current_round.current_player_index = current_player_index
	current_round.current_player_id = player_id

	print("🔄 ", player_id, " 的回合开始")
	action_timer = 0.0

	set_game_state(GameFlowState.PLAYING)
	emit_signal("turn_started", player_id)

	# 要求玩家操作（抽牌）
	current_round.start_action(player_id, "draw")
	emit_signal("action_required", player_id, ActionType.DRAW)

func process_player_action(player_id: String, action_type: String, action_data: Dictionary) -> bool:
	"""处理玩家操作"""
	# 验证是否是当前玩家
	if player_id != players[current_player_index]:
		print("✗ 不是当前玩家的操作")
		return false

	# 验证操作有效性
	if not validate_action(player_id, action_type, action_data):
		print("✗ 无效的操作")
		return false

	print("✓ 玩家 ", player_id, " 执行操作: ", action_type)

	# 记录操作
	current_round.record_action(player_id, action_type, action_data)
	action_timer = 0.0

	match action_type:
		"draw":
			handle_draw_action(player_id, action_data)
		"play":
			handle_play_action(player_id, action_data)
		"discard":
			handle_discard_action(player_id, action_data)
		"hu":
			handle_hu_action(player_id, action_data)
		"pass":
			handle_pass_action(player_id)

	return true

func validate_action(player_id: String, action_type: String, action_data: Dictionary) -> bool:
	"""验证玩家操作的有效性"""
	# 基础验证
	if player_id.is_empty():
		return false

	if action_type not in ["draw", "play", "discard", "hu", "pass"]:
		return false

	match action_type:
		"draw":
			return true  # 抽牌总是有效的
		"play", "discard":
			return "card_index" in action_data
		"hu":
			return "hu_type" in action_data
		"pass":
			return true

	return false

func handle_draw_action(player_id: String, action_data: Dictionary) -> void:
	"""处理抽牌操作"""
	print("📥 玩家 ", player_id, " 抽牌")

	# 转换到出牌阶段
	current_round.start_action(player_id, "play")
	await get_tree().create_timer(0.5).timeout
	emit_signal("action_required", player_id, ActionType.PLAY)

func handle_play_action(player_id: String, action_data: Dictionary) -> void:
	"""处理出牌操作"""
	var card_index = action_data.get("card_index", -1)
	print("🎴 玩家 ", player_id, " 出牌 (索引: ", card_index, ")")

	# 转换到弃牌阶段
	current_round.start_action(player_id, "discard")
	await get_tree().create_timer(0.5).timeout
	emit_signal("action_required", player_id, ActionType.DISCARD)

func handle_discard_action(player_id: String, action_data: Dictionary) -> void:
	"""处理弃牌操作"""
	var card_index = action_data.get("card_index", -1)
	print("🗑️ 玩家 ", player_id, " 弃牌 (索引: ", card_index, ")")

	# 本次回合结束，进入下一个玩家
	end_player_turn()

func handle_hu_action(player_id: String, action_data: Dictionary) -> void:
	"""处理胡牌操作"""
	var hu_type = action_data.get("hu_type", "unknown")
	print("🎊 玩家 ", player_id, " 胡牌! (类型: ", hu_type, ")")

	# 记录胡牌
	scores[player_id] += 10
	emit_signal("player_hu", player_id, hu_type)

	# 游戏结束
	end_game()

func handle_pass_action(player_id: String) -> void:
	"""处理跳过操作"""
	print("⏭️ 玩家 ", player_id, " 跳过")

	# 转到下一个玩家
	end_player_turn()

func handle_action_timeout() -> void:
	"""处理操作超时"""
	var player_id = players[current_player_index]
	print("⏰ 玩家 ", player_id, " 操作超时!")

	emit_signal("action_timeout", player_id)

	# 自动执行PASS操作
	handle_pass_action(player_id)
	action_timer = 0.0

func end_player_turn() -> void:
	"""结束玩家回合"""
	var player_id = players[current_player_index]
	print("✓ 玩家 ", player_id, " 的回合结束")

	emit_signal("turn_ended", player_id)

	# 检查本轮是否结束
	current_player_index = (current_player_index + 1) % players.size()

	# 这里可以添加更复杂的逻辑判断回合是否结束
	# 例如：检查是否所有玩家都操作过了

	await get_tree().create_timer(0.5).timeout

	# 开始下一个玩家的回合
	start_player_turn()

func end_round() -> void:
	"""结束当前回合"""
	print("✓ 第 ", round_number, " 回合结束")

	emit_signal("round_ended")

	# 检查游戏是否结束
	if round_number >= max_rounds:
		end_game()
	else:
		await get_tree().create_timer(1.0).timeout
		start_round()

func end_game() -> void:
	"""结束游戏"""
	print("\n========== 游戏结束 ==========")

	set_game_state(GameFlowState.GAME_END)

	# 计算游戏时间
	var game_duration = (Time.get_ticks_msec() - game_start_time) / 1000.0

	# 创建游戏结果
	var result = GameResult.new()
	result.total_rounds = round_number
	result.game_duration = game_duration
	result.final_scores = scores.duplicate()

	# 找到赢家
	var max_score = -1
	for player_id in scores:
		if scores[player_id] > max_score:
			max_score = scores[player_id]
			result.winner_id = player_id

	result.winner_score = max_score

	print("赢家: ", result.winner_id)
	print("最终分数: ", scores)
	print("游戏时长: ", int(game_duration), "秒")

	emit_signal("game_ended", result)

func pause_game() -> void:
	"""暂停游戏"""
	if game_state == GameFlowState.PLAYING:
		set_game_state(GameFlowState.PAUSED)
		emit_signal("game_paused")
		print("✓ 游戏已暂停")

func resume_game() -> void:
	"""恢复游戏"""
	if game_state == GameFlowState.PAUSED:
		set_game_state(GameFlowState.PLAYING)
		emit_signal("game_resumed")
		print("✓ 游戏已恢复")

func get_current_player() -> String:
	"""获取当前玩家ID"""
	if current_player_index >= 0 and current_player_index < players.size():
		return players[current_player_index]
	return ""

func get_player_score(player_id: String) -> int:
	"""获取玩家分数"""
	return scores.get(player_id, 0)

func set_game_state(new_state: int) -> void:
	"""设置游戏状态"""
	game_state = new_state
	print("🎮 游戏状态: ", GameFlowState.keys()[new_state])

func get_game_info() -> Dictionary:
	"""获取游戏信息"""
	return {
		"state": game_state,
		"round": round_number,
		"max_rounds": max_rounds,
		"current_player": get_current_player(),
		"players": players.duplicate(),
		"scores": scores.duplicate()
	}

func print_game_status() -> void:
	"""打印游戏状态"""
	print("\n========== 游戏状态 ==========")
	print("游戏状态: ", GameFlowState.keys()[game_state])
	print("当前回合: ", round_number, "/", max_rounds)
	print("当前玩家: ", get_current_player())
	print("玩家数: ", players.size())

	print("\n分数:")
	for player_id in scores:
		print("  ", player_id, ": ", scores[player_id])

	print("=============================\n")

func reset_game() -> void:
	"""重置游戏"""
	game_state = GameFlowState.LOBBY
	round_number = 0
	current_player_index = 0
	players.clear()
	scores.clear()
	action_timer = 0.0
	current_round = null
	print("✓ 游戏已重置")
