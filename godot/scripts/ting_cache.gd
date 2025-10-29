# 听牌缓存系统
# 用于缓存听牌检测结果，提升性能
#
# 用法:
#   var cache = TingCache.new()
#   var ting_cards = cache.get_ting_cards(hand)
#   cache.put_ting_cards(hand, result)

class_name TingCache

# 缓存字典 (手牌签名 -> 听牌列表)
var _cache: Dictionary = {}

# 缓存统计
var _total_hits: int = 0
var _total_misses: int = 0

# 缓存大小限制 (防止内存溢出)
const MAX_CACHE_SIZE = 1000

# ========================
# 主要API方法
# ========================

# 从缓存获取听牌结果
# 返回: 听牌列表 (如果缓存命中) 或 null (缓存未命中)
func get_ting_cards(hand: CardHand) -> Array:
	if hand == null or hand.get_card_count() != 13:
		return []

	var signature = _generate_signature(hand)

	if signature in _cache:
		_total_hits += 1
		return _cache[signature]

	_total_misses += 1
	return []  # 返回空数组表示缓存未命中

# 将听牌结果存储到缓存
func put_ting_cards(hand: CardHand, ting_cards: Array) -> void:
	if hand == null or hand.get_card_count() != 13:
		return

	# 如果缓存已满，清除旧数据
	if _cache.size() >= MAX_CACHE_SIZE:
		_clear_half_cache()

	var signature = _generate_signature(hand)
	_cache[signature] = ting_cards.duplicate()

# 清空所有缓存
func clear_cache() -> void:
	_cache.clear()
	_total_hits = 0
	_total_misses = 0

# ========================
# 统计和调试方法
# ========================

# 获取缓存大小
func get_cache_size() -> int:
	return _cache.size()

# 获取缓存命中率 (百分比)
func get_cache_hit_rate() -> float:
	var total = _total_hits + _total_misses
	if total == 0:
		return 0.0
	return float(_total_hits) / total * 100.0

# 获取缓存总次数
func get_total_queries() -> int:
	return _total_hits + _total_misses

# 获取命中次数
func get_total_hits() -> int:
	return _total_hits

# 获取未命中次数
func get_total_misses() -> int:
	return _total_misses

# 打印缓存统计信息
func print_stats() -> void:
	var total = _total_hits + _total_misses
	var hit_rate = get_cache_hit_rate()

	print("\n=== 听牌缓存统计 ===")
	print("缓存大小: %d / %d" % [_cache.size(), MAX_CACHE_SIZE])
	print("总查询数: %d" % total)
	print("命中次数: %d" % _total_hits)
	print("未命中: %d" % _total_misses)
	print("命中率: %.1f%%" % hit_rate)

# ========================
# 私有方法
# ========================

# 生成手牌签名 (唯一标识一个手牌配置)
# 签名格式: "suit1-num1,suit1-num2,...|suit2-num1,..."
func _generate_signature(hand: CardHand) -> String:
	var cards = hand.cards
	if cards.size() == 0:
		return ""

	# 先排序卡牌 (先按花色，再按数字)
	var sorted_cards = []
	for card in cards:
		sorted_cards.append(card)

	# 自定义排序
	sorted_cards.sort_custom(func(a, b):
		if a.suit != b.suit:
			return a.suit < b.suit
		return a.number < b.number
	)

	# 生成签名字符串
	var signature_parts = []
	for card in sorted_cards:
		signature_parts.append("%d-%d" % [card.suit, card.number])

	return ",".join(signature_parts)

# 清除一半的旧缓存 (当缓存满时)
func _clear_half_cache() -> void:
	var keys_to_remove = []
	var remove_count = MAX_CACHE_SIZE / 2

	for key in _cache.keys():
		if keys_to_remove.size() >= remove_count:
			break
		keys_to_remove.append(key)

	for key in keys_to_remove:
		_cache.erase(key)

	print("[缓存] 清除%d个旧条目以释放空间" % remove_count)
