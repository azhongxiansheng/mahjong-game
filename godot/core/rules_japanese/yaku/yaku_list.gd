class_name YakuList

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
