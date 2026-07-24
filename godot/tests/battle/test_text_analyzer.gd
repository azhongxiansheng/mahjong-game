extends GutTest

# E5-02 / #250 Round-2：语言隔离、rule_version、真实模板、冲突幂等、半角日文。

const RULE_VERSION := "trash_talk_rules_v1"
const AFFINITY_KEYS := ["DOMINATION", "CALM", "CUNNING", "PASSION", "MYSTIC"]


func test_normalize_fullwidth_ascii_case_and_whitespace() -> void:
	var raw := "　　ＨＥＬＬＯ　  World\t!"
	assert_eq(TextAnalyzer.normalize(raw), "hello world")


func test_normalize_strips_basic_and_halfwidth_jp_punctuation() -> void:
	assert_eq(TextAnalyzer.normalize("必胜！"), "必胜")
	assert_eq(TextAnalyzer.normalize("must win?"), "must win")
	assert_eq(TextAnalyzer.normalize("逆転。"), "逆転")
	assert_eq(TextAnalyzer.normalize("a，b、c；d：e"), "abcde")
	# 半角日文标点 ｡､･
	assert_eq(TextAnalyzer.normalize("必勝｡逆転､燃え･ろ"), "必勝逆転燃えろ")


func test_normalize_halfwidth_katakana_dakuten_handakuten() -> void:
	assert_eq(TextAnalyzer.normalize("ｱｲｳ"), "アイウ")
	assert_eq(TextAnalyzer.normalize("ﾄﾞﾗ"), "ドラ")
	assert_eq(TextAnalyzer.normalize("ﾊﾟｰ"), "パー")
	assert_eq(TextAnalyzer.normalize("ﾋﾟﾝ"), "ピン")
	assert_eq(TextAnalyzer.normalize("ひらがな"), "ひらがな")


func test_normalize_empty_and_cjk() -> void:
	assert_eq(TextAnalyzer.normalize(""), "")
	assert_eq(TextAnalyzer.normalize("燃烧翻盘"), "燃烧翻盘")
	assert_eq(TextAnalyzer.normalize("燃！烧"), "燃烧")


func test_legacy_analyze_still_returns_float_attrs() -> void:
	var result := TextAnalyzer.analyze("必胜！绝对不会输！")
	assert_true(result[Momentum.Attribute.DOMINATION] > 0.0)
	var empty := TextAnalyzer.analyze("")
	assert_eq(empty[Momentum.Attribute.DOMINATION], 0.0)
	assert_eq(empty[Momentum.Attribute.CALM], 0.0)


func test_rule_version_required_and_must_match_catalog() -> void:
	var base := {
		"window_id": "w_rv",
		"seat": 1,
		"character_id": "qiu_jue",
		"language": "zh",
		"utterances": [{"utterance_id": "u1", "text": "燃烧", "language": "zh"}],
	}
	var missing := base.duplicate(true)
	# 无 rule_version
	assert_true(TextAnalyzer.accumulate_window(missing).is_empty(), "缺失 rule_version 必须拒绝")

	var unknown := base.duplicate(true)
	unknown["rule_version"] = "trash_talk_rules_v999"
	assert_true(TextAnalyzer.accumulate_window(unknown).is_empty(), "未知 rule_version 必须拒绝")

	var ok := base.duplicate(true)
	ok["rule_version"] = RULE_VERSION
	var out: Dictionary = TextAnalyzer.accumulate_window(ok)
	assert_false(out.is_empty())
	assert_eq(String(out.get("rule_version", "")), RULE_VERSION)
	assert_true(out["matched_rule_ids"].has("r_persona_qiu_jue_kw_zh_01"))


func test_language_isolation_an_cheng_冷静_zh_not_ja() -> void:
	# 真实 catalog：an_cheng zh/ja 均含「冷静」；必须按 language 只命中对应 rule
	var zh := _accum_lang("w_calm_zh", 0, "an_cheng", "zh", [
		{"utterance_id": "u1", "text": "保持冷静观察", "language": "zh"},
	])
	assert_true(zh["matched_rule_ids"].has("r_persona_an_cheng_kw_zh_01"))
	assert_false(zh["matched_rule_ids"].has("r_persona_an_cheng_kw_ja_01"),
		"zh 不得命中 ja persona rule: %s" % str(zh["matched_rule_ids"]))

	var ja := _accum_lang("w_calm_ja", 0, "an_cheng", "ja", [
		{"utterance_id": "u1", "text": "冷静を保て", "language": "ja"},
	])
	assert_true(ja["matched_rule_ids"].has("r_persona_an_cheng_kw_ja_01"))
	assert_false(ja["matched_rule_ids"].has("r_persona_an_cheng_kw_zh_01"),
		"ja 不得命中 zh persona rule: %s" % str(ja["matched_rule_ids"]))


func test_language_isolation_expression_and_item() -> void:
	var zh_expr := _accum_lang("w_ex_zh", 0, "lin_yeche", "zh", [
		{"utterance_id": "u1", "text": "必胜翻盘燃烧", "language": "zh"},
	])
	assert_true(zh_expr["matched_rule_ids"].has("r_expr_generic_zh_01"))
	assert_false(zh_expr["matched_rule_ids"].has("r_expr_generic_en_01"))
	assert_false(zh_expr["matched_rule_ids"].has("r_expr_generic_ja_01"))

	var en_item := _accum_lang("w_it_en", 2, "lin_yeche", "en", [
		{"utterance_id": "u1", "text": "double payout crush", "language": "en"},
	])
	assert_true(en_item["matched_rule_ids"].has("r_item_double_payout_tag_01"))
	# 中文「碾压」不应在 en 语言下匹配
	var en_zh_word := _accum_lang("w_it_en2", 2, "lin_yeche", "en", [
		{"utterance_id": "u1", "text": "用倍率券碾压全场", "language": "en"},
	])
	assert_false(en_zh_word["matched_rule_ids"].has("r_item_double_payout_tag_01"),
		"en 语言不得用 zh item patterns 命中")


func test_utterance_language_overrides_window_default() -> void:
	var out := TextAnalyzer.accumulate_window({
		"rule_version": RULE_VERSION,
		"window_id": "w_ov",
		"seat": 1,
		"character_id": "qiu_jue",
		"language": "en",
		"utterances": [
			{"utterance_id": "u1", "text": "燃烧翻盘", "language": "zh"},
		],
	})
	assert_true(out["matched_rule_ids"].has("r_persona_qiu_jue_kw_zh_01"))
	assert_false(out["matched_rule_ids"].has("r_persona_qiu_jue_kw_en_01"))


func test_missing_language_rejects() -> void:
	var out := TextAnalyzer.accumulate_window({
		"rule_version": RULE_VERSION,
		"window_id": "w_nolang",
		"seat": 1,
		"character_id": "qiu_jue",
		"utterances": [{"utterance_id": "u1", "text": "燃烧"}],
	})
	assert_true(out.is_empty(), "无 window/utterance language 必须拒绝")


func test_invalid_language_rejects() -> void:
	var out := TextAnalyzer.accumulate_window({
		"rule_version": RULE_VERSION,
		"window_id": "w_badlang",
		"seat": 1,
		"character_id": "qiu_jue",
		"language": "fr",
		"utterances": [{"utterance_id": "u1", "text": "燃烧", "language": "fr"}],
	})
	assert_true(out.is_empty())


func test_gold_zero_from_fixture() -> void:
	var fixture: Dictionary = TrashTalkGoldFixtures.gold_zero()
	assert_eq(String(fixture.get("rule_version", "")), RULE_VERSION)
	var texts: Dictionary = fixture.get("texts_by_seat", {})
	var chars: Array = fixture.get("character_ids", [])
	var lang := String(fixture.get("language", "zh"))
	var window_id := String(fixture.get("window_id", ""))
	for seat in range(4):
		var cid := String(chars[seat])
		var text := String(texts.get(str(seat), ""))
		var out := _accum_lang(window_id, seat, cid, lang, [
			{"utterance_id": "u0", "text": text, "language": lang},
		])
		_assert_schema(out, window_id, seat, cid)
		assert_eq(out["matched_rule_ids"], [])
		assert_eq(int(out["specificity"]), 0)
		assert_eq(int(out["expression_quality"]), 0)
		for k in AFFINITY_KEYS:
			assert_eq(int(out["affinity"][k]), 0)
	# #251 边界：fixture 期望含 public_context/matrix，#250 不产出
	assert_true(fixture.get("expected", {}).has("matrix_components"))
	assert_true(fixture.has("public_context_tags_active"))


func test_gold_text_from_fixture_text_subset() -> void:
	var fixture: Dictionary = TrashTalkGoldFixtures.gold_text()
	var texts: Dictionary = fixture.get("texts_by_seat", {})
	var chars: Array = fixture.get("character_ids", [])
	var lang := String(fixture.get("language", "zh"))
	var window_id := String(fixture.get("window_id", ""))
	var seat := 1
	var cid := String(chars[seat])
	var text := String(texts.get(str(seat), ""))
	assert_false(text.is_empty(), "gold_text seat1 必须有文本")

	var out := _accum_lang(window_id, seat, cid, lang, [
		{"utterance_id": "utt_1", "text": text, "language": lang},
	])
	_assert_schema(out, window_id, seat, cid)
	var ids: Array = out["matched_rule_ids"]
	# #250 文本子集：persona keyword + expression + 文本可命中的 item pattern + 真实模板
	assert_true(ids.has("r_persona_qiu_jue_kw_zh_01"), str(ids))
	assert_true(ids.has("r_expr_generic_zh_01"), str(ids))
	assert_true(ids.has("r_item_relic_comeback_crown_tag_01"), "翻盘→comeback crown 文本 pattern")
	assert_true(ids.has("r_persona_qiu_jue_tpl_zh_01"), "应命中 catalog 真实 PERSONA_TEMPLATE")
	assert_true(TrashTalkRuleCatalog.has_rule_id("r_persona_qiu_jue_tpl_zh_01"))
	# #251 才拥有：奖池 double_payout 分项与 public_context
	assert_false(ids.has("r_item_double_payout_tag_01"))
	assert_false(ids.has("r_ctx_riichi_open_01"))
	var expected_ids: Array = fixture.get("expected", {}).get("matched_rule_ids_by_seat", {}).get("1", [])
	assert_true(expected_ids.has("r_ctx_riichi_open_01"), "fixture 仍声明 #251 的 ctx 期望")
	assert_true(expected_ids.has("r_item_double_payout_tag_01"), "fixture 仍声明 #251 的奖池 item 期望")

	assert_eq(int(out["expression_quality"]), 180)
	# PASSION: keyword 220 + template 100
	assert_eq(int(out["affinity"]["PASSION"]), 320)
	assert_eq(int(out["affinity"]["DOMINATION"]), 160)
	assert_eq(int(out["specificity"]), 850)

	# 静默席
	var silent := _accum_lang(window_id, 0, String(chars[0]), lang, [
		{"utterance_id": "s0", "text": String(texts.get("0", "")), "language": lang},
	])
	assert_eq(silent["matched_rule_ids"], [])


func test_persona_bound_to_character_id() -> void:
	var fixture: Dictionary = TrashTalkGoldFixtures.gold_text()
	var text := String(fixture["texts_by_seat"]["1"])
	var out := _accum_lang("w1", 0, "lin_yeche", "zh", [
		{"utterance_id": "u1", "text": text, "language": "zh"},
	])
	assert_false(out["matched_rule_ids"].has("r_persona_qiu_jue_kw_zh_01"))
	assert_false(out["matched_rule_ids"].has("r_persona_qiu_jue_tpl_zh_01"))
	assert_true(out["matched_rule_ids"].has("r_expr_generic_zh_01"))


func test_en_and_ja_keyword_hits() -> void:
	var en := _accum_lang("w_en", 1, "qiu_jue", "en", [
		{"utterance_id": "e1", "text": "Time to BURN and comeback!", "language": "en"},
	])
	assert_true(en["matched_rule_ids"].has("r_persona_qiu_jue_kw_en_01"))
	assert_false(en["matched_rule_ids"].has("r_persona_qiu_jue_kw_zh_01"))

	var ja := _accum_lang("w_ja", 1, "qiu_jue", "ja", [
		{"utterance_id": "j1", "text": "燃えろ！逆転だ！", "language": "ja"},
	])
	assert_true(ja["matched_rule_ids"].has("r_persona_qiu_jue_kw_ja_01"))
	assert_false(ja["matched_rule_ids"].has("r_persona_qiu_jue_kw_zh_01"))


func test_expression_en_ja() -> void:
	var en := _accum_lang("w_ee", 0, "lin_yeche", "en", [
		{"utterance_id": "e1", "text": "We must win this comeback!", "language": "en"},
	])
	assert_true(en["matched_rule_ids"].has("r_expr_generic_en_01"))
	assert_eq(int(en["expression_quality"]), 180)
	var ja := _accum_lang("w_ej", 0, "lin_yeche", "ja", [
		{"utterance_id": "j1", "text": "必勝で逆転！", "language": "ja"},
	])
	assert_true(ja["matched_rule_ids"].has("r_expr_generic_ja_01"))


func test_item_tag_zh_pattern_only_under_zh() -> void:
	var out := _accum_lang("w_item", 2, "lin_yeche", "zh", [
		{"utterance_id": "i1", "text": "用倍率券碾压全场", "language": "zh"},
	])
	assert_true(out["matched_rule_ids"].has("r_item_double_payout_tag_01"))
	assert_eq(int(out["specificity"]), 750)
	assert_eq(int(out["affinity"]["DOMINATION"]), 150)


func test_public_context_never_from_text() -> void:
	var out := _accum_lang("w_ctx", 0, "qiu_jue", "zh", [
		{"utterance_id": "c1", "text": "CTX_RIICHI_OPEN 立直公开", "language": "zh"},
	])
	var ctx_hits := 0
	for rid in out["matched_rule_ids"]:
		if String(rid).begins_with("r_ctx_"):
			ctx_hits += 1
	assert_eq(ctx_hits, 0)


func test_persona_template_real_catalog_hit_and_miss() -> void:
	assert_true(TrashTalkRuleCatalog.has_rule_id("r_persona_qiu_jue_tpl_zh_01"))
	var hit := _accum_lang("w_tpl", 1, "qiu_jue", "zh", [
		{"utterance_id": "t1", "text": "越危险，我越兴奋。", "language": "zh"},
	])
	assert_true(hit["matched_rule_ids"].has("r_persona_qiu_jue_tpl_zh_01"))
	assert_eq(int(hit["affinity"]["PASSION"]), 100)

	var miss := _accum_lang("w_tpl_miss", 1, "qiu_jue", "zh", [
		{"utterance_id": "t1", "text": "越危险，越兴奋。", "language": "zh"},
	])
	assert_false(miss["matched_rule_ids"].has("r_persona_qiu_jue_tpl_zh_01"))


func test_rules_override_key_is_ignored() -> void:
	# 生产 API 不得接受任意 rules 覆盖 catalog
	var forged_id := "r_forged_not_in_catalog"
	var out := TextAnalyzer.accumulate_window({
		"rule_version": RULE_VERSION,
		"window_id": "w_forge",
		"seat": 1,
		"character_id": "qiu_jue",
		"language": "zh",
		"utterances": [{"utterance_id": "u1", "text": "越危险，我越兴奋。", "language": "zh"}],
		"rules": [{
			"rule_id": forged_id,
			"component": "persona",
			"points": 999,
			"cap": 1000,
			"once_per_window_seat": true,
			"match": {
				"kind": "PERSONA_TEMPLATE",
				"language": "zh",
				"character_id": "qiu_jue",
				"patterns": ["越危险，我越兴奋。"],
			},
		}],
	})
	assert_false(out["matched_rule_ids"].has(forged_id))
	assert_true(out["matched_rule_ids"].has("r_persona_qiu_jue_tpl_zh_01"))
	assert_true(TrashTalkRuleCatalog.has_rule_id("r_persona_qiu_jue_tpl_zh_01"))
	assert_false(TrashTalkRuleCatalog.has_rule_id(forged_id))


func test_rule_once_per_window_seat_spam_cap() -> void:
	var text := String(TrashTalkGoldFixtures.gold_text()["texts_by_seat"]["1"])
	var out := _accum_lang("w_spam", 1, "qiu_jue", "zh", [
		{"utterance_id": "a", "text": text, "language": "zh"},
		{"utterance_id": "b", "text": text, "language": "zh"},
		{"utterance_id": "c", "text": text, "language": "zh"},
	])
	var persona_count := 0
	var expr_count := 0
	var tpl_count := 0
	for rid in out["matched_rule_ids"]:
		if rid == "r_persona_qiu_jue_kw_zh_01":
			persona_count += 1
		if rid == "r_expr_generic_zh_01":
			expr_count += 1
		if rid == "r_persona_qiu_jue_tpl_zh_01":
			tpl_count += 1
	assert_eq(persona_count, 1)
	assert_eq(expr_count, 1)
	assert_eq(tpl_count, 1)
	assert_eq(int(out["affinity"]["PASSION"]), 320)
	assert_eq(int(out["expression_quality"]), 180)


func test_duplicate_utterance_same_payload_idempotent_order_independent() -> void:
	var text := String(TrashTalkGoldFixtures.gold_text()["texts_by_seat"]["1"])
	var a := TextAnalyzer.accumulate_window({
		"rule_version": RULE_VERSION,
		"window_id": "w_idemp",
		"seat": 1,
		"character_id": "qiu_jue",
		"language": "zh",
		"utterances": [
			{"utterance_id": "same", "text": text, "language": "zh"},
			{"utterance_id": "same", "text": text, "language": "zh"},
		],
	})
	var b := TextAnalyzer.accumulate_window({
		"rule_version": RULE_VERSION,
		"window_id": "w_idemp",
		"seat": 1,
		"character_id": "qiu_jue",
		"language": "zh",
		"utterances": [
			{"utterance_id": "same", "text": text, "language": "zh"},
			{"utterance_id": "same", "text": text, "language": "zh"},
		],
	})
	assert_eq(TrashTalkGoldFixtures.stable_stringify(a), TrashTalkGoldFixtures.stable_stringify(b))
	assert_eq(int(a["affinity"]["PASSION"]), 320)


func test_duplicate_utterance_conflicting_text_rejects_order_independent() -> void:
	var text_a := "燃烧翻盘"
	var text_b := "绝崖"
	var forward := TextAnalyzer.accumulate_window({
		"rule_version": RULE_VERSION,
		"window_id": "w_conf",
		"seat": 1,
		"character_id": "qiu_jue",
		"language": "zh",
		"utterances": [
			{"utterance_id": "same", "text": text_a, "language": "zh"},
			{"utterance_id": "same", "text": text_b, "language": "zh"},
		],
	})
	var reverse := TextAnalyzer.accumulate_window({
		"rule_version": RULE_VERSION,
		"window_id": "w_conf",
		"seat": 1,
		"character_id": "qiu_jue",
		"language": "zh",
		"utterances": [
			{"utterance_id": "same", "text": text_b, "language": "zh"},
			{"utterance_id": "same", "text": text_a, "language": "zh"},
		],
	})
	assert_true(forward.is_empty(), "同 ID 冲突文本必须稳定拒绝")
	assert_true(reverse.is_empty(), "反序同样拒绝")
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(forward),
		TrashTalkGoldFixtures.stable_stringify(reverse)
	)


func test_duplicate_utterance_conflicting_language_rejects() -> void:
	var out := TextAnalyzer.accumulate_window({
		"rule_version": RULE_VERSION,
		"window_id": "w_conflang",
		"seat": 1,
		"character_id": "qiu_jue",
		"language": "zh",
		"utterances": [
			{"utterance_id": "same", "text": "燃烧", "language": "zh"},
			{"utterance_id": "same", "text": "燃烧", "language": "ja"},
		],
	})
	assert_true(out.is_empty())


func test_utterance_order_stable_by_utterance_id() -> void:
	var a := _accum_lang("w_ord", 1, "qiu_jue", "zh", [
		{"utterance_id": "u2", "text": "绝崖", "language": "zh"},
		{"utterance_id": "u1", "text": "必胜翻盘燃烧", "language": "zh"},
	])
	var b := _accum_lang("w_ord", 1, "qiu_jue", "zh", [
		{"utterance_id": "u1", "text": "必胜翻盘燃烧", "language": "zh"},
		{"utterance_id": "u2", "text": "绝崖", "language": "zh"},
	])
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(a),
		TrashTalkGoldFixtures.stable_stringify(b)
	)


func test_multi_utterance_accumulates_distinct_rules() -> void:
	var out := _accum_lang("w_multi", 1, "qiu_jue", "zh", [
		{"utterance_id": "u1", "text": "绝崖", "language": "zh"},
		{"utterance_id": "u2", "text": "倍率券防御碾压", "language": "zh"},
	])
	assert_true(out["matched_rule_ids"].has("r_persona_qiu_jue_kw_zh_01"))
	assert_true(out["matched_rule_ids"].has("r_item_double_payout_tag_01"))


func test_byte_identical_on_repeat_runs() -> void:
	var input := {
		"rule_version": RULE_VERSION,
		"window_id": "w_byte",
		"seat": 1,
		"character_id": "qiu_jue",
		"language": "zh",
		"utterances": [
			{"utterance_id": "u2", "text": "燃烧翻盘", "language": "zh"},
			{"utterance_id": "u1", "text": "绝崖", "language": "zh"},
		],
	}
	var a := TextAnalyzer.accumulate_window(input)
	var b := TextAnalyzer.accumulate_window(input)
	assert_eq(
		TrashTalkGoldFixtures.stable_stringify(a),
		TrashTalkGoldFixtures.stable_stringify(b)
	)


func test_all_feature_values_are_int_0_to_1000() -> void:
	var text := String(TrashTalkGoldFixtures.gold_text()["texts_by_seat"]["1"])
	var out := _accum_lang("w_int", 1, "qiu_jue", "zh", [
		{"utterance_id": "u1", "text": text + " 倍率券碾压", "language": "zh"},
	])
	for k in AFFINITY_KEYS:
		var v: Variant = out["affinity"][k]
		assert_eq(typeof(v), TYPE_INT, "affinity.%s 必须 int" % k)
		assert_true(int(v) >= 0 and int(v) <= 1000)
	assert_eq(typeof(out["specificity"]), TYPE_INT)
	assert_eq(typeof(out["expression_quality"]), TYPE_INT)


func test_output_has_no_grant_or_matrix_payload() -> void:
	var text := String(TrashTalkGoldFixtures.gold_text()["texts_by_seat"]["1"])
	var out := _accum_lang("w_no", 1, "qiu_jue", "zh", [
		{"utterance_id": "u1", "text": text, "language": "zh"},
	])
	assert_false(out.has("item_id"))
	assert_false(out.has("ITEM_GRANTED"))
	assert_false(out.has("matrix_components"))
	assert_false(out.has("skill_effect_multiplier"))


func test_analyzer_source_does_not_call_skill_effect_multiplier() -> void:
	var src := FileAccess.get_file_as_string("res://battle/text_analyzer.gd")
	assert_false(src.contains("skill_effect_multiplier"))


func test_matched_rule_ids_are_sorted() -> void:
	var text := String(TrashTalkGoldFixtures.gold_text()["texts_by_seat"]["1"])
	var out := _accum_lang("w_sort", 1, "qiu_jue", "zh", [
		{"utterance_id": "u1", "text": text + " 倍率券", "language": "zh"},
	])
	var ids: Array = out["matched_rule_ids"].duplicate()
	var sorted_ids: Array = ids.duplicate()
	sorted_ids.sort()
	assert_eq(ids, sorted_ids)


func test_punctuation_does_not_block_keyword_match() -> void:
	assert_eq(TextAnalyzer.normalize("燃！烧"), "燃烧")
	var out := _accum_lang("w_punc", 1, "qiu_jue", "zh", [
		{"utterance_id": "u1", "text": "燃！烧！起！来！翻、盘！", "language": "zh"},
	])
	assert_true(out["matched_rule_ids"].has("r_persona_qiu_jue_kw_zh_01"))


func test_empty_window_id_rejects() -> void:
	var out: Dictionary = TextAnalyzer.accumulate_window({
		"rule_version": RULE_VERSION,
		"window_id": "",
		"seat": 1,
		"character_id": "qiu_jue",
		"language": "zh",
		"utterances": [{"utterance_id": "u1", "text": "燃烧", "language": "zh"}],
	})
	assert_true(out.is_empty())


# --- helpers ---

func _accum_lang(
	window_id: String,
	seat: int,
	character_id: String,
	language: String,
	utterances: Array
) -> Dictionary:
	return TextAnalyzer.accumulate_window({
		"rule_version": RULE_VERSION,
		"window_id": window_id,
		"seat": seat,
		"character_id": character_id,
		"language": language,
		"utterances": utterances,
	})


func _assert_schema(out: Dictionary, window_id: String, seat: int, character_id: String) -> void:
	assert_false(out.is_empty(), "accumulate_window 不得返回空")
	assert_eq(String(out.get("rule_version", "")), RULE_VERSION)
	assert_eq(String(out.get("window_id", "")), window_id)
	assert_eq(int(out.get("seat", -1)), seat)
	assert_eq(String(out.get("character_id", "")), character_id)
	assert_true(out.get("matched_rule_ids") is Array)
	assert_true(out.get("affinity") is Dictionary)
	for k in AFFINITY_KEYS:
		assert_true(out["affinity"].has(k), "缺少 affinity.%s" % k)
	assert_true(out.has("specificity"))
	assert_true(out.has("expression_quality"))
