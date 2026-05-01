class_name Suuankou

# 四暗刻：4 个暗刻 + 1 雀头。雀头単騎時 → 双倍役満（SUUANKOU_TANKI）
# 副露只允许 ANKAN（明刻 / 明杠 / 吃 → 不暗）；荣胡完成的刻子算明刻
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	for m in wc.melds:
		if m.kind != Meld.Kind.ANKAN:
			return null
	if wc.win_result.standard_decompositions.size() == 0:
		return null
	var ankan_count := wc.melds.size()  # 此时 melds 全是 ANKAN
	for d in wc.win_result.standard_decompositions:
		var triplet_count := ankan_count
		var ron_breaks_concealment := false
		var all_triplets := true
		for meld_ids in d.melds:
			if meld_ids[0] != meld_ids[1]:
				all_triplets = false
				break
			triplet_count += 1
			# 荣胡完成的刻子是明刻
			if meld_ids[0] == wc.winning_tile.id and not wc.game_context.is_tsumo:
				ron_breaks_concealment = true
		if not all_triplets:
			continue
		if triplet_count != 4:
			continue
		# 全暗 — 雀头単騎判定（自摸或荣胡都可视情况判定単騎）
		# 単騎条件：和牌张 == 雀头牌（且 4 个刻子全暗）
		if wc.winning_tile.id == d.pair:
			if ron_breaks_concealment:
				# 雀头単騎不可能同时让某刻子被荣 — 此分支理论不会触发；保留兜底
				return YakuEntry.new(YakuId.SUUANKOU, 0, true, 1)
			return YakuEntry.new(YakuId.SUUANKOU_TANKI, 0, true, 2)
		# 非単騎 — 必须自摸才算 4 暗刻（荣胡破坏暗刻）
		if ron_breaks_concealment:
			continue
		return YakuEntry.new(YakuId.SUUANKOU, 0, true, 1)
	return null
