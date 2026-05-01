class_name Shousuushi

# 小四喜：东南西北中 3 种成刻 + 1 种为雀头
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
		var wind_pair: bool = d.pair in WINDS
		if wind_triplet == 3 and wind_pair:
			return YakuEntry.new(YakuId.SHOUSUUSHI, 0, true, 1)
	return null
