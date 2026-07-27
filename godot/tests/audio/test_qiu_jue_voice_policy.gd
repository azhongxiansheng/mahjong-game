extends GutTest

const Catalog := preload(
	"res://presentation/characters/character_presentation_catalog.gd")
const Policy := preload("res://presentation/characters/character_voice_policy.gd")


func _event(type: StringName, actor: int, extra: Dictionary = {}) -> BattleEvent:
	return BattleEvent.make(type, actor, null, extra)


func _policy(ids: Array = [&"qiu_jue", &"lin_yeche", &"bai_touli", &"hua_ling"]):
	var policy = Policy.new(Catalog.active_profiles()[0])
	policy.bind_characters(ids)
	return policy


func _bai_policy(ids: Array = [&"bai_touli", &"qiu_jue", &"lin_yeche", &"hua_ling"]):
	var profile = null
	for candidate in Catalog.active_profiles():
		if candidate.character_id == &"bai_touli":
			profile = candidate
			break
	var policy = Policy.new(profile)
	policy.bind_characters(ids)
	return policy


func _an_cheng_policy(ids: Array = [&"an_cheng", &"qiu_jue", &"lin_yeche", &"hua_ling"]):
	var profile = null
	for candidate in Catalog.active_profiles():
		if candidate.character_id == &"an_cheng":
			profile = candidate
			break
	var policy = Policy.new(profile)
	policy.bind_characters(ids)
	return policy


func test_entry_plays_once_for_local_qiu_jue() -> void:
	var policy = _policy()
	var first: Array = policy.requests_for_event(_event(&"GAME_BEGIN", 2))
	assert_eq(first.size(), 1)
	assert_eq(first[0].event_kind, &"entry")
	assert_true(policy.requests_for_event(_event(&"GAME_BEGIN", 1)).is_empty())


func test_entry_does_not_play_when_local_character_is_not_qiu_jue() -> void:
	var policy = _policy([&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"])
	assert_true(policy.requests_for_event(_event(&"GAME_BEGIN", 0)).is_empty())


func test_ability_requires_real_qiu_jue_skill_and_matching_actor() -> void:
	var policy = _policy()
	var requests: Array = policy.requests_for_event(_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_kaiji_passive_v1",
	}))
	assert_eq(requests.size(), 1)
	assert_eq(requests[0].event_kind, &"ability")
	assert_eq(requests[0].priority, 20)
	assert_true(policy.requests_for_event(_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_saki_passive_v1",
	})).is_empty())
	assert_true(policy.requests_for_event(_event(&"SKILL_TRIGGERED", 1, {
		"skill_id": &"char_kaiji_passive_v1",
	})).is_empty())


func test_win_and_deal_in_map_to_win_and_hurt() -> void:
	var policy = _policy([&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"])
	var win: Array = policy.requests_for_event(_event(&"WIN_DECLARED", 1, {
		"discarder_seat": 3,
		"is_tsumo": false,
	}))
	assert_eq(win.size(), 1)
	assert_eq(win[0].event_kind, &"win")
	var hurt: Array = policy.requests_for_event(_event(&"WIN_DECLARED", 2, {
		"discarder_seat": 1,
		"is_tsumo": false,
	}))
	assert_eq(hurt.size(), 1)
	assert_eq(hurt[0].event_kind, &"hurt")
	assert_true(policy.requests_for_event(_event(&"WIN_DECLARED", 2, {
		"is_tsumo": true,
	})).is_empty(), "自摸失分不应触发三家 hurt")


func test_advantage_only_fires_when_qiu_jue_becomes_unique_leader() -> void:
	var policy = _policy([&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"])
	assert_true(policy.requests_for_scores([25000, 25000, 25000, 25000]).is_empty())
	var lead: Array = policy.requests_for_scores([24000, 27000, 25000, 24000])
	assert_eq(lead.size(), 1)
	assert_eq(lead[0].event_kind, &"advantage")
	assert_true(policy.requests_for_scores([23000, 28000, 25000, 24000]).is_empty(),
		"保持领先不应每局重复播放")


func test_result_lose_only_applies_to_local_qiu_jue_without_first_place() -> void:
	var policy = _policy()
	var lose: Array = policy.requests_for_match_result([24000, 27000, 25000, 24000])
	assert_eq(lose.size(), 1)
	assert_eq(lose[0].event_kind, &"result_lose")
	assert_true(policy.requests_for_match_result([28000, 27000, 25000, 20000]).is_empty())


func test_bai_touli_six_offline_voice_categories_and_match_reset() -> void:
	var policy = _bai_policy()
	assert_eq(policy.requests_for_event(_event(&"GAME_BEGIN", 0))[0].event_kind, &"entry")
	assert_eq(policy.requests_for_event(_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_washizu_passive_v1",
	}))[0].event_kind, &"ability")
	assert_eq(policy.requests_for_scores([28000, 24000, 24000, 24000])[0].event_kind,
		&"advantage")
	assert_eq(policy.requests_for_event(_event(&"WIN_DECLARED", 1, {
		"discarder_seat": 0, "is_tsumo": false,
	}))[0].event_kind, &"hurt")
	assert_eq(policy.requests_for_event(_event(&"WIN_DECLARED", 0, {
		"discarder_seat": 2, "is_tsumo": false,
	}))[0].event_kind, &"win")
	assert_eq(policy.requests_for_match_result([24000, 27000, 25000, 24000])[0].event_kind,
		&"result_lose")
	policy.bind_characters([&"bai_touli", &"qiu_jue", &"lin_yeche", &"hua_ling"])
	assert_eq(policy.requests_for_event(_event(&"GAME_BEGIN", 0)).size(), 1,
		"新一场重新绑定后 entry 可再次播放")


func test_an_cheng_six_offline_voice_categories_without_cross_talk() -> void:
	var policy = _an_cheng_policy()
	assert_eq(policy.requests_for_event(_event(&"GAME_BEGIN", 0))[0].event_kind, &"entry")
	assert_eq(policy.requests_for_event(_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_awai_passive_v1",
	}))[0].event_kind, &"ability")
	assert_true(policy.requests_for_event(_event(&"SKILL_TRIGGERED", 1, {
		"skill_id": &"char_awai_passive_v1",
	})).is_empty(), "非安澄青座位不得串 ability 语音")
	assert_eq(policy.requests_for_scores([28000, 24000, 24000, 24000])[0].event_kind,
		&"advantage")
	assert_eq(policy.requests_for_event(_event(&"WIN_DECLARED", 1, {
		"discarder_seat": 0, "is_tsumo": false,
	}))[0].event_kind, &"hurt")
	assert_eq(policy.requests_for_event(_event(&"WIN_DECLARED", 0, {
		"discarder_seat": 2, "is_tsumo": false,
	}))[0].event_kind, &"win")
	assert_eq(policy.requests_for_match_result([24000, 27000, 25000, 24000])[0].event_kind,
		&"result_lose")
