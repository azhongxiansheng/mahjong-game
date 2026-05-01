class_name Yakuhai

# detect_all: 一手可同时含多个役牌 → 返回 Array
static func detect_all(wc: WinContext) -> Array:
	var result: Array = []
	if not wc.win_result.is_winning:
		return result
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return result

	var triplet_ids: Array = []
	# 副露中的刻子/杠子
	for m in wc.melds:
		match m.kind:
			Meld.Kind.PON, Meld.Kind.MINKAN, Meld.Kind.ANKAN, Meld.Kind.ADDED_KAN:
				triplet_ids.append(m.tiles[0].id)
	# 暗牌中的刻子（从 standard_decompositions 第一个分解读取）
	if wc.win_result.standard_decompositions.size() > 0:
		var d = wc.win_result.standard_decompositions[0]
		for meld_ids in d.melds:
			if meld_ids[0] == meld_ids[1] and meld_ids[1] == meld_ids[2]:
				triplet_ids.append(meld_ids[0])

	for tid in triplet_ids:
		match tid:
			TileId.HAKU:
				result.append(YakuEntry.new(YakuId.YAKUHAI_HAKU, 1, false, 0))
			TileId.HATSU:
				result.append(YakuEntry.new(YakuId.YAKUHAI_HATSU, 1, false, 0))
			TileId.CHUN:
				result.append(YakuEntry.new(YakuId.YAKUHAI_CHUN, 1, false, 0))
			TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N:
				if tid == wc.game_context.bakaze:
					result.append(YakuEntry.new(YakuId.YAKUHAI_BAKAZE, 1, false, 0))
				if tid == wc.game_context.jikaze:
					result.append(YakuEntry.new(YakuId.YAKUHAI_JIKAZE, 1, false, 0))
	return result
