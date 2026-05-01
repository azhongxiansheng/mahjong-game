class_name Sankantsu

# 三杠子：3 个杠（任意类型）
static func detect(wc: WinContext) -> YakuEntry:
	if not wc.win_result.is_winning:
		return null
	var kan_count := 0
	for m in wc.melds:
		if m.is_kan():
			kan_count += 1
	if kan_count == 3:
		return YakuEntry.new(YakuId.SANKANTSU, 2, false, 0)
	return null
