class_name ActionSource extends RefCounted

const HUMAN := &"HUMAN"
const AI := &"AI"
const REPLAY := &"REPLAY"


static func is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING_NAME:
		return false
	return value == HUMAN or value == AI or value == REPLAY
