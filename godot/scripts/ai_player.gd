# AI 玩家 - 具有不同难度的智能决策系统
class_name AIPlayer

var hand: CardHand
var difficulty: int = 1 # 1=简单, 2=中等, 3=困难
var memory: Dictionary = {} # 记录对手出过的牌

const EASY = 1
const MEDIUM = 2
const HARD = 3

# 初始化
func _init(diff: int = MEDIUM):
	hand = CardHand.new()
	difficulty = clamp(diff, EASY, HARD)

# 获取难度名称
func get_difficulty_name() -> String:
	match difficulty:
		EASY:
			return "简单"
		MEDIUM:
			return "中等"
		HARD:
			return "困难"
		_:
			return "未知"

# 选择出牌 - 主函数
func choose_discard_card() -> CardData:
	if hand.cards.size() == 0:
		return null

	match difficulty:
		EASY:
			return _choose_easy()
		MEDIUM:
			return _choose_medium()
		HARD:
			return _choose_hard()
		_:
			return hand.cards[0]

## 新增：适配GameController的出牌决策方法
func decide_card_to_play(ai_hand: CardHand) -> CardData:
	if ai_hand.cards.size() == 0:
		return null

	# 更新手牌引用
	self.hand = ai_hand

	# 调用原始决策逻辑
	return choose_discard_card()

# 简单难度: 随机出牌
func _choose_easy() -> CardData:
	var idx = randi() % hand.cards.size()
	return hand.cards[idx]

# 中等难度: 基于听牌数出牌
func _choose_medium() -> CardData:
	var best_card = null
	var min_ting = 999

	# 尝试每张牌，选择出牌后听牌最少的
	for card in hand.cards:
		hand.remove_card(card)

		var ting_count = WinChecker.check_can_hear(hand).size()
		if ting_count < min_ting:
			min_ting = ting_count
			best_card = card

		hand.add_card(card)

	return best_card if best_card != null else hand.cards[0]

# 困难难度: 基于风险评分出牌
func _choose_hard() -> CardData:
	var best_card = null
	var best_score = -999

	for card in hand.cards:
		var score = _calculate_risk_score(card)

		if score > best_score:
			best_score = score
			best_card = card

	return best_card if best_card != null else hand.cards[0]

# 计算出牌的风险评分
func _calculate_risk_score(card: CardData) -> float:
	var score = 0.0

	# 因素1: 出牌后的听牌数 (越少越好)
	hand.remove_card(card)
	var my_ting_count = WinChecker.check_can_hear(hand).size()
	score -= my_ting_count * 10.0 # 负分，因为听牌多不利
	hand.add_card(card)

	# 因素2: 牌的稀有度 (常见牌更安全)
	var card_count = _count_card_type(card)
	score += card_count * 5.0 # 相同牌多说明不稀有

	# 因素3: 对手出过的牌安全性 (出过的牌更安全)
	var card_key = "%d_%d" % [card.suit, card.number]
	if card_key in memory:
		score += memory[card_key] * 3.0 # 对手出过这种牌则更安全

	# 因素4: 边牌倾向 (1、9号牌通常更安全)
	if card.number == 1 or card.number == 9:
		score += 5.0

	return score

# 计数牌的数量
func _count_card_type(card: CardData) -> int:
	var count = 0
	for c in hand.cards:
		if c.suit == card.suit and c.number == card.number:
			count += 1
	return count

# 记录对手出过的牌
func record_opponent_discard(card: CardData):
	var card_key = "%d_%d" % [card.suit, card.number]
	memory[card_key] = memory.get(card_key, 0) + 1

# 清空记忆
func clear_memory():
	memory.clear()

# 检查是否可以胡
func can_win() -> bool:
	if hand.get_card_count() != 14:
		return false

	var result = WinChecker.check_win(hand)
	return result.can_win

# 检查是否可以听牌
func can_hear_tiles() -> Array:
	if hand.get_card_count() != 13:
		return []

	return WinChecker.check_can_hear(hand)

# 添加卡牌
func add_card(card: CardData):
	hand.add_card(card)

# 移除卡牌
func remove_card(card: CardData):
	hand.remove_card(card)

# 获取手牌数
func get_card_count() -> int:
	return hand.get_card_count()

# 清空手牌
func clear_hand():
	hand.clear()

# 打印 AI 状态
func print_status():
	print("\n=== AI 玩家状态 ===")
	print("难度: %s" % get_difficulty_name())
	print("手牌数: %d" % get_card_count())
	print("对手记忆: %d种牌" % memory.size())
	if can_hear_tiles().size() > 0:
		print("可听牌: %d种" % can_hear_tiles().size())
