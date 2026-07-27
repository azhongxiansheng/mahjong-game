extends GutTest

const Catalog := preload(
	"res://presentation/characters/character_presentation_catalog.gd")
const Policy := preload("res://presentation/characters/character_voice_policy.gd")
const ABILITY_ID := &"char_tetsuya_passive_v1"


func _event(type: StringName, actor: int, extra: Dictionary = {}) -> BattleEvent:
	return BattleEvent.make(type, actor, null, extra)


func _policy(ids: Array = [&"qiu_jue", &"lian_yao", &"ju_jin", &"hua_ling"]):
	var profile = null
	for candidate in Catalog.active_profiles():
		if candidate.character_id == &"ju_jin":
			profile = candidate
			break
	assert_not_null(profile)
	if profile == null:
		return null
	var policy = Policy.new(profile)
	policy.bind_characters(ids, 2)
	return policy


func test_six_offline_events_route_for_nonzero_local_seat_without_cross_talk() -> void:
	var policy = _policy()
	if policy == null:
		return
	assert_eq(policy.requests_for_event(_event(&"GAME_BEGIN", 0))[0].event_kind, &"entry")
	var ability: Array = policy.requests_for_event(_event(&"SKILL_TRIGGERED", 2, {
		"skill_id": ABILITY_ID,
		"han_delta": 3,
	}))
	assert_eq(ability.size(), 1)
	assert_eq(ability[0].event_kind, &"ability")
	assert_eq(ability[0].priority, 20)
	assert_eq(policy.requests_for_event(_event(&"WIN_DECLARED", 2, {
		"is_tsumo": true,
	}))[0].event_kind, &"win")
	assert_eq(policy.requests_for_event(_event(&"WIN_DECLARED", 1, {
		"is_tsumo": false, "discarder_seat": 2,
	}))[0].event_kind, &"hurt")
	assert_eq(policy.requests_for_scores([23000, 24000, 30000, 23000])[0].event_kind,
		&"advantage")
	assert_eq(policy.requests_for_match_result([24000, 26000, 22000, 28000])[0].event_kind,
		&"result_lose")
	assert_true(policy.requests_for_event(_event(&"SKILL_TRIGGERED", 1, {
		"skill_id": ABILITY_ID,
	})).is_empty())
	assert_true(policy.requests_for_event(_event(&"SKILL_TRIGGERED", 2, {
		"skill_id": &"char_teru_passive_v1",
	})).is_empty())


func test_manifest_exposes_exactly_two_variants_for_all_six_existing_events() -> void:
	var catalog := CharacterVoiceCatalog.new()
	for event_kind in [&"entry", &"ability", &"advantage", &"hurt", &"win", &"result_lose"]:
		var paths := catalog.clip_paths(&"ju_jin", event_kind)
		assert_eq(paths.size(), 2)
		for path in paths:
			assert_true(String(path).begins_with(
				"res://assets/voice/characters/ju_jin/ja/"))
			assert_true(ResourceLoader.exists(String(path)))


func test_lian_yao_and_ju_jin_profiles_emit_only_the_matching_ability_voice() -> void:
	var router := CharacterPresentationRouter.new(Catalog.active_profiles())
	router.bind_characters([&"qiu_jue", &"lian_yao", &"ju_jin", &"hua_ling"], 2)
	var ju_requests := router.voice_requests_for_event(_event(&"SKILL_TRIGGERED", 2, {
		"skill_id": ABILITY_ID,
		"han_delta": 3,
	}))
	assert_eq(ju_requests.size(), 1)
	assert_eq(ju_requests[0].character_id, &"ju_jin")
	var lian_requests := router.voice_requests_for_event(_event(&"SKILL_TRIGGERED", 1, {
		"skill_id": &"char_teru_passive_v1",
		"han_delta": 2,
	}))
	assert_eq(lian_requests.size(), 1)
	assert_eq(lian_requests[0].character_id, &"lian_yao")
