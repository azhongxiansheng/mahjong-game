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


func test_catalog_activates_yuan_xi_distinct_wall_and_last_tile_feedback() -> void:
	var router = Router.new(Catalog.active_profiles())
	router.bind_characters([&"yuan_xi", &"qiu_jue", &"lin_yeche", &"hua_ling"])
	assert_eq(router.next_draw_label_for_local_character(), "潮见")
	var wall_event := _event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_koromo_passive_v1",
		"skill_name": "渊汐·底牌潮掌",
		"source_event": &"TILE_DRAWN",
	})
	var wall_feedback: Dictionary = router.feedback_for_event(wall_event)
	assert_true(bool(wall_feedback.get("suppress_toast", false)),
		"潮见三牌已是信息反馈，不得再用 toast 遮挡对家手牌")
	assert_eq(String(wall_feedback.get("text", "")), "")
	var settle_event := _event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_koromo_passive_v1",
		"skill_name": "渊汐·底牌潮掌",
		"source_event": &"HAITEI",
	})
	var settle_feedback: Dictionary = router.feedback_for_event(settle_event)
	assert_eq(settle_feedback.text, "🌊 渊汐 · 底牌潮掌　末巡和牌 +3 番")
	assert_eq(settle_feedback.position, Vector2(420, 84),
		"末巡结算 toast 必须落在顶部安全空档")
	assert_eq(router.voice_requests_for_event(wall_event).size(), 1)
	router.bind_characters([&"qiu_jue", &"yuan_xi", &"lin_yeche", &"hua_ling"])
	assert_eq(router.next_draw_label_for_local_character(), "")
	assert_true(router.feedback_for_event(wall_event).is_empty(),
		"非渊汐席位不得冒用反馈或能力语音")


func test_catalog_activates_hua_ling_feedback_and_six_voice_kinds_without_crossing() -> void:
	var router = Router.new(Catalog.active_profiles())
	router.bind_characters([&"hua_ling", &"qiu_jue", &"bai_touli", &"lin_yeche"])
	var entry: Array = router.voice_requests_for_event(_event(&"GAME_BEGIN", 0))
	assert_eq(entry.size(), 1)
	if entry.is_empty():
		return
	assert_eq(entry[0].character_id, &"hua_ling")
	assert_eq(entry[0].event_kind, &"entry")
	var ability_event := _event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_saki_passive_v1",
		"skill_name": "华岭澄·宝华绽放",
	})
	var ability: Array = router.voice_requests_for_event(ability_event)
	assert_eq(ability.size(), 1)
	if ability.is_empty():
		return
	assert_eq(ability[0].event_kind, &"ability")
	assert_eq(ability[0].priority, 20)
	var feedback: Dictionary = router.feedback_for_event(ability_event)
	assert_eq(feedback.text, "✦ 华岭澄 · 宝华绽放　+2 Dora")
	assert_eq(feedback.color, Color("7fe0c3"))
	assert_true(feedback.pulse)
	var win: Array = router.voice_requests_for_event(_event(&"WIN_DECLARED", 0, {
		"is_tsumo": true,
	}))
	assert_eq(win.size(), 1)
	assert_eq(win[0].event_kind, &"win")
	var hurt: Array = router.voice_requests_for_event(_event(&"WIN_DECLARED", 2, {
		"discarder_seat": 0,
		"is_tsumo": false,
	}))
	assert_eq(hurt.size(), 2, "白透璃和牌与华岭澄受创均应各自产生合法请求")
	var hua_hurt := hurt.filter(func(request):
		return request.character_id == &"hua_ling")
	assert_eq(hua_hurt.size(), 1)
	if not hua_hurt.is_empty():
		assert_eq(hua_hurt[0].event_kind, &"hurt")
	var advantage: Array = router.voice_requests_for_scores([28000, 24000, 24000, 24000])
	assert_eq(advantage.size(), 1)
	assert_eq(advantage[0].event_kind, &"advantage")
	var lose: Array = router.voice_requests_for_match_result([24000, 28000, 24000, 24000])
	assert_eq(lose.size(), 1)
	assert_eq(lose[0].event_kind, &"result_lose")
	assert_true(router.voice_requests_for_event(_event(&"SKILL_TRIGGERED", 1, {
		"skill_id": &"char_saki_passive_v1",
	})).is_empty(), "同能力 ID 也必须匹配华岭澄所在座位，防止跨角色串音")


func test_catalog_activates_ying_li_consumption_feedback_and_voice() -> void:
	var router = Router.new(Catalog.active_profiles())
	router.bind_characters([&"ying_li", &"qiu_jue", &"bai_touli", &"hua_ling"])
	var ability_event := _event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_momoko_passive_v1",
		"skill_name": "影立静·消影一发",
		"source_event": &"WIN_DECLARED_PRE",
	})
	var requests: Array = router.voice_requests_for_event(ability_event)
	assert_eq(requests.size(), 1)
	assert_eq(requests[0].character_id, &"ying_li")
	assert_eq(requests[0].event_kind, &"ability")
	assert_eq(requests[0].priority, 20)
	var feedback: Dictionary = router.feedback_for_event(ability_event)
	assert_eq(feedback.text, "🌑 影立静 · 消影一发　潜伏解除 · +1 番")


func test_ying_li_status_reads_authoritative_registered_skill_only_for_owner() -> void:
	var bc := BattleController.new(343)
	assert_true(BossAbilityFactory.inject(
		bc.registry, &"char_momoko_passive_v1", 0))
	bc.call("_emit", &"RIICHI_DECLARED", 0, null, {})
	var router = Router.new(Catalog.active_profiles())
	router.bind_characters([&"ying_li", &"qiu_jue", &"bai_touli", &"hua_ling"])
	var status: Dictionary = router.status_for_registry(bc.registry, 0)
	assert_eq(status.text, "消影一发 · 潜伏中")
	assert_eq(status.character_id, &"ying_li")
	assert_true(router.status_for_registry(bc.registry, 1).is_empty(),
		"非 owner viewer 不得继承本席状态")

	bc.call("_emit", &"WIN_DECLARED_PRE", 0, null, {})
	assert_true(router.status_for_registry(bc.registry, 0).is_empty(),
		"真实消费后状态视图必须立即清除")


func test_lian_yao_profile_formats_authoritative_layer_and_actual_bonus() -> void:
	var bc := BattleController.new(349)
	assert_true(BossAbilityFactory.inject(
		bc.registry, &"char_teru_passive_v1", 2))
	bc.call("_emit", &"WIN_DECLARED_PRE", 2, null, {})
	bc.call("_emit", &"WIN_DECLARED_PRE", 2, null, {})
	var router = Router.new(Catalog.active_profiles())
	router.bind_characters([&"qiu_jue", &"bai_touli", &"lian_yao", &"hua_ling"])
	var status: Dictionary = router.status_for_registry(bc.registry, 2)
	assert_eq(status.get("character_id", &""), &"lian_yao")
	assert_eq(status.get("text", ""), "叠曜 2 层 · 本次 +2 番")
	assert_true(router.status_for_registry(bc.registry, 0).is_empty())

	var ability_event := _event(&"SKILL_TRIGGERED", 2, {
		"skill_id": &"char_teru_passive_v1",
		"skill_name": "连曜真·叠曜连斩",
	})
	assert_eq(router.feedback_for_event(ability_event).text,
		"☀ 连曜真 · 叠曜连斩　连斩加深")
	var requests: Array = router.voice_requests_for_event(ability_event)
	assert_eq(requests.size(), 1)
	assert_eq(requests[0].character_id, &"lian_yao")
	assert_eq(requests[0].event_kind, &"ability")


func test_catalog_activates_bao_luo_red_feedback_and_six_voice_kinds_without_crossing() -> void:
	var router = Router.new(Catalog.active_profiles())
	router.bind_characters([&"bao_luo", &"qiu_jue", &"bai_touli", &"hua_ling"])
	var entry: Array = router.voice_requests_for_event(_event(&"GAME_BEGIN", 0))
	assert_eq(entry.size(), 1)
	if entry.is_empty():
		return
	assert_eq(entry[0].event_kind, &"entry")
	var ability_event := _event(&"SKILL_TRIGGERED", 0, {
		"skill_id": &"char_kuro_passive_v1",
		"skill_name": "宝络绯·赤线缠宝",
		"extra_red_dora_delta": 2,
	})
	var ability: Array = router.voice_requests_for_event(ability_event)
	assert_eq(ability.size(), 1)
	assert_eq(ability[0].event_kind, &"ability")
	assert_eq(ability[0].priority, 20)
	var feedback: Dictionary = router.feedback_for_event(ability_event)
	assert_eq(feedback.text, "♦ 宝络绯 · 赤线缠宝　+2 赤 Dora")
	assert_eq(feedback.color, Color("ff5b6e"))
	assert_true(feedback.pulse)
	var win: Array = router.voice_requests_for_event(_event(&"WIN_DECLARED", 0, {
		"is_tsumo": true,
	}))
	assert_eq(win.size(), 1)
	if not win.is_empty():
		assert_eq(win[0].event_kind, &"win")
	var hurt: Array = router.voice_requests_for_event(_event(&"WIN_DECLARED", 2, {
		"discarder_seat": 0, "is_tsumo": false,
	})).filter(func(request): return request.character_id == &"bao_luo")
	assert_eq(hurt.size(), 1)
	if not hurt.is_empty():
		assert_eq(hurt[0].event_kind, &"hurt")
	var advantage: Array = router.voice_requests_for_scores([28000, 24000, 24000, 24000])
	assert_eq(advantage.size(), 1)
	if not advantage.is_empty():
		assert_eq(advantage[0].event_kind, &"advantage")
	var lose: Array = router.voice_requests_for_match_result([24000, 28000, 25000, 23000])
	assert_eq(lose.size(), 1)
	if not lose.is_empty():
		assert_eq(lose[0].event_kind, &"result_lose")
	assert_true(router.voice_requests_for_event(_event(&"SKILL_TRIGGERED", 1, {
		"skill_id": &"char_kuro_passive_v1",
	})).is_empty(), "宝络绯能力与座位角色不匹配时不得串音")
