extends GutTest

const Catalog := preload(
	"res://presentation/characters/character_presentation_catalog.gd")
const Policy := preload("res://presentation/characters/character_voice_policy.gd")
const ABILITY_ID := &"char_teru_passive_v1"


func _event(type: StringName, actor: int, extra: Dictionary = {}) -> BattleEvent:
	return BattleEvent.make(type, actor, null, extra)


func _policy(ids: Array = [&"lian_yao", &"qiu_jue", &"bai_touli", &"hua_ling"]):
	var profile = null
	for candidate in Catalog.active_profiles():
		if candidate.character_id == &"lian_yao":
			profile = candidate
			break
	assert_not_null(profile)
	if profile == null:
		return null
	var policy = Policy.new(profile)
	policy.bind_characters(ids)
	return policy


func test_six_offline_events_route_without_cross_talk() -> void:
	var policy = _policy()
	if policy == null:
		return
	assert_eq(policy.requests_for_event(_event(&"GAME_BEGIN", 0))[0].event_kind, &"entry")
	var ability: Array = policy.requests_for_event(_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": ABILITY_ID,
	}))
	assert_eq(ability[0].event_kind, &"ability")
	assert_eq(ability[0].priority, 20)
	assert_eq(policy.requests_for_event(_event(&"WIN_DECLARED", 0, {
		"is_tsumo": true,
	}))[0].event_kind, &"win")
	assert_eq(policy.requests_for_event(_event(&"WIN_DECLARED", 2, {
		"is_tsumo": false, "discarder_seat": 0,
	}))[0].event_kind, &"hurt")
	assert_eq(policy.requests_for_scores([28000, 25000, 24000, 23000])[0].event_kind,
		&"advantage")
	assert_eq(policy.requests_for_match_result([22000, 30000, 25000, 23000])[0].event_kind,
		&"result_lose")
	assert_true(policy.requests_for_event(_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_kaiji_passive_v1",
	})).is_empty())
	assert_true(policy.requests_for_event(_event(&"SKILL_TRIGGERED", 1, {
		"skill_id": ABILITY_ID,
	})).is_empty())
