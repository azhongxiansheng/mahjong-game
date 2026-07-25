class_name CharacterAbilitySlot extends RefCounted

# E2-04 + E5-05：欢乐场角色能力槽。
# 构造期可创建对象；首窗默认 unarmed。
# active 武装仅本槽运行时态；pending 唯一真源在 ItemInventoryModule。

var seat: int = -1
var character_id: StringName = &""
var ability_id: StringName = &""
var skill: SkillResource = null
var armed: bool = false
var active_window_id = null # String | null
## registry 是否已注册当前 skill（armed 期间）
var registry_registered: bool = false


func _init(
	p_seat: int = -1,
	p_character_id: StringName = &"",
	p_ability_id: StringName = &"",
	p_skill: SkillResource = null,
	p_armed: bool = false
) -> void:
	seat = p_seat
	character_id = p_character_id
	ability_id = p_ability_id
	skill = p_skill
	armed = p_armed
	active_window_id = null
	registry_registered = false


func can_receive_hooks() -> bool:
	return armed and skill != null


func set_armed_for_window(window_id: String) -> void:
	armed = true
	active_window_id = window_id
	# 不改写 skill.params


func clear_active_keep_pending() -> void:
	armed = false
	active_window_id = null
	# 不改写 skill.params


func clear_all_arm() -> void:
	armed = false
	active_window_id = null
