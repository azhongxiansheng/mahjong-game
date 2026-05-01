class_name Suukantsu

# 四槓子：4 个杠（明杠 / 暗杠 / 加杠任意组合）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	var kan_count := 0
	for m in wc.melds:
		if m.is_kan():
			kan_count += 1
	if kan_count == 4:
		return YakuEntry.new(YakuId.SUUKANTSU, 0, true, 1)
	return null
