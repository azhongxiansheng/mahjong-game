class_name MenzenHelper

static func is_menzen(melds: Array[Meld]) -> bool:
	for m in melds:
		if m.kind != Meld.Kind.ANKAN:
			return false
	return true
