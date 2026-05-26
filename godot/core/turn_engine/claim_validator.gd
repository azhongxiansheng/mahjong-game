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

# 吃 companion 候选：返所有合法的 [伴1, 伴2] tile_id 对（不含 discarded_id 自身）
# 规则同 can_chi（仅下家可吃 + 数牌 + 三种顺子组合），但本函数 caller 已确认
# can_chi=true，所以不再校验 seat / 颜色，只算 tile_id 组合。
# 用途：玩家 chi 时从多组合法 companion 中手动挑选；UI 弹候选让玩家选。
# 返：Array[Array]，每元素 [tid1, tid2]（不一定升序，按"低-中-高"位置顺序）。
static func chi_companion_options(hand: Hand, discarded_id: int) -> Array:
	if TileId.is_honor(discarded_id):
		return []
	var n: int = TileId.number(discarded_id)
	var options: Array = []
	# [d-2, d-1, d]：要求 n >= 3，且手中含 d-2, d-1
	if n >= 3 and hand.count_of(discarded_id - 2) > 0 and hand.count_of(discarded_id - 1) > 0:
		options.append([discarded_id - 2, discarded_id - 1])
	# [d-1, d, d+1]：要求 2 <= n <= 8
	if n >= 2 and n <= 8 and hand.count_of(discarded_id - 1) > 0 and hand.count_of(discarded_id + 1) > 0:
		options.append([discarded_id - 1, discarded_id + 1])
	# [d, d+1, d+2]：要求 n <= 7
	if n <= 7 and hand.count_of(discarded_id + 1) > 0 and hand.count_of(discarded_id + 2) > 0:
		options.append([discarded_id + 1, discarded_id + 2])
	return options

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

# 喰い替え: after chi/pon, which tile IDs are forbidden to discard immediately.
# is_chi=true: claimed_id + suji partner (the tile at the "other end" of the sequence).
# is_chi=false (pon): just claimed_id (cannot discard 4th copy).
# companion_ids: the two tiles from hand used in chi (sorted ascending); empty for pon.
static func kuikae_restricted_ids(claimed_id: int, companion_ids: Array, is_chi: bool) -> Array:
	var restricted: Array = [claimed_id]
	if not is_chi:
		return restricted
	if companion_ids.size() != 2:
		return restricted
	var lo: int = min(companion_ids[0], companion_ids[1])
	var hi: int = max(companion_ids[0], companion_ids[1])
	if claimed_id < lo:
		var suji: int = hi + 1
		if _in_same_suit(claimed_id, suji):
			restricted.append(suji)
	elif claimed_id > hi:
		var suji: int = lo - 1
		if _in_same_suit(claimed_id, suji):
			restricted.append(suji)
	return restricted

static func _in_same_suit(a: int, b: int) -> bool:
	if TileId.is_honor(a) or TileId.is_honor(b):
		return false
	for rng in [[TileId.W1, TileId.W9], [TileId.T1, TileId.T9], [TileId.S1, TileId.S9]]:
		if a >= rng[0] and a <= rng[1] and b >= rng[0] and b <= rng[1]:
			return true
	return false
