class_name ItemSkillBuilder extends RefCounted


static func build(
	definition: ItemDefinition,
	item_instance_id: String = ""
) -> SkillResource:
	if definition == null \
			or definition.hook_resource_path.is_empty() \
			or definition.triggers.is_empty():
		return null
	var hook_script: GDScript = load(definition.hook_resource_path)
	if hook_script == null:
		return null
	var skill := SkillResource.new()
	skill.id = definition.id
	skill.display_name = definition.display_name
	skill.description = definition.description
	skill.rarity = definition.rarity
	skill.is_ability = true
	skill.owner_triggers = definition.triggers.duplicate()
	skill.hook_script = hook_script
	if not item_instance_id.is_empty():
		skill.params = skill.params.duplicate(true)
		skill.params["item_instance_id"] = item_instance_id
		skill.params["item_id"] = String(definition.id)
	return skill
