class_name Shousangen

# 小三元：三元牌 2 刻 + 1 对
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	for d in wc.win_result.standard_decompositions:
		var dragon_pon := 0
		# 副露中的三元刻
		for m in wc.melds:
			if m.kind != Meld.Kind.CHI and m.tiles.size() >= 3:
				var t0: int = m.tiles[0].id
				if t0 == TileId.HAKU or t0 == TileId.HATSU or t0 == TileId.CHUN:
					dragon_pon += 1
		# 暗 melds 中的三元刻
		for meld_ids in d.melds:
			if meld_ids[0] == meld_ids[1] and meld_ids[1] == meld_ids[2]:
				var t0: int = meld_ids[0]
				if t0 == TileId.HAKU or t0 == TileId.HATSU or t0 == TileId.CHUN:
					dragon_pon += 1
		# 雀头三元
		var dragon_pair: bool = (d.pair == TileId.HAKU or d.pair == TileId.HATSU or d.pair == TileId.CHUN)
		if dragon_pon == 2 and dragon_pair:
			return YakuEntry.new(YakuId.SHOUSANGEN, 2, false, 0)
	return null
