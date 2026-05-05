## 游戏控制器
## 管理游戏的核心流程：摸牌、出牌、AI决策、胡牌判定等
class_name GameController
extends Node

## 游戏相关引用
var game_state: GameState
var ai_player: AIPlayer

## UI系统引用
var hand_display: HandDisplayManager
var animation: CardAnimation

## 牌库数据
var deck: Array[CardData] = []
var deck_index: int = 0

## UI位置配置
var deck_pos: Vector2 = Vector2(100, 100) # 牌库位置
var player_hand_pos: Vector2 = Vector2(100, 500) # 玩家手牌位置
var discard_pos: Vector2 = Vector2(400, 300) # 弃牌堆位置

## 游戏配置
var ai_difficulty: int = 1 # 0=简单, 1=中等, 2=困难

## 信号
signal game_initialized
signal turn_started(player: String)
signal card_drawn(player: String, card: CardData)
signal card_played(player: String, card: CardData)
signal win_detected(winner: String, win_info: Dictionary)

func _ready() -> void:
	print("🎮 GameController 初始化中...")

	# 初始化游戏状态
	game_state = GameState.new()
	game_state._ready()

	# 初始化AI玩家
	ai_player = AIPlayer.new()
	ai_player.difficulty = ai_difficulty

	# 初始化UI系统
	_initialize_ui_system()

	print("✅ GameController 初始化完成")

## 初始化UI系统
func _initialize_ui_system() -> void:
	print("🎨 初始化UI系统...")

	# 创建手牌显示管理器
	hand_display = HandDisplayManager.new()
	print("   ✅ HandDisplayManager 已创建")

	# 创建动画系统
	animation = CardAnimation.new()
	print("   ✅ CardAnimation 已创建")

	# 连接手牌选择信号
	hand_display.card_selected.connect(_on_player_card_selected)
	hand_display.card_deselected.connect(_on_player_card_deselected)
	print("   ✅ 信号已连接")

## 初始化游戏
func initialize_game() -> void:
	print("\n" + "==================================================")
	print("🎮 游戏初始化")
	print("==================================================\n")

	# 重置游戏状态
	game_state.reset_game()

	# 创建牌库
	_create_deck()

	# 洗牌
	_shuffle_deck()

	# 发牌给玩家和AI
	_deal_cards()

	# 更新手牌显示
	hand_display.set_hand(game_state.player_hand)

	game_initialized.emit()

	# 开始第一轮
	start_round()

## 开始新一轮
func start_round() -> void:
	print("\n🎮 第 %d 轮开始\n" % game_state.game_round)

	# 清空手牌
	game_state.player_hand.clear()
	game_state.ai_hand.clear()
	game_state.player_discards.clear()
	game_state.ai_discards.clear()
	game_state.discard_pile.clear()

	# 重新洗牌和发牌
	deck_index = 0
	_shuffle_deck()
	_deal_cards()

	# 刷新手牌显示
	hand_display.refresh_display()

	# 玩家先手
	game_state.transition_to(GameState.State.PLAYER_TURN)
	turn_started.emit("player")

## 创建标准麻将牌库
func _create_deck() -> void:
	deck.clear()

	# 4套完整的牌
	for _set in range(4):
		# 万牌 (0-8: 一万到九万)
		for num in range(1, 10):
			var card = CardData.new(CardData.Suit.WAN, num)
			deck.append(card)

		# 筒牌 (9-17: 一筒到九筒)
		for num in range(1, 10):
			var card = CardData.new(CardData.Suit.TONG, num)
			deck.append(card)

		# 条牌 (18-26: 一条到九条)
		for num in range(1, 10):
			var card = CardData.new(CardData.Suit.TIAO, num)
			deck.append(card)

		# 字牌 (27-33: 东南西北中发白)
		var letter_cards = [
			{"suit": CardData.Suit.ZI, "number": 1}, # 东
			{"suit": CardData.Suit.ZI, "number": 2}, # 南
			{"suit": CardData.Suit.ZI, "number": 3}, # 西
			{"suit": CardData.Suit.ZI, "number": 4}, # 北
			{"suit": CardData.Suit.ZI, "number": 5}, # 中
			{"suit": CardData.Suit.ZI, "number": 6}, # 发
			{"suit": CardData.Suit.ZI, "number": 7}, # 白
		]
		for card_info in letter_cards:
			var card = CardData.new(card_info["suit"], card_info["number"])
			deck.append(card)

	print("✅ 牌库创建完成: %d张牌" % deck.size())

## 洗牌
func _shuffle_deck() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	for i in range(deck.size() - 1, 0, -1):
		var j = rng.randi_range(0, i)
		var temp = deck[i]
		deck[i] = deck[j]
		deck[j] = temp

	deck_index = 0
	print("🔀 牌库已洗牌")

## 发牌给玩家和AI
func _deal_cards() -> void:
	# 玩家先摸13张
	for _i in range(13):
		var card = _draw_from_deck()
		if card:
			game_state.player_hand.add_card(card)

	# AI摸13张
	for _i in range(13):
		var card = _draw_from_deck()
		if card:
			game_state.ai_hand.add_card(card)

	print("✅ 发牌完成")
	print("   玩家: %d张" % game_state.player_hand.cards.size())
	print("   AI: %d张" % game_state.ai_hand.cards.size())

## 从牌库抽牌
func _draw_from_deck() -> CardData:
	if deck_index >= deck.size():
		print("⚠️  牌库已用完!")
		return null

	var card = deck[deck_index]
	deck_index += 1
	return card

## 玩家摸牌（UI交互）
func player_draw_card() -> void:
	if not game_state.is_player_turn():
		print("❌ 现在不是玩家回合")
		return

	var card = _draw_from_deck()
	if card:
		game_state.player_hand.add_card(card)
		game_state.record_action("player", GameState.Action.DRAW, card)
		card_drawn.emit("player", card)
		print("✅ 玩家摸牌: %s" % card.get_display_name())
		print("   手牌数: %d" % game_state.player_hand.cards.size())

		# 更新UI显示
		hand_display.refresh_display()

## 玩家出牌（通过UI信号调用）
func player_play_card(card: CardData) -> void:
	if not game_state.is_player_turn():
		print("❌ 现在不是玩家回合")
		return

	# 从手牌中移除该牌
	if not game_state.player_hand.remove_card(card):
		print("❌ 手牌中没有这张牌")
		return

	# 记录弃牌
	game_state.player_discards.append(card)
	game_state.last_played_card = card
	game_state.last_played_by = "player"

	game_state.record_action("player", GameState.Action.PLAY, card)
	card_played.emit("player", card)
	print("✅ 玩家出牌: %s" % card.get_display_name())

	# 更新UI显示
	hand_display.refresh_display()
	hand_display.clear_selection()

	# 检查AI是否能胡
	if await _check_ai_win():
		return

	# 切换到AI回合
	game_state.transition_to(GameState.State.AI_TURN)
	call_deferred("_ai_turn")

## 玩家选中卡牌（UI信号）
func _on_player_card_selected(card: CardData) -> void:
	# 检查玩家手牌是否满14张（已摸牌）
	if game_state.player_hand.cards.size() < 14:
		print("❌ 还没有摸牌，无法出牌")
		hand_display.clear_selection()
		return

	# 出牌
	player_play_card(card)

## 玩家取消选中卡牌（UI信号）
func _on_player_card_deselected(card: CardData) -> void:
	print("📋 玩家取消选择: %s" % card.get_display_name())

## AI出牌
func ai_play_card() -> void:
	if not game_state.is_ai_turn():
		print("❌ 现在不是AI回合")
		return

	# AI决策出牌
	var card_to_play = ai_player.decide_card_to_play(game_state.ai_hand)

	if not card_to_play:
		print("❌ AI无法决定出牌")
		return

	# 从手牌中移除该牌
	game_state.ai_hand.remove_card(card_to_play)

	# 记录弃牌
	game_state.ai_discards.append(card_to_play)
	game_state.last_played_card = card_to_play
	game_state.last_played_by = "ai"

	game_state.record_action("ai", GameState.Action.PLAY, card_to_play)
	card_played.emit("ai", card_to_play)
	print("✅ AI出牌: %s" % card_to_play.get_display_name())

	# 检查玩家是否能胡
	if await _check_player_win():
		return

	# 切换到玩家回合
	game_state.transition_to(GameState.State.PLAYER_TURN)
	call_deferred("_player_turn_start")

## AI回合
func _ai_turn() -> void:
	# AI摸牌
	var card = _draw_from_deck()
	if card:
		game_state.ai_hand.add_card(card)
		game_state.record_action("ai", GameState.Action.DRAW, card)
		card_drawn.emit("ai", card)
		print("✅ AI摸牌: %s" % card.get_display_name())

	# 等待1秒后AI出牌
	await get_tree().create_timer(1.0).timeout
	ai_play_card()

## 玩家回合开始
func _player_turn_start() -> void:
	turn_started.emit("player")

## 检查玩家是否能胡
func _check_player_win() -> bool:
	# 只有14张牌才能胡
	if game_state.player_hand.cards.size() != 14:
		return false

	# 检查是否满足胡牌条件
	var win_result = WinChecker.check_win(game_state.player_hand)

	if win_result and win_result.is_win:
		# 玩家胡牌！
		game_state.transition_to(GameState.State.SHOW_WIN)
		var win_info = {
			"winner": "player",
			"win_type": win_result.win_type,
			"melding_groups": win_result.melding_groups
		}
		win_detected.emit("player", win_info)
		print("🏆 玩家胡牌!")

		# 等待显示后结束回合
		await get_tree().create_timer(2.0).timeout
		game_state.end_round("player")

		# 检查是否继续下一轮
		if game_state.game_round <= game_state.game_total_rounds:
			await get_tree().create_timer(1.0).timeout
			start_round()
		else:
			game_state.end_game()

		return true

	return false

## 检查AI是否能胡
func _check_ai_win() -> bool:
	# 只有14张牌才能胡
	if game_state.ai_hand.cards.size() != 14:
		return false

	# 检查是否满足胡牌条件
	var win_result = WinChecker.check_win(game_state.ai_hand)

	if win_result and win_result.is_win:
		# AI胡牌！
		game_state.transition_to(GameState.State.SHOW_WIN)
		var win_info = {
			"winner": "ai",
			"win_type": win_result.win_type,
			"melding_groups": win_result.melding_groups
		}
		win_detected.emit("ai", win_info)
		print("🏆 AI胡牌!")

		# 等待显示后结束回合
		await get_tree().create_timer(2.0).timeout
		game_state.end_round("ai")

		# 检查是否继续下一轮
		if game_state.game_round <= game_state.game_total_rounds:
			await get_tree().create_timer(1.0).timeout
			start_round()
		else:
			game_state.end_game()

		return true

	return false

## 重新开始游戏
func restart_game() -> void:
	initialize_game()

## 调试：获取当前游戏状态
func get_debug_info() -> Dictionary:
	return {
		"current_state": game_state.current_state,
		"game_round": game_state.game_round,
		"player_hand_count": game_state.player_hand.cards.size(),
		"ai_hand_count": game_state.ai_hand.cards.size(),
		"player_score": game_state.player_score,
		"ai_score": game_state.ai_score,
		"deck_remaining": deck.size() - deck_index
	}

## 获取UI系统引用（供main.gd使用）
func get_hand_display() -> HandDisplayManager:
	return hand_display

func get_animation() -> CardAnimation:
	return animation
