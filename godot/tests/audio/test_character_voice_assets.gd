extends GutTest


const MANIFEST_PATH := "res://assets/voice/characters/ja_voice_manifest.json"
const CHARACTER_IDS := [
	"qiu_jue",
	"lin_yeche",
	"bai_touli",
	"hua_ling",
	"ying_li",
	"an_cheng",
	"yuan_xi",
	"ji_shu",
	"xian_shi",
	"bao_luo",
	"lian_yao",
	"ju_jin",
]
const EVENTS := ["entry", "ability", "advantage", "hurt", "win", "result_lose"]


func _load_manifest() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


func test_manifest_maps_two_japanese_lines_per_event_and_character() -> void:
	assert_true(FileAccess.file_exists(MANIFEST_PATH), "日语角色语音 manifest 应存在")
	var manifest := _load_manifest()
	assert_false(manifest.is_empty(), "日语角色语音 manifest 应为合法 JSON object")
	if manifest.is_empty():
		return
	assert_eq(manifest.get("language", ""), "ja")
	assert_eq(manifest.get("model", ""), "fish-s2-pro")
	var characters: Dictionary = manifest.get("characters", {})
	assert_eq(characters.keys().size(), CHARACTER_IDS.size())
	for character_id in CHARACTER_IDS:
		assert_true(characters.has(character_id), "%s 应存在语音映射" % character_id)
		if not characters.has(character_id):
			continue
		var clips: Array = characters[character_id].get("clips", [])
		assert_eq(clips.size(), EVENTS.size() * 2, "%s 应有 12 条语音" % character_id)
		var event_counts: Dictionary = {}
		var file_names: Dictionary = {}
		for clip: Dictionary in clips:
			var event: String = clip.get("event", "")
			event_counts[event] = int(event_counts.get(event, 0)) + 1
			var file_name: String = clip.get("file", "")
			assert_false(file_name.is_empty(), "%s 的语音文件名不得为空" % character_id)
			assert_false(file_names.has(file_name), "%s 的语音文件名不得重复" % character_id)
			file_names[file_name] = true
			assert_false(String(clip.get("text", "")).is_empty(), "%s 的日语台词不得为空" % character_id)
		for event in EVENTS:
			assert_eq(int(event_counts.get(event, 0)), 2, "%s/%s 应有两个变体" % [character_id, event])


func test_all_manifest_clips_load_as_offline_48k_mono_pcm16() -> void:
	var manifest := _load_manifest()
	assert_false(manifest.is_empty(), "manifest 缺失时不能验证语音文件")
	if manifest.is_empty():
		return
	var characters: Dictionary = manifest["characters"]
	for character_id in CHARACTER_IDS:
		var base_path := "res://assets/voice/characters/%s/ja" % character_id
		for clip: Dictionary in characters[character_id]["clips"]:
			var path := base_path.path_join(String(clip["file"]))
			assert_true(ResourceLoader.exists(path), "%s 应存在" % path)
			if not ResourceLoader.exists(path):
				continue
			var stream := ResourceLoader.load(path) as AudioStreamWAV
			assert_not_null(stream, "%s 应可加载为 AudioStreamWAV" % path)
			if stream == null:
				continue
			assert_eq(stream.mix_rate, 48000, "%s 应为 48kHz" % path)
			assert_false(stream.stereo, "%s 应为 mono" % path)
			assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, "%s 应为 PCM16" % path)
			assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, "%s 不应循环" % path)
