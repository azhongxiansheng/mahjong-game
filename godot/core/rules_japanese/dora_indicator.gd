class_name DoraIndicator

# Dora 指示牌 → Dora 转换 + 手牌+副露中 dora 张数统计。
# 复用 TileId.next_for_dora；赤 dora 按 Tile.is_red_dora 单独计。

static func dora_from_indicator(indicator_id: int) -> int:
	return TileId.next_for_dora(indicator_id)

# 普通 dora 张数：枚举 hand + 所有副露的 tile id，匹配任一指示牌对应的 dora id 计数
static func count_normal_dora(hand: Hand, called_melds: Array, indicator_ids: Array) -> int:
	var dora_set := {}
	for ind in indicator_ids:
		dora_set[dora_from_indicator(ind)] = true

	var total := 0
	for tid in hand.to_id_array():
		if dora_set.has(tid):
			total += 1
	for m in called_melds:
		for t in m.tiles:
			if dora_set.has(t.id):
				total += 1
	return total

# 赤 dora 张数：扫 hand + 副露中所有 Tile.is_red_dora
static func count_red_dora(hand: Hand, called_melds: Array) -> int:
	var total := 0
	for t in hand.tiles():
		if t.is_red_dora:
			total += 1
	for m in called_melds:
		for t in m.tiles:
			if t.is_red_dora:
				total += 1
	return total
