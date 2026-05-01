class_name Chuuren

# 九蓮宝燈 / 純正九蓮宝燈
# 必须完全无副露（连暗杠都不行 — wc.is_menzen() 容许 ANKAN，这里要更严）
# 起手 14 张同花色，分布满足 1112345678999 + 任意一张
# 純正：去掉和牌张后剩 13 张恰为 1112345678999
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if wc.melds.size() != 0:
		return null
	# 单一花色（数牌）
	var first_suit := -1
	for tid in wc.all_tile_ids():
		if TileId.is_honor(tid):
			return null
		var s: int = TileId.suit(tid)
		if first_suit == -1:
			first_suit = s
		elif s != first_suit:
			return null
	# 1-9 数字分布
	var counts := {}
	for tid in wc.all_tile_ids():
		var num: int = TileId.number(tid)
		counts[num] = counts.get(num, 0) + 1
	if counts.get(1, 0) < 3 or counts.get(9, 0) < 3:
		return null
	for n in [2, 3, 4, 5, 6, 7, 8]:
		if counts.get(n, 0) < 1:
			return null
	# 純正判定：去掉和牌张后剩 1112345678999
	var counts_wo := counts.duplicate()
	var win_num: int = TileId.number(wc.winning_tile.id)
	counts_wo[win_num] = counts_wo[win_num] - 1
	var is_pure: bool = counts_wo.get(1, 0) == 3 and counts_wo.get(9, 0) == 3
	if is_pure:
		for n in [2, 3, 4, 5, 6, 7, 8]:
			if counts_wo.get(n, 0) != 1:
				is_pure = false
				break
	if is_pure:
		return YakuEntry.new(YakuId.JUNSEI_CHUUREN, 0, true, 2)
	return YakuEntry.new(YakuId.CHUUREN, 0, true, 1)
