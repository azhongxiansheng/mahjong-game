class_name CharacterPresentationRouter extends RefCounted

const CharacterVoicePolicyScript := preload(
	"res://presentation/characters/character_voice_policy.gd")

var _profiles_by_ability: Dictionary = {}
var _registered_characters: Dictionary = {}
var _policies: Array = []
var _character_ids: Array = []


func _init(profiles: Array = []) -> void:
	for profile_value in profiles:
		if not (profile_value is CharacterPresentationProfile):
			continue
		var profile := profile_value as CharacterPresentationProfile
		if not profile.is_valid() or _profiles_by_ability.has(profile.ability_id) \
				or _registered_characters.has(profile.character_id):
			continue
		_profiles_by_ability[profile.ability_id] = profile
		_registered_characters[profile.character_id] = true
		_policies.append(CharacterVoicePolicyScript.new(profile))


func bind_characters(character_ids: Array) -> void:
	_character_ids = character_ids.duplicate()
	for policy in _policies:
		policy.bind_characters(_character_ids)


func voice_requests_for_event(event: BattleEvent) -> Array:
	var requests: Array = []
	for policy in _policies:
		requests.append_array(policy.requests_for_event(event))
	return requests


func voice_requests_for_scores(scores: Array) -> Array:
	var requests: Array = []
	for policy in _policies:
		requests.append_array(policy.requests_for_scores(scores))
	return requests


func voice_requests_for_match_result(final_scores: Array) -> Array:
	var requests: Array = []
	for policy in _policies:
		requests.append_array(policy.requests_for_match_result(final_scores))
	return requests


func feedback_for_event(event: BattleEvent) -> Dictionary:
	if event == null or event.type != &"SKILL_TRIGGERED":
		return {}
	var ability_id := StringName(String(event.extra.get("skill_id", "")))
	var profile_value: Variant = _profiles_by_ability.get(ability_id, null)
	if not (profile_value is CharacterPresentationProfile):
		return {}
	var profile := profile_value as CharacterPresentationProfile
	if _character_at(event.actor_seat) != profile.character_id:
		return {}
	var text := profile.format_feedback(String(event.extra.get("skill_name", "")))
	if text.is_empty():
		return {}
	return {
		"text": text,
		"color": profile.feedback_color,
		"pulse": profile.feedback_pulse,
	}


func reveal_label_for_local_character(local_seat: int = 0) -> String:
	var character_id := _character_at(local_seat)
	if not _registered_characters.has(character_id):
		return ""
	for profile_value in _profiles_by_ability.values():
		var profile := profile_value as CharacterPresentationProfile
		if profile.character_id == character_id:
			return profile.viewer_reveal_label
	return ""


func status_for_registry(registry: SkillRegistry, viewer_seat: int) -> Dictionary:
	if registry == null or _character_at(viewer_seat) == &"":
		return {}
	for entry_value in registry.get_all_entries():
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry := entry_value as Dictionary
		var anchor_value: Variant = entry.get("anchor", null)
		if typeof(anchor_value) != TYPE_INT or int(anchor_value) != viewer_seat:
			continue
		var skill := entry.get("skill") as SkillResource
		if skill == null:
			continue
		var profile_value: Variant = _profiles_by_ability.get(skill.id, null)
		if not (profile_value is CharacterPresentationProfile):
			continue
		var profile := profile_value as CharacterPresentationProfile
		if _character_at(viewer_seat) != profile.character_id \
				or not profile.has_active_status(skill):
			continue
		return {
			"character_id": profile.character_id,
			"text": profile.status_text,
			"color": profile.status_color,
		}
	return {}


func _character_at(seat: int) -> StringName:
	if seat < 0 or seat >= _character_ids.size():
		return &""
	return StringName(String(_character_ids[seat]))
