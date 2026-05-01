class_name SanshokuDoujun

# 三色同顺：万/筒/索 三色各有一个相同数字开头的顺子
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	var seqs := _collect_all_sequences(wc)
	# Group by start number -> which suits have this start
	var by_start: Dictionary = {}
	for s in seqs:
		var num: int = TileId.number(s[0])
		var suit: int = TileId.suit(s[0])
		if not by_start.has(num):
			by_start[num] = {}
		by_start[num][suit] = true
	for num in by_start:
		var suits: Dictionary = by_start[num]
		if suits.has(TileId.Suit.MAN) and suits.has(TileId.Suit.PIN) and suits.has(TileId.Suit.SOU):
			var han: int = 2 if wc.is_menzen() else 1
			return YakuEntry.new(YakuId.SANSHOKU_DOUJUN, han, false, 0)
	return null

# Public helper used by Ittsu too
static func _collect_all_sequences(wc: WinContext) -> Array:
	var result: Array = []
	for m in wc.melds:
		if m.kind == Meld.Kind.CHI:
			result.append([m.tiles[0].id, m.tiles[1].id, m.tiles[2].id])
	if wc.win_result.standard_decompositions.size() > 0:
		var d = wc.win_result.standard_decompositions[0]
		for meld_ids in d.melds:
			if meld_ids[0] != meld_ids[1] and meld_ids[2] - meld_ids[0] == 2:
				result.append(meld_ids)
	return result
