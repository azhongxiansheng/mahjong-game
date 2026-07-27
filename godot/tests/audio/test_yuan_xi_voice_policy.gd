extends GutTest

const Catalog := preload(
	"res://presentation/characters/character_presentation_catalog.gd")
const Policy := preload("res://presentation/characters/character_voice_policy.gd")


func _event(type: StringName, actor: int, extra: Dictionary = {}) -> BattleEvent:
	return BattleEvent.make(type, actor, null, extra)


func _policy(ids: Array = [&"yuan_xi", &"qiu_jue", &"bai_touli", &"hua_ling"]):
	var profile = null
	for candidate in Catalog.active_profiles():
		if candidate.character_id == &"yuan_xi":
			profile = candidate
			break
	assert_not_null(profile, "表现目录必须注册渊汐")
	var policy = Policy.new(profile)
	policy.bind_characters(ids)
	return policy


func test_six_offline_voice_kinds_route_without_cross_character_audio() -> void:
	var policy = _policy()
	assert_eq(policy.requests_for_event(_event(&"GAME_BEGIN", 3))[0].event_kind, &"entry")
	var ability := policy.requests_for_event(_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_koromo_passive_v1",
		"source_event": &"TILE_DRAWN",
	}))
	assert_eq(ability[0].event_kind, &"ability")
	assert_eq(ability[0].priority, 20)
	assert_eq(policy.requests_for_event(_event(&"WIN_DECLARED", 0, {
		"is_tsumo": true,
	}))[0].event_kind, &"win")
	assert_eq(policy.requests_for_event(_event(&"WIN_DECLARED", 2, {
		"is_tsumo": false,
		"discarder_seat": 0,
	}))[0].event_kind, &"hurt")
	assert_eq(policy.requests_for_scores([28000, 25000, 24000, 23000])
		[0].event_kind, &"advantage")
	assert_eq(policy.requests_for_match_result([22000, 30000, 25000, 23000])
		[0].event_kind, &"result_lose")
	assert_true(policy.requests_for_event(_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_awai_passive_v1",
	})).is_empty())
	assert_true(policy.requests_for_event(_event(&"SKILL_TRIGGERED", 1, {
		"skill_id": &"char_koromo_passive_v1",
	})).is_empty())


func test_rebind_resets_entry_and_nonzero_yuan_seat_routes_only_own_events() -> void:
	var policy = _policy([&"qiu_jue", &"yuan_xi", &"bai_touli", &"hua_ling"])
	assert_true(policy.requests_for_event(_event(&"GAME_BEGIN", 0)).is_empty())
	assert_true(policy.requests_for_event(_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_koromo_passive_v1",
	})).is_empty())
	assert_eq(policy.requests_for_event(_event(&"SKILL_TRIGGERED", 1, {
		"skill_id": &"char_koromo_passive_v1",
	})).size(), 1)
	policy.bind_characters([&"yuan_xi", &"qiu_jue", &"bai_touli", &"hua_ling"])
	assert_eq(policy.requests_for_event(_event(&"GAME_BEGIN", 2)).size(), 1,
		"新会话绑定必须重置 entry 去重状态")
