class_name Sanankou

# 三暗刻：3 个暗刻（被荣胡的刻子算明刻不算暗刻）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	# 副露中的暗杠 = 暗刻贡献
	var ankan_count := 0
	for m in wc.melds:
		if m.kind == Meld.Kind.ANKAN:
			ankan_count += 1
	# 暗牌中的刻子，遍历分解取最大暗刻数
	var best := 0
	for d in wc.win_result.standard_decompositions:
		var count := ankan_count
		for meld_ids in d.melds:
			if meld_ids[0] == meld_ids[1] and meld_ids[1] == meld_ids[2]:
				# 刻子。若是被荣胡的刻子（winning_tile 是该刻子成员且非自摸），算明刻
				if meld_ids[0] == wc.winning_tile.id and not wc.game_context.is_tsumo:
					pass  # 明刻
				else:
					count += 1
		if count > best:
			best = count
	if best >= 3:
		return YakuEntry.new(YakuId.SANANKOU, 2, false, 0)
	return null
