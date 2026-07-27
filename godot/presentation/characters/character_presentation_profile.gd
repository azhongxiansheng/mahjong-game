class_name CharacterPresentationProfile extends RefCounted

var character_id: StringName
var ability_id: StringName
var feedback_template: String
var feedback_color: Color
var feedback_pulse: bool
var viewer_reveal_label: String
var status_param: StringName
var status_text: String
var status_color: Color


func _init(
	p_character_id: StringName = &"",
	p_ability_id: StringName = &"",
	p_feedback_template: String = "",
	p_feedback_color: Color = Color(1, 0.88, 0.32),
	p_feedback_pulse: bool = false,
	p_viewer_reveal_label: String = "",
	p_status_param: StringName = &"",
	p_status_text: String = "",
	p_status_color: Color = Color(0.66, 0.63, 0.78)
) -> void:
	character_id = p_character_id
	ability_id = p_ability_id
	feedback_template = p_feedback_template
	feedback_color = p_feedback_color
	feedback_pulse = p_feedback_pulse
	viewer_reveal_label = p_viewer_reveal_label
	status_param = p_status_param
	status_text = p_status_text
	status_color = p_status_color


func is_valid() -> bool:
	return character_id != &"" and ability_id != &"" and not feedback_template.is_empty()


func format_feedback(skill_name: String) -> String:
	if not is_valid() or skill_name.is_empty():
		return ""
	return feedback_template.format({"skill_name": skill_name.replace("·", " · ")})


func has_active_status(skill: SkillResource) -> bool:
	return skill != null and status_param != &"" and not status_text.is_empty() \
		and bool(skill.params.get(status_param, false))
