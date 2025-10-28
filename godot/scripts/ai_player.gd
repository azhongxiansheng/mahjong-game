class_name AIPlayer

# AI玩家类
# 管理AI的手牌、决策和出牌逻辑

## AI难度等级
enum Difficulty {
	EASY,      # 简单 - 随机出牌
	NORMAL,    # 普通 - 弃老打新
	HARD,      # 困难 - 听牌优先
	EXPERT,    # 专家 - 全面分析
}

var player_id: int                 # 玩家ID (0-3)
var difficulty: Difficulty         # 难度等级
var hand: CardHand                 # 手牌
var discarded_cards: Array[CardData]  # 已弃的牌
var ting_info: TingChecker.TingResult  # 听牌信息
var is_ting: bool                  # 是否已听牌
var name: String                   # 玩家名字

func _init(p_id: int, p_difficulty: Difficulty = Difficulty.NORMAL):
	"""初始化AI玩家"""
	player_id = p_id
	difficulty = p_difficulty
	hand = CardHand.new()
	discarded_cards = []
	ting_info = TingChecker.TingResult.new()
	is_ting = false
	name = "AI玩家%d" % (p_id + 1)

func receive_card(card: CardData) -> void:
	"""接收抽到的牌"""
	if card:
		hand.add_card(card)

func discard_card() -> CardData:
	"""
	AI出牌决策
	根据难度等级选择出牌策略
	"""
	if hand.get_card_count() == 0:
		print("AI玩家 %d: 错误 - 没有可出的牌" % player_id)
		return null
	
	var card_to_discard: CardData = null
	
	match difficulty:
		Difficulty.EASY:
			card_to_discard = _decide_easy()
		Difficulty.NORMAL:
			card_to_discard = _decide_normal()
		Difficulty.HARD:
			card_to_discard = _decide_hard()
		Difficulty.EXPERT:
			card_to_discard = _decide_expert()
	
	if card_to_discard:
		hand.remove_card(card_to_discard)
		discarded_cards.append(card_to_discard)
	
	return card_to_discard

# 简单策略 - 随机出牌
func _decide_easy() -> CardData:
	"""简单AI - 随机选择一张牌出"""
	if hand.get_card_count() > 0:
		var index = randi() % hand.get_card_count()
		return hand.cards[index]
	return null

# 普通策略 - 弃老打新
func _decide_normal() -> CardData:
	"""
	普通AI - 弃老打新
	优先出1和9，保留中间牌
	"""
	var candidate_cards: Array[CardData] = []
	
	# 收集老头牌（1和9）
	for card in hand.cards:
		if card.suit < 3 and (card.number == 1 or card.number == 9):
			candidate_cards.append(card)
	
	if not candidate_cards.is_empty():
		return candidate_cards[randi() % candidate_cards.size()]
	
	# 如果没有老头牌，随机选择
	var index = randi() % hand.get_card_count()
	return hand.cards[index]

# 困难策略 - 听牌优先
func _decide_hard() -> CardData:
	"""
	困难AI - 更智能的决策
	1. 检测听牌
	2. 如果已听，谨慎出牌
	3. 否则积极争取听牌
	"""
	# 检测听牌
	update_ting_info()
	
	if is_ting:
		# 已听牌 - 出最安全的牌（避免帮助对手）
		return _get_safest_card()
	else:
		# 未听牌 - 找能让我们接近听牌的出牌
		return _get_card_toward_ting()

# 专家策略 - 全面分析
func _decide_expert() -> CardData:
	"""
	专家AI - 最复杂的决策
	综合考虑：听牌、安全、收益等
	"""
	update_ting_info()
	
	# 评估所有可能的出牌
	var scores: Dictionary = {}
	
	for card in hand.cards:
		var score = 0
		
		# 基础分：不出我们听的牌
		if is_ting and card in ting_info.ting_cards:
			score -= 1000  # 严格禁止
		else:
			score += 10
		
		# 出牌后的听牌收益
		var temp_hand = CardHand.new()
		for c in hand.cards:
			if c != card:
				temp_hand.add_card(c)
		
		var future_ting = TingChecker.check_ting(temp_hand)
		if future_ting.can_ting:
			score += future_ting.ting_count * 50
		
		scores[card.get_card_name()] = score
	
	# 选择最高分的牌
	var best_card = null
	var best_score = -999999
	
	for card in hand.cards:
		var card_name = card.get_card_name()
		if card_name in scores and scores[card_name] > best_score:
			best_score = scores[card_name]
			best_card = card
	
	return best_card if best_card else hand.cards[0]

# 更新听牌信息
func update_ting_info() -> void:
	"""更新当前的听牌信息"""
	ting_info = TingChecker.check_ting(hand)
	is_ting = ting_info.can_ting

# 获取最安全的牌
func _get_safest_card() -> CardData:
	"""获取最安全的出牌（已听牌时使用）"""
	# 出最早弃过的牌类型，认为这类牌对手不要
	if not discarded_cards.is_empty():
		var last_discarded = discarded_cards[-1]
		for card in hand.cards:
			if card.suit == last_discarded.suit and card.number == last_discarded.number:
				continue  # 不重复
			# 出相同花色但不同数字的牌
			if card.suit == last_discarded.suit:
				return card
	
	# 备选：出最小的牌
	hand.sort_cards()
	return hand.cards[0]

# 获取朝向听牌的出牌
func _get_card_toward_ting() -> CardData:
	"""
	寻找能帮助我们接近听牌的出牌
	"""
	var best_card = null
	var best_ting_value = -1
	
	# 评估每张出牌后的听牌价值
	for card in hand.cards:
		var temp_hand = CardHand.new()
		for c in hand.cards:
			if c != card:
				temp_hand.add_card(c)
		
		var future_ting = TingChecker.check_ting(temp_hand)
		var ting_value = TingChecker.calculate_ting_value(future_ting, temp_hand)
		
		if ting_value > best_ting_value:
			best_ting_value = ting_value
			best_card = card
	
	return best_card if best_card else hand.cards[0]

# 获取玩家状态描述
func get_status_string() -> String:
	"""获取玩家状态字符串"""
	var status = "%s - 手牌:%d张" % [name, hand.get_card_count()]
	
	if is_ting:
		status += " [听牌: %s]" % TingChecker.get_ting_description(ting_info)
	
	return status

# 重置玩家（新游戏）
func reset() -> void:
	"""重置为新游戏"""
	hand = CardHand.new()
	discarded_cards = []
	ting_info = TingChecker.TingResult.new()
	is_ting = false
