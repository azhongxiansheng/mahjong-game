extends GutTest

const Catalog := preload("res://audio/character_voice_catalog.gd")


func test_qiu_jue_manifest_exposes_two_clips_for_all_six_events() -> void:
	var catalog = Catalog.new()
	for event_kind in ["entry", "ability", "advantage", "hurt", "win", "result_lose"]:
		var clips: Array = catalog.clip_paths(&"qiu_jue", StringName(event_kind))
		assert_eq(clips.size(), 2, "qiu_jue/%s 应有两个生产变体" % event_kind)
		for path in clips:
			assert_true(ResourceLoader.exists(String(path)), "%s 应是可加载的生产 WAV" % path)


func test_ying_li_manifest_exposes_two_clips_for_all_six_events() -> void:
	var catalog = Catalog.new()
	for event_kind in ["entry", "ability", "advantage", "hurt", "win", "result_lose"]:
		var clips: Array = catalog.clip_paths(&"ying_li", StringName(event_kind))
		assert_eq(clips.size(), 2, "ying_li/%s 应有两个生产变体" % event_kind)
		for path in clips:
			assert_true(ResourceLoader.exists(String(path)), "%s 应是可加载的生产 WAV" % path)


func test_lian_yao_manifest_exposes_two_clips_for_all_six_events() -> void:
	var catalog = Catalog.new()
	for event_kind in ["entry", "ability", "advantage", "hurt", "win", "result_lose"]:
		var clips: Array = catalog.clip_paths(&"lian_yao", StringName(event_kind))
		assert_eq(clips.size(), 2, "lian_yao/%s 应有两个生产变体" % event_kind)
		for path in clips:
			assert_true(ResourceLoader.exists(String(path)), "%s 应是可加载的生产 WAV" % path)


func test_bao_luo_manifest_exposes_two_clips_for_all_six_events() -> void:
	var catalog = Catalog.new()
	for event_kind in ["entry", "ability", "advantage", "hurt", "win", "result_lose"]:
		var clips: Array = catalog.clip_paths(&"bao_luo", StringName(event_kind))
		assert_eq(clips.size(), 2, "bao_luo/%s 应有两个生产变体" % event_kind)
		for path in clips:
			assert_true(ResourceLoader.exists(String(path)), "%s 应是可加载的生产 WAV" % path)


func test_catalog_rejects_unknown_character_or_event() -> void:
	var catalog = Catalog.new()
	assert_true(catalog.clip_paths(&"missing", &"entry").is_empty())
	assert_true(catalog.clip_paths(&"qiu_jue", &"missing").is_empty())
