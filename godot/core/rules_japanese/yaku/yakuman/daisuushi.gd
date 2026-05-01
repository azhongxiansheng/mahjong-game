class_name Daisuushi

# 大四喜：东南西北 4 种全部成刻 → 双倍役満
const WINDS: Array = [TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N]

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	for d in wc.win_result.standard_decompositions:
		var wind_triplet := 0
		for m in wc.melds:
			if m.kind == Meld.Kind.CHI:
				continue
			if m.tiles[0].id in WINDS:
				wind_triplet += 1
		for meld_ids in d.melds:
			if meld_ids[0] == meld_ids[1] and meld_ids[1] == meld_ids[2]:
				if meld_ids[0] in WINDS:
					wind_triplet += 1
		if wind_triplet == 4:
			return YakuEntry.new(YakuId.DAISUUSHI, 0, true, 2)
	return null
