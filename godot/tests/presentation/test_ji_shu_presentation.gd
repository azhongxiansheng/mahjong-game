extends GutTest


func _event(type: StringName, actor: int, extra: Dictionary = {}) -> BattleEvent:
	return BattleEvent.make(type, actor, null, extra)


func test_real_trigger_feedback_and_six_voice_categories_do_not_cross_talk() -> void:
	var router := CharacterPresentationRouter.new(CharacterPresentationCatalog.active_profiles())
	router.bind_characters([&"ji_shu", &"qiu_jue", &"hua_ling", &"lin_yeche"])
	var entry := router.voice_requests_for_event(_event(&"GAME_BEGIN", 0))
	assert_eq(entry.size(), 1)
	assert_eq(entry[0].event_kind, &"entry")
	assert_eq(entry[0].priority, 10)
	var skill_event := _event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_nodoka_passive_v1",
		"skill_name": "纪枢·概率圣裁",
		"source_event": "TENPAI_ENTERED",
	})
	var ability := router.voice_requests_for_event(skill_event)
	assert_eq(ability.size(), 1)
	assert_eq(ability[0].event_kind, &"ability")
	assert_eq(ability[0].priority, 20)
	var feedback := router.feedback_for_event(skill_event)
	assert_true(String(feedback.get("text", "")).contains("等待牌已揭示"))
	assert_eq(feedback.get("position"), Vector2(420, 84))
	assert_eq(router.voice_requests_for_event(_event(&"WIN_DECLARED", 0,
		{"is_tsumo": true}))[0].event_kind, &"win")
	var hurt := router.voice_requests_for_event(_event(&"WIN_DECLARED", 1,
		{"is_tsumo": false, "discarder_seat": 0})).filter(
			func(request): return request.character_id == &"ji_shu")
	assert_eq(hurt.size(), 1)
	assert_eq(hurt[0].event_kind, &"hurt")
	assert_eq(router.voice_requests_for_scores([30000, 25000, 24000, 21000])[0]
		.event_kind, &"advantage")
	assert_eq(router.voice_requests_for_match_result([20000, 30000, 25000, 25000])[0]
		.event_kind, &"result_lose")
	assert_true(router.voice_requests_for_event(_event(&"SKILL_TRIGGERED", 1, {
		"skill_id": &"char_nodoka_passive_v1",
		"skill_name": "纪枢·概率圣裁",
		"source_event": "TENPAI_ENTERED",
	})).is_empty(), "角色与席位不匹配时不得串音")
