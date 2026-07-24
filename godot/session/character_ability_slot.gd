class_name CharacterAbilitySlot extends RefCounted

# E2-04：欢乐场角色能力槽（生产模块）。
# 对象可在构造期创建；首个奖励窗口默认 unarmed，不得接收 hook。

var seat: int = -1
var character_id: StringName = &""
var ability_id: StringName = &""
var skill: SkillResource = null
var armed: bool = false


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


func can_receive_hooks() -> bool:
	return armed and skill != null
