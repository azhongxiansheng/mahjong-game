class_name YakuEvaluator

# 入口：传入 WinContext，返回 YakuList。
# 当前注册 8 个 state detector。后续 task 逐步追加 yakuhai / pattern / yakuman。
static func evaluate(wc: WinContext) -> YakuList:
	var list := YakuList.new()
	if not wc.win_result.is_winning:
		return list

	var detectors := [
		Riichi,
		DoubleRiichi,
		Ippatsu,
		MenzenTsumo,
		Haitei,
		Houtei,
		Rinshan,
		Chankan,
	]
	for d in detectors:
		var entry: YakuEntry = d.detect(wc)
		if entry != null:
			list.add(entry)
	return list
