class_name YakuEntry

var yaku_id: int
var han: int
var is_yakuman: bool
var yakuman_multiplier: int

func _init(p_id: int, p_han: int, p_is_yakuman: bool, p_yakuman_multiplier: int) -> void:
	yaku_id = p_id
	han = p_han
	is_yakuman = p_is_yakuman
	yakuman_multiplier = p_yakuman_multiplier

func name_zh() -> String:
	return YakuId.metadata(yaku_id).name_zh
