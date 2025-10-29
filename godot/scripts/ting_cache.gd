# 听牌缓存系统 - 用于缓存听牌检测结果，提升性能
class_name TingCache

var _cache: Dictionary = {}
var _total_hits: int = 0
var _total_misses: int = 0
const MAX_CACHE_SIZE = 1000

func get_ting_cards(hand: CardHand) -> Array:
	if hand == null or hand.get_card_count() != 13:
		return []
	
	var signature = _generate_signature(hand)
	
	if signature in _cache:
		_total_hits += 1
		return _cache[signature]
	
	_total_misses += 1
	return []

func put_ting_cards(hand: CardHand, ting_cards: Array) -> void:
	if hand == null or hand.get_card_count() != 13:
		return
	
	if _cache.size() >= MAX_CACHE_SIZE:
		_clear_half_cache()
	
	var signature = _generate_signature(hand)
	_cache[signature] = ting_cards.duplicate()

func clear_cache() -> void:
	_cache.clear()
	_total_hits = 0
	_total_misses = 0

func get_cache_size() -> int:
	return _cache.size()

func get_cache_hit_rate() -> float:
	var total = _total_hits + _total_misses
	if total == 0:
		return 0.0
	return float(_total_hits) / total * 100.0

func get_total_queries() -> int:
	return _total_hits + _total_misses

func get_total_hits() -> int:
	return _total_hits

func get_total_misses() -> int:
	return _total_misses

func print_stats() -> void:
	var total = _total_hits + _total_misses
	var hit_rate = get_cache_hit_rate()
	
	print("\n=== 听牌缓存统计 ===")
	print("缓存大小: %d / %d" % [_cache.size(), MAX_CACHE_SIZE])
	print("总查询数: %d" % total)
	print("命中次数: %d" % _total_hits)
	print("未命中: %d" % _total_misses)
	print("命中率: %.1f%%" % hit_rate)

func _generate_signature(hand: CardHand) -> String:
	var cards = hand.cards
	if cards.size() == 0:
		return ""
	
	var sorted_cards = []
	for card in cards:
		sorted_cards.append(card)
	
	sorted_cards.sort_custom(func(a, b):
		if a.suit != b.suit:
			return a.suit < b.suit
		return a.number < b.number
	)
	
	var signature_parts = []
	for card in sorted_cards:
		signature_parts.append("%d-%d" % [card.suit, card.number])
	
	return ",".join(signature_parts)

func _clear_half_cache() -> void:
	var keys_to_remove = []
	var remove_count = int(MAX_CACHE_SIZE / 2.0)
	
	for key in _cache.keys():
		if keys_to_remove.size() >= remove_count:
			break
		keys_to_remove.append(key)
	
	for key in keys_to_remove:
		_cache.erase(key)
	
	print("[缓存] 清除%d个旧条目以释放空间" % remove_count)
