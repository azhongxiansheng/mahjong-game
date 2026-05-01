class_name AbortiveDraw

# 5 种途中流局（spec §3.2）的纯判定函数。
# 触发时机/优先级由调用方（状态机）决定，本模块只提供 bool 判定。

# 四风连打：第一巡 4 家弃同一字风牌
static func is_suufon_renda(first_round_discards: Array) -> bool:
	if first_round_discards.size() != 4:
		return false
	var first: int = first_round_discards[0]
	if first < TileId.E or first > TileId.N:
		return false  # 必须风牌
	for d in first_round_discards:
		if d != first:
			return false
	return true

# 九种九牌：第一巡某家手 13 张含 ≥9 种 distinct 幺九
static func is_kyuusyu_kyuuhai(hand_ids: Array) -> bool:
	var distinct := {}
	for tid in hand_ids:
		if TileId.is_yaochu(tid):
			distinct[tid] = true
	return distinct.size() >= 9

# 四杠散了：4 杠成立且非全同 1 人（同 1 人 4 杠 → 四杠子役满，不流局）
static func is_suukantsu_sanra(kan_seats: Array) -> bool:
	if kan_seats.size() != 4:
		return false
	var distinct := {}
	for s in kan_seats:
		distinct[s] = true
	return distinct.size() > 1

# 四家立直：4 家都立直
static func is_suucha_riichi(seats_riichi: Array) -> bool:
	if seats_riichi.size() != 4:
		return false
	for r in seats_riichi:
		if not r:
			return false
	return true

# 三家和了：3 家以上同时荣胡
static func is_sancha_houra(ron_count: int) -> bool:
	return ron_count >= 3
