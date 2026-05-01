class_name SanshokuDoukou

# 三色同刻：万/筒/索 三色 同数字刻子
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	# 收集所有刻子的 tile_id
	var triplets: Array = []
	for m in wc.melds:
		match m.kind:
			Meld.Kind.PON, Meld.Kind.MINKAN, Meld.Kind.ANKAN, Meld.Kind.ADDED_KAN:
				triplets.append(m.tiles[0].id)
	if wc.win_result.standard_decompositions.size() > 0:
		var d = wc.win_result.standard_decompositions[0]
		for meld_ids in d.melds:
			if meld_ids[0] == meld_ids[1] and meld_ids[1] == meld_ids[2]:
				triplets.append(meld_ids[0])
	# 按数字分组找三花色齐
	var by_num: Dictionary = {}
	for tid in triplets:
		if TileId.is_honor(tid):
			continue
		var num: int = TileId.number(tid)
		var suit: int = TileId.suit(tid)
		if not by_num.has(num):
			by_num[num] = {}
		by_num[num][suit] = true
	for num in by_num:
		var s: Dictionary = by_num[num]
		if s.has(TileId.Suit.MAN) and s.has(TileId.Suit.PIN) and s.has(TileId.Suit.SOU):
			return YakuEntry.new(YakuId.SANSHOKU_DOUKOU, 2, false, 0)
	return null
