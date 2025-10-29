class_name GameController

# 游戏组件
var game_state: GameState
var deck: MahjongDeck
var player_hand: CardHand
var game_stats: Dictionary = {
	"rounds": 0,
	"wins": 0,
	"losses": 0,
	"total_cards_drawn": 0,
	"total_cards_discarded": 0
}

func _init() -> void:
	"""初始化游戏控制器"""
	# 延迟初始化 - 不在这里创建对象
	game_state = null
	deck = null
	player_hand = null

func init_game() -> void:
	"""初始化游戏"""
	print("\n【游戏初始化】")

	# 创建游戏状态管理器
	if game_state == null:
		game_state = GameState.new()

	game_state.update_phase(GameState.GamePhase.WAITING)

	# 创建牌池
	deck = MahjongDeck.new()
	deck.shuffle()

	print("✓ 游戏初始化完成")

func start_game() -> void:
	"""开始游戏"""
	if game_state.get_phase() != GameState.GamePhase.WAITING:
		print("错误：游戏不在准备状态")
		return

	print("\n【游戏开始】")
	game_state.update_phase(GameState.GamePhase.DRAWING)

	# 发初始手牌（13张）
	player_hand = CardHand.new()
	var initial_cards = deck.draw_initial_hand(13)
	for card in initial_cards:
		player_hand.add_card(card)

	game_stats["rounds"] += 1
	game_stats["total_cards_drawn"] += 13

	game_state.update_phase(GameState.GamePhase.PLAYING)
	print("✓ 游戏已开始，发放初始手牌")
	print_player_hand()

func draw_card() -> CardData:
	"""玩家抽一张卡"""
	if not (game_state.get_phase() == GameState.GamePhase.PLAYING or game_state.get_phase() == GameState.GamePhase.DISCARDING):
		print("错误：无法抽卡（当前阶段：%d）" % game_state.get_phase())
		return null

	game_state.update_phase(GameState.GamePhase.DRAWING)
	var card = deck.draw_one()
	if card:
		player_hand.add_card(card)
		game_stats["total_cards_drawn"] += 1
		print("✓ 抽卡: %s" % card.get_card_name())
	else:
		print("牌池已空！")

	game_state.update_phase(GameState.GamePhase.PLAYING)
	return card

func discard_card(card: CardData) -> bool:
	"""玩家出一张卡"""
	var current_phase = game_state.get_phase()
	if current_phase != GameState.GamePhase.PLAYING:
		print("错误：无法出牌（当前阶段不对）")
		return false

	game_state.update_phase(GameState.GamePhase.DISCARDING)
	if player_hand.remove_card(card):
		game_stats["total_cards_discarded"] += 1
		game_state.add_to_discard_pile({"suit": card.suit, "number": card.number})
		print("✓ 出牌: %s" % card.get_card_name())
		return true
	else:
		print("错误：卡牌不在手牌中")
		return false

func check_win() -> bool:
	"""检查是否胜利"""
	if player_hand.get_card_count() == 0:
		print("\n🎉 胜利！")
		game_state.update_phase(GameState.GamePhase.WIN)
		game_stats["wins"] += 1
		return true
	return false

func end_game() -> void:
	"""结束游戏"""
	print("\n【游戏结束】")
	game_state.update_phase(GameState.GamePhase.FINISHED)
	print_game_stats()

func print_player_hand() -> void:
	"""打印玩家手牌"""
	if player_hand:
		player_hand.print_hand()

func print_game_stats() -> void:
	"""打印游戏统计"""
	print("\n【游戏统计】")
	print("轮数: %d" % game_stats["rounds"])
	print("胜利: %d" % game_stats["wins"])
	print("失败: %d" % game_stats["losses"])
	print("总抽卡数: %d" % game_stats["total_cards_drawn"])
	print("总出牌数: %d" % game_stats["total_cards_discarded"])
	print("当前手牌: %d" % (player_hand.get_card_count() if player_hand else 0))

func get_game_status() -> Dictionary:
	"""获取游戏状态"""
	return {
		"current_state": game_state.get_state_name(),
		"hand_count": player_hand.get_card_count() if player_hand else 0,
		"deck_remaining": deck.get_remaining_count() if deck else 0,
		"rounds": game_stats["rounds"]
	}
