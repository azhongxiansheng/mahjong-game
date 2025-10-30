## 游戏状态管理类
## 负责管理游戏的各个阶段和全局游戏状态
class_name GameState
extends Node

## 游戏状态枚举
enum State {
	IDLE, # 等待玩家操作
	PLAYER_TURN, # 玩家回合（摸牌-出牌）
	AI_TURN, # AI回合（出牌-响应）
	SHOW_WIN, # 显示胡牌
	GAME_OVER # 游戏结束
}

## 游戏动作类型
enum Action {
	DRAW, # 摸牌
	PLAY, # 出牌
	PENG, # 碰
	KONG, # 杠
	WIN, # 胡牌
	PASS # 跳过
}

## 当前游戏状态
var current_state: State = State.IDLE
var previous_state: State = State.IDLE

## 玩家数据
var player_hand: CardHand
var player_discards: Array[CardData] = []
var player_score: int = 0
var player_ready_to_play: bool = false

## AI数据
var ai_hand: CardHand
var ai_discards: Array[CardData] = []
var ai_score: int = 0

## 游戏数据
var discard_pile: Array[CardData] = [] # 当前回合弃牌堆
var game_round: int = 1
var game_total_rounds: int = 4
var last_played_card: CardData = null
var last_played_by: String = "" # "player" 或 "ai"

## 信号
signal state_changed(new_state: State, old_state: State)
signal action_performed(player: String, action: Action, card: CardData)
signal round_started(round_num: int)
signal round_ended(winner: String)
signal game_ended(winner: String)

func _ready() -> void:
	print("🎮 GameState 初始化中...")
	player_hand = CardHand.new()
	ai_hand = CardHand.new()
	print("✅ GameState 初始化完成")

## 过渡到新状态
func transition_to(new_state: State) -> void:
	if new_state == current_state:
		return

	previous_state = current_state
	current_state = new_state
	state_changed.emit(new_state, previous_state)

	print("📍 状态转换: %s → %s" % [_state_name(previous_state), _state_name(new_state)])

## 获取状态名称（调试用）
func _state_name(state: State) -> String:
	match state:
		State.IDLE: return "IDLE"
		State.PLAYER_TURN: return "PLAYER_TURN"
		State.AI_TURN: return "AI_TURN"
		State.SHOW_WIN: return "SHOW_WIN"
		State.GAME_OVER: return "GAME_OVER"
		_: return "UNKNOWN"

## 记录玩家动作
func record_action(player: String, action: Action, card: CardData = null) -> void:
	action_performed.emit(player, action, card)

	var action_name = _action_name(action)
	if card:
		print("🎯 %s 执行: %s -> %s" % [player, action_name, card.get_display_name()])
	else:
		print("🎯 %s 执行: %s" % [player, action_name])

## 获取动作名称（调试用）
func _action_name(action: Action) -> String:
	match action:
		Action.DRAW: return "摸牌"
		Action.PLAY: return "出牌"
		Action.PENG: return "碰"
		Action.KONG: return "杠"
		Action.WIN: return "胡牌"
		Action.PASS: return "跳过"
		_: return "未知动作"

## 开始新一轮
func start_new_round() -> void:
	if game_round > game_total_rounds:
		end_game()
		return

	player_hand.clear()
	ai_hand.clear()
	player_discards.clear()
	ai_discards.clear()
	discard_pile.clear()
	player_ready_to_play = false
	last_played_card = null
	last_played_by = ""

	transition_to(State.PLAYER_TURN)
	round_started.emit(game_round)
	print("🎮 第 %d 轮开始" % game_round)

## 结束当前回合
func end_round(winner: String) -> void:
	# 根据胜负更新分数
	if winner == "player":
		player_score += 1
	elif winner == "ai":
		ai_score += 1

	round_ended.emit(winner)
	print("🏆 第 %d 轮结束，胜者: %s" % [game_round, winner])
	game_round += 1

## 结束游戏
func end_game() -> void:
	var winner = "player" if player_score > ai_score else ("ai" if ai_score > player_score else "draw")
	transition_to(State.GAME_OVER)
	game_ended.emit(winner)

	print("\n==================================================")
	print("🎉 游戏结束！")
	print("玩家分数: %d" % player_score)
	print("AI分数: %d" % ai_score)
	print("胜者: %s" % winner)
	print("==================================================\n")

## 重置游戏
func reset_game() -> void:
	current_state = State.IDLE
	previous_state = State.IDLE
	player_hand.clear()
	ai_hand.clear()
	player_discards.clear()
	ai_discards.clear()
	discard_pile.clear()
	player_score = 0
	ai_score = 0
	game_round = 1
	player_ready_to_play = false
	last_played_card = null
	last_played_by = ""
	print("🔄 游戏已重置")

## 获取当前玩家
func get_current_player() -> String:
	return "player" if current_state == State.PLAYER_TURN else "ai"

## 检查是否是玩家回合
func is_player_turn() -> bool:
	return current_state == State.PLAYER_TURN

## 检查是否是AI回合
func is_ai_turn() -> bool:
	return current_state == State.AI_TURN

## 获取游戏进度
func get_progress() -> float:
	return float(game_round) / float(game_total_rounds)

## 获取玩家手牌数
func get_player_hand_count() -> int:
	return player_hand.cards.size()

## 获取AI手牌数
func get_ai_hand_count() -> int:
	return ai_hand.cards.size()

## 调试输出游戏状态
func debug_state() -> void:
	print("\n==================================================")
	print("🎮 游戏状态调试信息")
	print("当前状态: %s" % _state_name(current_state))
	print("当前回合: %d/%d" % [game_round, game_total_rounds])
	print("玩家分数: %d | AI分数: %d" % [player_score, ai_score])
	print("玩家手牌数: %d | AI手牌数: %d" % [get_player_hand_count(), get_ai_hand_count()])
	print("==================================================\n")
