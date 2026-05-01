class_name SkillResource extends Resource

@export var id: StringName
@export var display_name: String
@export var description: String
@export var rarity: int = 0
@export var attached_tile: int = -1
@export var is_ability: bool = false
@export var owner_triggers: Array[StringName] = []
@export var holder_triggers: Array[StringName] = []
@export var params: Dictionary = {}
@export var hook_script: GDScript

var consumed: bool = false
