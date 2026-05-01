class_name Ryanpeikou

static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	# kokushi cannot be ryanpeikou; chiitoi hands CAN be ryanpeikou — ryanpeikou takes precedence
	if wc.win_result.is_kokushi:
		return null
	if not wc.is_menzen():
		return null
	for d in wc.win_result.standard_decompositions:
		var pairs := Iipeikou._count_identical_sequence_pairs(d)
		if pairs >= 2:
			return YakuEntry.new(YakuId.RYANPEIKOU, 3, false, 0)
	return null
