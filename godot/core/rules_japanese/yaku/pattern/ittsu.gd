class_name Ittsu

# 一気通貫：同一花色的 123+456+789（同色 1-4-7 三组顺子）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	if wc.win_result.is_chiitoi or wc.win_result.is_kokushi:
		return null
	# By suit, collect set of start numbers (1, 4, 7)
	var by_suit: Dictionary = {}
	for s in SanshokuDoujun._collect_all_sequences(wc):
		if TileId.is_honor(s[0]):
			continue
		var suit: int = TileId.suit(s[0])
		var num: int = TileId.number(s[0])
		if not by_suit.has(suit):
			by_suit[suit] = {}
		by_suit[suit][num] = true
	for suit in by_suit:
		var nums: Dictionary = by_suit[suit]
		if nums.has(1) and nums.has(4) and nums.has(7):
			var han: int = 2 if wc.is_menzen() else 1
			return YakuEntry.new(YakuId.ITTSU, han, false, 0)
	return null
