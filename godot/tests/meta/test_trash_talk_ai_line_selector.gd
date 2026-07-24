extends GutTest

# E5-01 / #249：严格输入、上下文候选、硬编码黄金向量、utterance 幂等。

const RV := "trash_talk_rules_v1"


func test_fixed_seed_gold_vectors_pin_line_id() -> void:
	var cases: Array = [
		{
			"case_id": "generic_zh_lin",
			"input": _base_input({
				"seed": 42, "hand_seq": 1, "window_id": "hand_1_window_0",
				"seat": 2, "discard_server_seq": 17,
				"character_id": "lin_yeche", "language": "zh",
				"public_context_tags": [],
			}),
			"line_id": "ai_lin_yeche_zh_02",
			"utterance_id": "ai|trash_talk_rules_v1|hand_1_window_0|2",
		},
		{
			"case_id": "ctx_riichi_zh_ying",
			"input": _base_input({
				"seed": 7, "hand_seq": 2, "window_id": "hand_2_window_1",
				"seat": 1, "discard_server_seq": 9,
				"character_id": "ying_li", "language": "zh",
				"public_context_tags": ["CTX_RIICHI_OPEN"],
			}),
			"line_id": "ai_ying_li_zh_01",
			"utterance_id": "ai|trash_talk_rules_v1|hand_2_window_1|1",
		},
		{
			"case_id": "en_qiu_no_ctx",
			"input": _base_input({
				"seed": 12345, "hand_seq": 0, "window_id": "w_en",
				"seat": 3, "discard_server_seq": 3,
				"character_id": "qiu_jue", "language": "en",
			}),
			"line_id": "ai_qiu_jue_en_02",
			"utterance_id": "ai|trash_talk_rules_v1|w_en|3",
		},
		{
			"case_id": "ja_hua_dora",
			"input": _base_input({
				"seed": 99, "hand_seq": 4, "window_id": "hand_4_window_0",
				"seat": 0, "discard_server_seq": 12,
				"character_id": "hua_ling", "language": "ja",
				"public_context_tags": ["CTX_DORA_REVEALED"],
			}),
			"line_id": "ai_hua_ling_ja_02",
			"utterance_id": "ai|trash_talk_rules_v1|hand_4_window_0|0",
		},
	]
	for row in cases:
		var case_id: String = String(row.case_id)
		var r: Variant = TrashTalkAiLineSelector.select_ai_line(row.input)
		assert_not_null(r, "case %s 不得 null" % case_id)
		if r == null:
			continue
		assert_eq(String(r.get("line_id", "")), row.line_id, case_id)
		assert_eq(String(r.get("utterance_id", "")), row.utterance_id, case_id)
		assert_eq(String(r.get("rule_version", "")), RV, case_id)
		assert_eq(int(r.get("seat", -1)), int(row.input.seat))
		assert_eq(String(r.get("window_id", "")), String(row.input.window_id))
		assert_eq(int(r.get("discard_server_seq", -1)), int(row.input.discard_server_seq))
		var r2: Variant = TrashTalkAiLineSelector.select_ai_line(row.input)
		assert_eq(String(r.get("utterance_id", "")), String(r2.get("utterance_id", "")))
		assert_eq(String(r.get("line_id", "")), String(r2.get("line_id", "")))


func test_utterance_id_ignores_discard_server_seq_and_line() -> void:
	# 同窗同席：不同 discard_server_seq 可能选出不同 line，但 utterance_id 必须相同
	var base := _base_input({
		"seed": 42, "hand_seq": 1, "window_id": "hand_1_window_0",
		"seat": 2, "discard_server_seq": 17,
		"character_id": "lin_yeche", "language": "zh",
		"public_context_tags": [],
	})
	var a: Variant = TrashTalkAiLineSelector.select_ai_line(base)
	var other: Dictionary = base.duplicate(true)
	other["discard_server_seq"] = 99
	var b: Variant = TrashTalkAiLineSelector.select_ai_line(other)
	assert_not_null(a)
	assert_not_null(b)
	assert_eq(String(a.get("utterance_id", "")), String(b.get("utterance_id", "")),
		"utterance_id 不得依赖 discard_server_seq 或 line_id")
	assert_eq(String(a.get("utterance_id", "")), "ai|trash_talk_rules_v1|hand_1_window_0|2")
	assert_false(String(a.get("utterance_id", "")).contains(String(a.get("line_id", ""))))
	# 选线仍可随 discard_server_seq 变化（确定性，但不要求一定不同）
	assert_true(a.has("rule_version"))
	assert_eq(String(a.get("rule_version", "")), RV)


func test_no_discard_is_silent() -> void:
	var r: Variant = TrashTalkAiLineSelector.select_ai_line(_base_input({
		"seed": 1, "hand_seq": 0, "window_id": "w0", "seat": 1,
		"discard_server_seq": 5, "character_id": "qiu_jue", "language": "en",
		"has_first_discard": false,
	}))
	assert_null(r, "未弃牌必须静默")


func test_illegal_inputs_return_null() -> void:
	var good: Dictionary = _base_input({
		"seed": 1, "hand_seq": 0, "window_id": "w", "seat": 0,
		"discard_server_seq": 1, "character_id": "lin_yeche", "language": "zh",
		"public_context_tags": [],
	})
	var cases: Array = []
	var bad_seed: Dictionary = good.duplicate(true)
	bad_seed["seed"] = "1"
	cases.append(bad_seed)
	var bad_hand: Dictionary = good.duplicate(true)
	bad_hand["hand_seq"] = 1.5
	cases.append(bad_hand)
	var bad_window: Dictionary = good.duplicate(true)
	bad_window["window_id"] = ""
	cases.append(bad_window)
	var bad_seat: Dictionary = good.duplicate(true)
	bad_seat["seat"] = 4
	cases.append(bad_seat)
	var bad_seq: Dictionary = good.duplicate(true)
	bad_seq["discard_server_seq"] = 0
	cases.append(bad_seq)
	var bad_char: Dictionary = good.duplicate(true)
	bad_char["character_id"] = "not_a_char"
	cases.append(bad_char)
	var bad_lang: Dictionary = good.duplicate(true)
	bad_lang["language"] = "fr"
	cases.append(bad_lang)
	var bad_tag: Dictionary = good.duplicate(true)
	bad_tag["public_context_tags"] = ["CTX_HIDDEN_HAND"]
	cases.append(bad_tag)
	var bad_tag_type: Dictionary = good.duplicate(true)
	bad_tag_type["public_context_tags"] = [1]
	cases.append(bad_tag_type)
	var bad_rv: Dictionary = good.duplicate(true)
	bad_rv["rule_version"] = "nope"
	cases.append(bad_rv)
	var bad_hfd: Dictionary = good.duplicate(true)
	bad_hfd["has_first_discard"] = 1
	cases.append(bad_hfd)
	for c in cases:
		assert_null(TrashTalkAiLineSelector.select_ai_line(c), "非法输入须 null: %s" % str(c))


func test_context_filter_excludes_unmet_situational_lines() -> void:
	var no_ctx: Array = TrashTalkRuleCatalog.ai_lines_for_public_context(
		&"ying_li", "zh", []
	)
	for line in no_ctx:
		var tags: Array = line.get("context_tags", [])
		assert_true(tags.is_empty(), "无上下文不得纳入情境线 %s" % line.get("line_id"))
	var with_ctx: Array = TrashTalkRuleCatalog.ai_lines_for_public_context(
		&"ying_li", "zh", ["CTX_RIICHI_OPEN"]
	)
	var ids: Array = []
	for line in with_ctx:
		ids.append(String(line.get("line_id", "")))
	assert_true(ids.has("ai_ying_li_zh_03"))
	assert_true(ids.has("ai_ying_li_zh_01"))


func test_selector_source_is_pure() -> void:
	var src: String = load("res://meta/trash_talk_ai_line_selector.gd").source_code
	for bad in ["randi", "randf", "Time.get", "emit_signal", "ITEM_GRANTED", "REWARD_WINDOW_"]:
		assert_false(src.contains(bad), "选择器不得含: %s" % bad)


func _base_input(overrides: Dictionary) -> Dictionary:
	var d := {
		"rule_version": RV,
		"has_first_discard": true,
	}
	for k in overrides.keys():
		d[k] = overrides[k]
	return d
