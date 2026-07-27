extends GutTest

const Profile := preload(
	"res://presentation/characters/character_presentation_profile.gd")
const Router := preload(
	"res://presentation/characters/character_presentation_router.gd")
const Catalog := preload(
	"res://presentation/characters/character_presentation_catalog.gd")


func _profile(
	character_id: StringName,
	ability_id: StringName,
	feedback_template: String
):
	return Profile.new(character_id, ability_id, feedback_template, Color("ffb347"), true)


func _event(type: StringName, actor: int, extra: Dictionary = {}) -> BattleEvent:
	return BattleEvent.make(type, actor, null, extra)


func test_profile_requires_stable_character_ability_and_feedback() -> void:
	assert_true(_profile(&"qiu_jue", &"char_kaiji_passive_v1", "🔥 {skill_name}").is_valid())
	assert_false(_profile(&"", &"char_kaiji_passive_v1", "🔥 {skill_name}").is_valid())
	assert_false(_profile(&"qiu_jue", &"", "🔥 {skill_name}").is_valid())
	assert_false(_profile(&"qiu_jue", &"char_kaiji_passive_v1", "").is_valid())


func test_two_profiles_route_ability_without_crossing_characters() -> void:
	var router = Router.new([
		_profile(&"qiu_jue", &"char_kaiji_passive_v1", "🔥 {skill_name}　+2 番"),
		_profile(&"lin_yeche", &"char_akagi_passive_v1", "👁 {skill_name}　透视 1 张"),
	])
	router.bind_characters([&"qiu_jue", &"lin_yeche", &"bai_touli", &"hua_ling"])
	var qiu_requests: Array = router.voice_requests_for_event(_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_kaiji_passive_v1",
	}))
	assert_eq(qiu_requests.size(), 1)
	assert_eq(qiu_requests[0].character_id, &"qiu_jue")
	var lin_requests: Array = router.voice_requests_for_event(_event(&"SKILL_TRIGGERED", 1, {
		"skill_id": &"char_akagi_passive_v1",
	}))
	assert_eq(lin_requests.size(), 1)
	assert_eq(lin_requests[0].character_id, &"lin_yeche")
	assert_true(router.voice_requests_for_event(_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_akagi_passive_v1",
	})).is_empty(), "能力与座位角色不匹配时不得串音")


func test_router_returns_profile_feedback_without_table_character_branch() -> void:
	var router = Router.new([
		_profile(&"qiu_jue", &"char_kaiji_passive_v1", "🔥 {skill_name}　+2 番"),
	])
	router.bind_characters([&"qiu_jue", &"lin_yeche", &"bai_touli", &"hua_ling"])
	var feedback: Dictionary = router.feedback_for_event(_event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_kaiji_passive_v1",
		"skill_name": "裘绝·绝崖翻盘",
	}))
	assert_eq(feedback.text, "🔥 裘绝 · 绝崖翻盘　+2 番")
	assert_eq(feedback.color, Color("ffb347"))
	assert_true(feedback.pulse)


func test_common_lifecycle_is_aggregated_for_each_profile() -> void:
	var router = Router.new([
		_profile(&"qiu_jue", &"char_kaiji_passive_v1", "🔥 {skill_name}"),
		_profile(&"lin_yeche", &"char_akagi_passive_v1", "👁 {skill_name}"),
	])
	router.bind_characters([&"qiu_jue", &"lin_yeche", &"bai_touli", &"hua_ling"])
	var entry: Array = router.voice_requests_for_event(_event(&"GAME_BEGIN", 2))
	assert_eq(entry.size(), 1)
	assert_eq(entry[0].character_id, &"qiu_jue")
	var advantage: Array = router.voice_requests_for_scores([24000, 27000, 25000, 24000])
	assert_eq(advantage.size(), 1)
	assert_eq(advantage[0].character_id, &"lin_yeche")
	assert_eq(advantage[0].event_kind, &"advantage")
	var lose: Array = router.voice_requests_for_match_result([24000, 27000, 25000, 24000])
	assert_eq(lose.size(), 1)
	assert_eq(lose[0].character_id, &"qiu_jue")
	assert_eq(lose[0].event_kind, &"result_lose")


func test_duplicate_character_profile_is_ignored_to_prevent_double_voice() -> void:
	var router = Router.new([
		_profile(&"qiu_jue", &"char_kaiji_passive_v1", "🔥 {skill_name}"),
		_profile(&"qiu_jue", &"duplicate_ability_v1", "重复 {skill_name}"),
	])
	router.bind_characters([&"qiu_jue", &"lin_yeche", &"bai_touli", &"hua_ling"])
	var entry: Array = router.voice_requests_for_event(_event(&"GAME_BEGIN", 0))
	assert_eq(entry.size(), 1, "同一 character_id 只能注册一个表现 profile")


func test_catalog_activates_lin_yeche_without_table_character_branch() -> void:
	var router = Router.new(Catalog.active_profiles())
	router.bind_characters([&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"])
	var entry: Array = router.voice_requests_for_event(_event(&"GAME_BEGIN", 0))
	assert_eq(entry.size(), 1)
	assert_eq(entry[0].character_id, &"lin_yeche")
	var ability_event := _event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_akagi_passive_v1",
		"skill_name": "林夜彻·脊读鬼神",
	})
	var ability: Array = router.voice_requests_for_event(ability_event)
	assert_eq(ability.size(), 1)
	assert_eq(ability[0].character_id, &"lin_yeche")
	var feedback: Dictionary = router.feedback_for_event(ability_event)
	assert_eq(feedback.text, "👁 林夜彻 · 脊读鬼神　透视下家手牌")


func test_catalog_activates_bai_touli_feedback_voice_and_reveal_label() -> void:
	var router = Router.new(Catalog.active_profiles())
	router.bind_characters([&"bai_touli", &"qiu_jue", &"lin_yeche", &"hua_ling"])
	assert_eq(router.reveal_label_for_local_character(), "镜华")
	var ability_event := _event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_washizu_passive_v1",
		"skill_name": "白透璃·万透镜华",
	})
	var voice: Array = router.voice_requests_for_event(ability_event)
	assert_eq(voice.size(), 1)
	assert_eq(voice[0].character_id, &"bai_touli")
	assert_eq(voice[0].event_kind, &"ability")
	var feedback: Dictionary = router.feedback_for_event(ability_event)
	assert_eq(feedback.text, "🔮 白透璃 · 万透镜华　看破三家各两张手牌")
	router.bind_characters([&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"])
	assert_eq(router.reveal_label_for_local_character(), "读脊")


func test_catalog_activates_an_cheng_feedback_voice_and_next_draw_label() -> void:
	var router = Router.new(Catalog.active_profiles())
	router.bind_characters([&"an_cheng", &"qiu_jue", &"lin_yeche", &"hua_ling"])
	assert_eq(router.next_draw_label_for_local_character(), "预知")
	var ability_event := _event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_awai_passive_v1",
		"skill_name": "安澄青·无风净界",
	})
	var voice: Array = router.voice_requests_for_event(ability_event)
	assert_eq(voice.size(), 1)
	assert_eq(voice[0].character_id, &"an_cheng")
	assert_eq(voice[0].event_kind, &"ability")
	var feedback: Dictionary = router.feedback_for_event(ability_event)
	assert_eq(feedback.text, "🫧 安澄青 · 无风净界　净化振听并预知下一摸")
	router.bind_characters([&"qiu_jue", &"an_cheng", &"lin_yeche", &"hua_ling"])
	assert_eq(router.next_draw_label_for_local_character(), "")
