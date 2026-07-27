class_name CharacterPresentationProfile extends RefCounted

var character_id: StringName
var ability_id: StringName
var feedback_template: String
var feedback_color: Color
var feedback_pulse: bool
var viewer_reveal_label: String
var next_draw_reveal_label: String
var seat_draw_forecast_label: String
var status_param: StringName
var status_text: String
var status_color: Color
var feedback_templates_by_source: Dictionary
var status_next_offset: int
var feedback_position: Vector2


func _init(
	p_character_id: StringName = &"",
	p_ability_id: StringName = &"",
	p_feedback_template: String = "",
	p_feedback_color: Color = Color(1, 0.88, 0.32),
	p_feedback_pulse: bool = false,
	p_viewer_reveal_label: String = "",
	p_next_draw_reveal_label: String = "",
	p_status_param: StringName = &"",
	p_status_text: String = "",
	p_status_color: Color = Color(0.66, 0.63, 0.78),
	p_feedback_templates_by_source: Dictionary = {},
	p_feedback_position: Vector2 = Vector2(420, 12),
	p_status_next_offset: int = 0,
	p_seat_draw_forecast_label: String = ""
) -> void:
	character_id = p_character_id
	ability_id = p_ability_id
	feedback_template = p_feedback_template
	feedback_color = p_feedback_color
	feedback_pulse = p_feedback_pulse
	viewer_reveal_label = p_viewer_reveal_label
	next_draw_reveal_label = p_next_draw_reveal_label
	status_param = p_status_param
	status_text = p_status_text
	status_color = p_status_color
	feedback_templates_by_source = p_feedback_templates_by_source.duplicate()
	status_next_offset = p_status_next_offset
	feedback_position = p_feedback_position
	seat_draw_forecast_label = p_seat_draw_forecast_label


func is_valid() -> bool:
	return character_id != &"" and ability_id != &"" and not feedback_template.is_empty()


func format_feedback(skill_name: String, extra: Dictionary = {}) -> String:
	if not is_valid() or skill_name.is_empty():
		return ""
	var source_event := StringName(String(extra.get("source_event", "")))
	var template := feedback_template
	if feedback_templates_by_source.has(source_event):
		template = String(feedback_templates_by_source[source_event])
	return template.format({
		"skill_name": skill_name.replace("·", " · "),
		"han_delta": int(extra.get("han_delta", 0)),
	})


func has_active_status(skill: SkillResource) -> bool:
	return skill != null and status_param != &"" and not status_text.is_empty() \
		and bool(skill.params.get(status_param, false))


func format_status(skill: SkillResource) -> String:
	if not has_active_status(skill):
		return ""
	var value := int(skill.params.get(status_param, 0))
	return status_text.format({
		"value": value,
		"next": value + status_next_offset,
	})
