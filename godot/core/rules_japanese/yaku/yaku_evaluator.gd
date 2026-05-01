class_name YakuEvaluator

# 入口：传入 WinContext，返回 YakuEntries。
static func evaluate(wc: WinContext) -> YakuEntries:
	var list := YakuEntries.new()
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
		# Yakuman
		KokushiYakuman, Daisangen, Tsuuiisou, Ryuuiisou, Chinroutou,
		Suuankou, Suukantsu, Shousuushi, Daisuushi,
		Chuuren, Tenhou, Chiihou,
	]
	for d in single_detectors:
		var entry: YakuEntry = d.detect(wc)
		if entry != null:
			list.add(entry)

	# Multi-entry detectors (return Array)
	for e in Yakuhai.detect_all(wc):
		list.add(e)

	list.apply_exclusions()
	return list
