extends GutTest

const Catalog := preload(
	"res://presentation/characters/character_presentation_catalog.gd")
const Policy := preload("res://presentation/characters/character_voice_policy.gd")


func _event(type: StringName, actor: int, extra: Dictionary = {}) -> BattleEvent:
	return BattleEvent.make(type, actor, null, extra)


func _policy(ids: Array = [&"ying_li", &"qiu_jue", &"bai_touli", &"hua_ling"]):
	var profile = null
	for candidate in Catalog.active_profiles():
		if candidate.character_id == &"ying_li":
			profile = candidate
			break
	assert_not_null(profile)
	var policy = Policy.new(profile)
	policy.bind_characters(ids)
	return policy


func test_six_lifecycle_events_route_without_cross_character_audio() -> void:
	var policy = _policy()
	var entry: Array = policy.requests_for_event(_event(&"GAME_BEGIN", 3))
	assert_eq(entry[0].event_kind, &"entry")
	var ability: Array = policy.requests_for_event(_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_momoko_passive_v1",
	}))
	assert_eq(ability[0].event_kind, &"ability")
	assert_eq(ability[0].priority, 20)
	var win: Array = policy.requests_for_event(_event(&"WIN_DECLARED", 0, {
		"is_tsumo": true,
	}))
	assert_eq(win[0].event_kind, &"win")
	var hurt: Array = policy.requests_for_event(_event(&"WIN_DECLARED", 2, {
		"is_tsumo": false,
		"discarder_seat": 0,
	}))
	assert_eq(hurt[0].event_kind, &"hurt")
	var advantage: Array = policy.requests_for_scores([28000, 25000, 24000, 23000])
	assert_eq(advantage[0].event_kind, &"advantage")
	var lose: Array = policy.requests_for_match_result([22000, 30000, 25000, 23000])
	assert_eq(lose[0].event_kind, &"result_lose")

	assert_true(policy.requests_for_event(_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_kaiji_passive_v1",
	})).is_empty())
	assert_true(policy.requests_for_event(_event(&"SKILL_TRIGGERED", 1, {
		"skill_id": &"char_momoko_passive_v1",
	})).is_empty())
