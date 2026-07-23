class_name SessionIntent extends RefCounted

# 大厅纯 UI 选择态（E1-04 / #228）。
# 只承载玩家选择，不含正式会话构造所需的权威字段。

var room_kind: StringName = &"PRACTICE"
var round_kind: StringName = &"EAST"
var game_mode: StringName = &"STANDARD"
var selected_character_id: StringName = &""


func _init(
	p_room_kind: StringName = &"PRACTICE",
	p_round_kind: StringName = &"EAST",
	p_game_mode: StringName = &"STANDARD",
	p_selected_character_id: StringName = &""
) -> void:
	room_kind = p_room_kind
	round_kind = p_round_kind
	game_mode = p_game_mode
	selected_character_id = p_selected_character_id


## 将三维选择稳定还原为 8 个 mode_id 之一。
func mode_id() -> StringName:
	var room_token := "PUBLIC" if room_kind == &"PUBLIC_CASUAL" else String(room_kind)
	return StringName("%s_%s_%s" % [room_token, String(round_kind), String(game_mode)])
