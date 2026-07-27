class_name CharacterVoiceCatalog extends RefCounted

const MANIFEST_PATH := "res://assets/voice/characters/ja_voice_manifest.json"

var _characters: Dictionary = {}


func _init() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var manifest := parsed as Dictionary
	var characters: Variant = manifest.get("characters", {})
	if typeof(characters) == TYPE_DICTIONARY:
		_characters = characters as Dictionary


func clip_paths(character_id: StringName, event_kind: StringName) -> Array:
	var character: Variant = _characters.get(String(character_id), null)
	if typeof(character) != TYPE_DICTIONARY:
		return []
	var data := character as Dictionary
	var base_path := String(data.get("base_path", ""))
	var clips: Variant = data.get("clips", [])
	if base_path.is_empty() or typeof(clips) != TYPE_ARRAY:
		return []
	var result: Array = []
	for clip_value in clips as Array:
		if typeof(clip_value) != TYPE_DICTIONARY:
			continue
		var clip := clip_value as Dictionary
		if StringName(String(clip.get("event", ""))) != event_kind:
			continue
		var file_name := String(clip.get("file", ""))
		if not file_name.is_empty():
			result.append(base_path.path_join(file_name))
	return result
