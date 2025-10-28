class_name GameFlow
extends Node

# 游戏控制器和UI引用
var game_controller: GameController
var game_ui: GameUI

# 游戏状态
var current_round: int = 0
var current_player_index: int = 0
var game_started: bool = false
var game_paused: bool = false

# 玩家列表
var players: Array = []

# 信号
signal game_initialized
signal round_started(round_number: int)
signal turn_started(player_index: int)
signal turn_ended
signal game_ended(winner_index: int)

func _ready() -> void:
	print("========== GameFlow 初始化 ==========")

	# ✓ 方案 1: 尝试正确的相对路径
	var main = get_tree().root.get_node_or_null("/root/Main")
	if main:
		game_ui = main.get_node_or_null("UILayer/GameUI")
	
	# ✓ 方案 2: 如果失败，尝试通过 find_child
	if not game_ui:
		game_ui = get_tree().root.find_child("GameUI", true, false)
	
	if not game_ui:
		print("⚠ 无法找到GameUI")
		return

	print("✓ GameFlow已初始化")

func init_game(player_count: int = 4) -> void:
	"""初始化游戏"""
	print("\n========== 初始化游戏 ==========")

	if game_controller:
		game_controller.init_game()

	current_round = 1
	current_player_index = 0
	game_started = true

	print("✓ 游戏已初始化")
	print("✓ 当前轮: %d" % current_round)

	game_initialized.emit()

	# 开始第一轮
	await get_tree().create_timer(0.5).timeout
	start_round()

func start_round() -> void:
	"""开始新的一轮"""
	print("\n========== 第 %d 轮开始 ==========" % current_round)

	if game_ui:
		game_ui.add_log_message("✓ 第 %d 轮开始" % current_round)

	round_started.emit(current_round)

	# 发初始手牌
	if game_controller:
		game_controller.start_game()

		# 显示玩家手牌
		var player = game_controller.get_current_player()
		if player and game_ui:
			var hand = player.get_hand() if player.has_method("get_hand") else player.hand
			if hand:
				game_ui.display_hand(hand)
				game_ui.display_opponent_hand(13)

	await get_tree().create_timer(0.5).timeout
	start_turn()

func start_turn() -> void:
	"""开始玩家回合"""
	print("\n--- 玩家 %d 的回合 ---" % (current_player_index + 1))

	if game_ui:
		game_ui.add_log_message("玩家 %d 的回合" % (current_player_index + 1))

	turn_started.emit(current_player_index)

	# 抽卡
	if game_controller:
		var drawn_card = game_controller.draw_card()
		if drawn_card and game_ui:
			game_ui.add_log_message("抽到: %s" % drawn_card.get_card_name())

func end_turn() -> void:
	"""结束玩家回合"""
	print("玩家回合结束")

	# 切换到下一个玩家
	current_player_index = (current_player_index + 1) % 4

	turn_ended.emit()

	if game_ui:
		game_ui.add_log_message("回合结束")

	await get_tree().create_timer(0.5).timeout

	if current_player_index == 0:
		# 新的一轮
		current_round += 1
		if current_round <= 16:  # 最多16轮
			start_round()
		else:
			end_game()
	else:
		start_turn()

func end_game() -> void:
	"""结束游戏"""
	print("\n========== 游戏结束 ==========")

	game_started = false

	if game_ui:
		game_ui.add_log_message("游戏结束！")

	game_ended.emit(current_player_index)

func check_win(hand: CardHand) -> bool:
	"""检查是否能胡牌"""
	if not WinChecker:
		print("⚠ WinChecker不可用")
		return false

	var result = WinChecker.check_win(hand)

	if result.can_win:
		print("✓ 胡牌!")
		if game_ui:
			game_ui.show_win_result(result)
		game_ended.emit(current_player_index)
		return true

	return false

func check_ting(hand: CardHand) -> bool:
	"""检查是否能听牌"""
	if not TingChecker:
		print("⚠ TingChecker不可用")
		return false

	var result = TingChecker.check_ting(hand)

	if result.can_ting:
		print("✓ 可以听牌，听%d种牌" % result.ting_count)
		if game_ui:
			game_ui.add_log_message("可以听牌，听 %d 种牌" % result.ting_count)
		return true

	return false

func pause_game() -> void:
	"""暂停游戏"""
	if game_started:
		game_paused = true
		print("⏸ 游戏已暂停")
		if game_ui:
			game_ui.add_log_message("游戏已暂停")

func resume_game() -> void:
	"""恢复游戏"""
	if game_paused:
		game_paused = false
		print("▶ 游戏已恢复")
		if game_ui:
			game_ui.add_log_message("游戏已恢复")

func get_game_status() -> Dictionary:
	"""获取游戏状态"""
	return {
		"current_round": current_round,
		"current_player": current_player_index,
		"game_started": game_started,
		"game_paused": game_paused
	}
