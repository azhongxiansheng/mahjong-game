class_name YakuEntries

var entries: Array[YakuEntry] = []

func size() -> int:
	return entries.size()

func add(entry: YakuEntry) -> void:
	entries.append(entry)

func is_yakuman() -> bool:
	for e in entries:
		if e.is_yakuman:
			return true
	return false

func total_han() -> int:
	if is_yakuman():
		return 0
	var sum := 0
	for e in entries:
		sum += e.han
	return sum

func yakuman_total_multiplier() -> int:
	var total := 0
	for e in entries:
		if e.is_yakuman:
			total += e.yakuman_multiplier
	return total

func id_list() -> Array:
	var ids := []
	for e in entries:
		ids.append(e.yaku_id)
	return ids

# 上位役覆盖下位役。trigger_id 触发时，被覆盖的 id 从 entries 移除。
const EXCLUSIONS: Dictionary = {
	YakuId.RYANPEIKOU: [YakuId.IIPEIKOU],
	YakuId.CHINITSU: [YakuId.HONITSU],
	YakuId.JUNCHAN: [YakuId.HONCHANTA],
	YakuId.DAISANGEN: [YakuId.YAKUHAI_HAKU, YakuId.YAKUHAI_HATSU, YakuId.YAKUHAI_CHUN, YakuId.SHOUSANGEN],
	YakuId.DAISUUSHI: [YakuId.YAKUHAI_BAKAZE, YakuId.YAKUHAI_JIKAZE, YakuId.SHOUSUUSHI, YakuId.TOITOI],
	YakuId.SUUANKOU: [YakuId.TOITOI, YakuId.SANANKOU],
	YakuId.SUUANKOU_TANKI: [YakuId.TOITOI, YakuId.SANANKOU, YakuId.SUUANKOU],
	YakuId.KOKUSHI_13: [YakuId.KOKUSHI],
	YakuId.JUNSEI_CHUUREN: [YakuId.CHUUREN],
	YakuId.TSUUIISOU: [YakuId.HONITSU, YakuId.HONCHANTA, YakuId.YAKUHAI_HAKU, YakuId.YAKUHAI_HATSU, YakuId.YAKUHAI_CHUN, YakuId.YAKUHAI_BAKAZE, YakuId.YAKUHAI_JIKAZE, YakuId.SHOUSANGEN, YakuId.SHOUSUUSHI],
	YakuId.CHINROUTOU: [YakuId.HONCHANTA, YakuId.JUNCHAN, YakuId.TOITOI],
	YakuId.RYUUIISOU: [YakuId.HONITSU, YakuId.YAKUHAI_HATSU],
	YakuId.SUUKANTSU: [YakuId.SANKANTSU, YakuId.TOITOI],
}

func apply_exclusions() -> void:
	if entries.is_empty():
		return
	var active_ids: Dictionary = {}
	for e in entries:
		active_ids[e.yaku_id] = true
	var to_remove: Dictionary = {}
	for trigger_id in EXCLUSIONS:
		if active_ids.has(trigger_id):
			for excluded_id in EXCLUSIONS[trigger_id]:
				to_remove[excluded_id] = true
	if to_remove.is_empty():
		return
	var new_entries: Array[YakuEntry] = []
	for e in entries:
		if not to_remove.has(e.yaku_id):
			new_entries.append(e)
	entries = new_entries
