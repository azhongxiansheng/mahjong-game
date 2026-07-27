class_name ItemDefinition extends RefCounted

const HELD_STATUS := "held"

enum Category {
	CONSUMABLE,
	RELIC,
}

enum UseMode {
	UNAVAILABLE,
	IMMEDIATE,
	ARMED,
	PASSIVE,
}

var id: StringName
var display_name: String
var description: String
var rarity: int
var category: int
var use_mode: int
var triggers: Array[StringName] = []
var hook_resource_path: String
var table_icon_path: String
var is_grantable: bool


func _init(
	p_id: StringName = &"",
	p_display_name: String = "",
	p_description: String = "",
	p_rarity: int = Rarity.Kind.COMMON,
	p_category: int = Category.CONSUMABLE,
	p_use_mode: int = UseMode.UNAVAILABLE,
	p_triggers: Array = [],
	p_hook_resource_path: String = "",
	p_table_icon_path: String = "",
	p_is_grantable: bool = false
) -> void:
	id = p_id
	display_name = p_display_name
	description = p_description
	rarity = p_rarity
	category = p_category
	use_mode = p_use_mode
	for trigger in p_triggers:
		triggers.append(StringName(String(trigger)))
	hook_resource_path = p_hook_resource_path
	table_icon_path = p_table_icon_path
	is_grantable = p_is_grantable


func is_valid() -> bool:
	return id != &"" \
		and not display_name.is_empty() \
		and not description.is_empty() \
		and (category == Category.CONSUMABLE or category == Category.RELIC) \
		and use_mode >= UseMode.UNAVAILABLE and use_mode <= UseMode.PASSIVE


func is_consumable() -> bool:
	return category == Category.CONSUMABLE


func is_relic() -> bool:
	return category == Category.RELIC


func can_use(status: String) -> bool:
	return status == HELD_STATUS \
		and (use_mode == UseMode.IMMEDIATE or use_mode == UseMode.ARMED)
