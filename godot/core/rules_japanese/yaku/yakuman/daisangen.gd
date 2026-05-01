class_name Daisangen

# 大三元：白 / 发 / 中 全部成刻（含明刻、暗刻、明杠、暗杠、加杠均可）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	for d in wc.win_result.standard_decompositions:
		var dragons := {TileId.HAKU: false, TileId.HATSU: false, TileId.CHUN: false}
		# 副露中三元刻 / 杠
		for m in wc.melds:
			if m.kind == Meld.Kind.CHI:
				continue
			var t0: int = m.tiles[0].id
			if dragons.has(t0):
				dragons[t0] = true
		# 暗 melds 中三元刻
		for meld_ids in d.melds:
			if meld_ids[0] == meld_ids[1] and meld_ids[1] == meld_ids[2]:
				var t0: int = meld_ids[0]
				if dragons.has(t0):
					dragons[t0] = true
		if dragons[TileId.HAKU] and dragons[TileId.HATSU] and dragons[TileId.CHUN]:
			return YakuEntry.new(YakuId.DAISANGEN, 0, true, 1)
	return null
