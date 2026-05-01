class_name ClaimValidator

# 鸣牌 / 荣胡 / 自摸合法性。所有方法纯函数：不修改 state。

# 吃：仅下家 (claimant == discarder + 1)，且 hand 含构成顺子的另 2 张，且数牌
static func can_chi(claimant_seat: int, discarder_seat: int, hand: Hand, discarded_id: int) -> bool:
	if claimant_seat == discarder_seat:
		return false
	if claimant_seat != (discarder_seat + 1) % 4:
		return false
	if TileId.is_honor(discarded_id):
		return false
	# 三种顺子组合：[d-2,d-1,d] / [d-1,d,d+1] / [d,d+1,d+2]
	# 要求另两张同色（即同一花色范围），用 number 边界判断
	var n: int = TileId.number(discarded_id)
	# [d-2, d-1, d]：要求 n >= 3，且手中含 d-2, d-1
	if n >= 3 and hand.count_of(discarded_id - 2) > 0 and hand.count_of(discarded_id - 1) > 0:
		return true
	# [d-1, d, d+1]：要求 2 <= n <= 8
	if n >= 2 and n <= 8 and hand.count_of(discarded_id - 1) > 0 and hand.count_of(discarded_id + 1) > 0:
		return true
	# [d, d+1, d+2]：要求 n <= 7
	if n <= 7 and hand.count_of(discarded_id + 1) > 0 and hand.count_of(discarded_id + 2) > 0:
		return true
	return false

# 碰：任意非弃牌家，hand 含 ≥ 2 张同 id
static func can_pon(claimant_seat: int, discarder_seat: int, hand: Hand, discarded_id: int) -> bool:
	if claimant_seat == discarder_seat:
		return false
	return hand.count_of(discarded_id) >= 2

# 明杠：任意非弃牌家，hand 含 ≥ 3 张同 id
static func can_minkan(claimant_seat: int, discarder_seat: int, hand: Hand, discarded_id: int) -> bool:
	if claimant_seat == discarder_seat:
		return false
	return hand.count_of(discarded_id) >= 3

# 暗杠候选：手中有 4 张同 id 的 id 列表
static func ankan_candidates(hand: Hand) -> Array:
	var candidates: Array = []
	for tid in TileId.ALL:
		if hand.count_of(tid) >= 4:
			candidates.append(tid)
	return candidates

# 加杠：melds 中含某 id 的 PON + 手中有第 4 张同 id
static func can_added_kan(melds: Array, hand: Hand, tile_id: int) -> bool:
	if hand.count_of(tile_id) < 1:
		return false
	for m in melds:
		if m.kind == Meld.Kind.PON and m.tiles[0].id == tile_id:
			return true
	return false

# 荣胡：完成胡牌型 + 非振听
static func can_ron(hand: Hand, melds: Array, discarded_tile: Tile, furiten_state: FuritenState) -> bool:
	if furiten_state.is_furiten():
		return false
	var typed_melds: Array[Meld] = []
	for m in melds:
		typed_melds.append(m)
	var r := WinPattern.detect(hand, typed_melds, discarded_tile)
	return r.is_winning

# 自摸：摸到的牌完成胡牌型
static func can_tsumo(hand: Hand, melds: Array, drawn_tile: Tile) -> bool:
	var typed_melds: Array[Meld] = []
	for m in melds:
		typed_melds.append(m)
	var r := WinPattern.detect(hand, typed_melds, drawn_tile)
	return r.is_winning
