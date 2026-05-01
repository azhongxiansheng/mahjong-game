class_name YakuEvaluator

# 入口：传入 WinContext，返回 YakuList。
static func evaluate(wc: WinContext) -> YakuList:
	var list := YakuList.new()
	if not wc.win_result.is_winning:
		return list

	# Single-entry detectors
	var single_detectors := [
		Riichi,
		DoubleRiichi,
		Ippatsu,
		MenzenTsumo,
		Haitei,
		Houtei,
		Rinshan,
		Chankan,
		Pinfu,
		Iipeikou, Ryanpeikou, Tanyao,
		SanshokuDoujun, Ittsu,
		Toitoi, Sanankou, SanshokuDoukou, Sankantsu, Shousangen,
		Honchanta, Chiitoitsu, Junchan, Honitsu, Chinitsu,
	]
	for d in single_detectors:
		var entry: YakuEntry = d.detect(wc)
		if entry != null:
			list.add(entry)

	# Multi-entry detectors (return Array)
	for e in Yakuhai.detect_all(wc):
		list.add(e)

	return list
