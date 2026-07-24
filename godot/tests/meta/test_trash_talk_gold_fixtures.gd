extends GutTest

# E5-01 / #249：黄金 fixture 硬编码摘要钉死（禁止自证互比）。

const GOLD_ZERO_DIGEST := "65e26a7e"
const GOLD_TEXT_DIGEST := "5832cc42"


func test_gold_zero_hardcoded_digest() -> void:
	var fixture: Dictionary = TrashTalkGoldFixtures.gold_zero()
	assert_eq(String(fixture.get("fixture_id", "")), "gold_zero_v1")
	assert_eq(String(fixture.get("rule_version", "")), "trash_talk_rules_v1")
	var digest := TrashTalkGoldFixtures.stable_digest(fixture)
	assert_eq(digest, GOLD_ZERO_DIGEST,
		"gold_zero_v1 digest 漂移: %s" % digest)
	_assert_all_components_zero(fixture)


func test_gold_text_hardcoded_digest() -> void:
	var fixture: Dictionary = TrashTalkGoldFixtures.gold_text()
	assert_eq(String(fixture.get("fixture_id", "")), "gold_text_v1")
	var digest := TrashTalkGoldFixtures.stable_digest(fixture)
	assert_eq(digest, GOLD_TEXT_DIGEST, "gold_text_v1 digest 漂移: %s" % digest)
	var expected: Dictionary = fixture.get("expected", {})
	var any_nonzero := false
	for row in expected.get("matrix_components", []):
		for key in ["persona", "item_tag", "public_context", "expression"]:
			var v: int = int(row.get(key, 0))
			assert_true(v >= 0 and v <= 1000)
			if v > 0:
				any_nonzero = true
	assert_true(any_nonzero)
	for rid in expected.get("matched_rule_ids_by_seat", {}).get("1", []):
		assert_true(TrashTalkRuleCatalog.has_rule_id(String(rid)))


func test_digest_changes_when_integer_or_text_mutates() -> void:
	var base: Dictionary = TrashTalkGoldFixtures.gold_text()
	var base_digest := TrashTalkGoldFixtures.stable_digest(base)
	var mutated: Dictionary = base.duplicate(true)
	var comps: Array = mutated["expected"]["matrix_components"]
	comps[0]["persona"] = int(comps[0]["persona"]) + 1
	assert_ne(TrashTalkGoldFixtures.stable_digest(mutated), base_digest)
	var mutated2: Dictionary = base.duplicate(true)
	mutated2["texts_by_seat"]["1"] = "漂移文本"
	assert_ne(TrashTalkGoldFixtures.stable_digest(mutated2), base_digest)
	var mutated3: Dictionary = base.duplicate(true)
	var rules: Array = mutated3["expected"]["matched_rule_ids_by_seat"]["1"].duplicate()
	rules.reverse()
	mutated3["expected"]["matched_rule_ids_by_seat"]["1"] = rules
	assert_ne(TrashTalkGoldFixtures.stable_digest(mutated3), base_digest)


func test_stable_stringify_escapes_and_quotes_keys() -> void:
	var s := TrashTalkGoldFixtures.stable_stringify({
		"a": "x\"y\\z\n\t\r",
	})
	assert_true(s.contains("\\\""))
	assert_true(s.contains("\\\\"))
	assert_true(s.contains("\\n"))
	assert_true(s.contains("\\t"))
	assert_true(s.contains("\\r"))
	assert_eq(TrashTalkGoldFixtures.stable_stringify({"b": 1, "a": 2}), "{\"a\":2,\"b\":1}")
	# 特殊 key：冒号、逗号、引号必须加引号并转义，序列化无歧义
	var special := TrashTalkGoldFixtures.stable_stringify({
		":,": 1,
		"a\"b": 2,
		"c,d": 3,
	})
	assert_eq(special, "{\":,\":1,\"a\\\"b\":2,\"c,d\":3}")


func test_gold_fixtures_list_contains_both() -> void:
	var ids: Array = []
	for f in TrashTalkGoldFixtures.all():
		ids.append(String(f.get("fixture_id", "")))
	ids.sort()
	assert_eq(ids, ["gold_text_v1", "gold_zero_v1"])


func _assert_all_components_zero(fixture: Dictionary) -> void:
	var expected: Dictionary = fixture.get("expected", {})
	for row in expected.get("matrix_components", []):
		for key in ["persona", "item_tag", "public_context", "expression"]:
			assert_eq(int(row.get(key, -1)), 0)
	var matched: Dictionary = expected.get("matched_rule_ids_by_seat", {})
	for seat_key in matched.keys():
		assert_eq(matched[seat_key].size(), 0)
