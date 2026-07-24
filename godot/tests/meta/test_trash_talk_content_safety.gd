extends GutTest

# E5-01 / #249：IP / 禁词 / E6 / 卦象 / 有害内容负向。

const OLD_PRODUCTION_IDS: Array = [
	"akagi", "kaiji", "washizu", "saki", "teru", "awai",
	"koromo", "nodoka", "toki", "kuro", "momoko", "tetsuya",
]

const OLD_PRODUCTION_NAMES: Array = [
	"赤木", "开司", "鹲巣", "宫永咲", "宫永照", "大星淡",
	"天江衣", "原村和", "園城寺怜", "松実玄", "東横桃子", "哲也",
	"宫永", "鷲巣", "鹫巢",
]

const FORBIDDEN_FRAGMENTS: Array = [
	"举报", "禁言", "座位静音", "自动禁言", "审核", "e6", "E6",
	"卦名", "卦象", "爻辞", "八卦", "爻",
	"owner_character_id",
	"skill_effect_multiplier",
	"自杀", "自残", "去死", "杀死你",
]

# 旧错误 + round-3 夹生缩写一律禁止（须用自然日文）
const FORBIDDEN_JA_TOKENS: Array = [
	# round-2 及更早
	"加符", "リーチ加符", "翻減", "翻倍", "翻水晶",
	# round-3 夹生
	"加翻", "減翻", "ハン倍", "リーチ加翻", "ハン水晶",
]


func test_visible_content_has_no_ip_or_forbidden_terms() -> void:
	var blob: String = TrashTalkRuleCatalog.all_visible_text_blob()
	# 旧罗马 id 只查结构化引用，避免 toki/saki 等短串误伤英文词
	for old_id in OLD_PRODUCTION_IDS:
		assert_false(blob.contains('"%s"' % old_id), "不得引用旧 id 字符串: %s" % old_id)
		assert_false(blob.contains("&\"%s\"" % old_id), "不得引用旧 id StringName: %s" % old_id)
		assert_null(CharacterPool.find(StringName(old_id)))
	for cid in TrashTalkRuleCatalog.character_ids():
		assert_false(OLD_PRODUCTION_IDS.has(cid), "规则库角色不得用旧 id: %s" % cid)
	for old_display_name in OLD_PRODUCTION_NAMES:
		assert_false(blob.contains(old_display_name), "不得出现旧 IP 名: %s" % old_display_name)
	for frag in FORBIDDEN_FRAGMENTS:
		assert_false(blob.contains(frag), "禁词: %s" % frag)


func test_japanese_mahjong_han_fu_terminology_not_confused() -> void:
	# 扫描全部日文关键词 / 人设 / AI / item patterns（含 rule 双份）
	var ja_tokens: Array = []
	for cid in TrashTalkRuleCatalog.character_ids():
		var p: Dictionary = TrashTalkRuleCatalog.character_persona(StringName(cid))
		for kw in p.get("keywords", {}).get("ja", []):
			ja_tokens.append(String(kw))
		for t in p.get("human_templates", {}).get("ja", []):
			ja_tokens.append(String(t))
		for line in p.get("ai_templates", {}).get("ja", []):
			ja_tokens.append(String(line.get("text", "")))
	for item_id in TrashTalkRuleCatalog.grantable_item_ids():
		var def: Dictionary = TrashTalkRuleCatalog.item_def(StringName(item_id))
		for pat in def.get("patterns", {}).get("ja", []):
			ja_tokens.append(String(pat))
		for rule in def.get("rules", []):
			for pat2 in rule.get("match", {}).get("patterns", {}).get("ja", []):
				ja_tokens.append(String(pat2))
	for token in ja_tokens:
		for bad in FORBIDDEN_JA_TOKENS:
			# 仅精确匹配：避免「1翻減少」被「翻減」子串误伤
			assert_false(token == bad,
				"日文 token 不得为错误/夹生术语 [%s]" % bad)
	# 正向：自然日文精确表达
	var lian_kw: Array = TrashTalkRuleCatalog.character_persona(&"lian_yao").get("keywords", {}).get("ja", [])
	assert_true(lian_kw.has("翻数追加"), "连曜日文关键词须含 翻数追加")
	_assert_ja_patterns_exact(&"double_payout_v1", ["倍率券", "翻数2倍", "圧倒"])
	_assert_ja_patterns_exact(&"relic_iron_will_v1", ["鉄壁の意志", "1翻減少", "粘り"])
	_assert_ja_patterns_exact(&"relic_dragon_seal_v1", ["龍印", "三元", "1翻追加"])
	_assert_ja_patterns_exact(&"relic_han_crystal_v1", ["翻数水晶", "リーチ時1翻追加", "爆発"])
	# item 与 rule.match 双份 patterns 一致
	for item_id in ["double_payout_v1", "relic_iron_will_v1", "relic_dragon_seal_v1", "relic_han_crystal_v1"]:
		var def2: Dictionary = TrashTalkRuleCatalog.item_def(StringName(item_id))
		var top_ja: Array = def2.get("patterns", {}).get("ja", [])
		var rule0: Dictionary = def2.get("rules", [])[0]
		var match_ja: Array = rule0.get("match", {}).get("patterns", {}).get("ja", [])
		assert_eq(top_ja, match_ja, "item/rule 日文 patterns 必须双份一致: %s" % item_id)


func _assert_ja_patterns_exact(item_id: StringName, expected_ja: Array) -> void:
	var def: Dictionary = TrashTalkRuleCatalog.item_def(item_id)
	var top_ja: Array = def.get("patterns", {}).get("ja", [])
	assert_eq(top_ja, expected_ja, "item %s 顶层 ja patterns 精确匹配" % item_id)
	var match_ja: Array = def.get("rules", [])[0].get("match", {}).get("patterns", {}).get("ja", [])
	assert_eq(match_ja, expected_ja, "item %s rule.match ja patterns 精确匹配" % item_id)


func test_no_owner_or_hexagram_fields_in_item_defs() -> void:
	for item_id in TrashTalkRuleCatalog.grantable_item_ids():
		var def: Dictionary = TrashTalkRuleCatalog.item_def(StringName(item_id))
		for bad_key in ["owner_character_id", "growth_stage", "hexagram", "yao"]:
			assert_false(def.has(bad_key), "%s 不得含 %s" % [item_id, bad_key])


func test_rules_contain_no_moderation_actions() -> void:
	for rule in TrashTalkRuleCatalog.all_rules():
		var s := str(rule)
		for bad in ["report", "mute", "ban", "举报", "禁言", "审核"]:
			assert_false(s.contains(bad), "规则不得含审核动作: %s in %s" % [bad, rule.get("rule_id", "")])


func test_catalog_source_has_no_e6_or_reward_side_effects() -> void:
	for path in [
		"res://meta/trash_talk_rule_catalog.gd",
		"res://meta/trash_talk_ai_line_selector.gd",
		"res://meta/trash_talk_gold_fixtures.gd",
	]:
		var src: String = load(path).source_code
		for bad in [
			"ITEM_GRANTED", "REWARD_WINDOW_", "emit_signal",
			"skill_effect_multiplier", "举报", "禁言",
		]:
			assert_false(src.contains(bad), "%s 不得含 %s" % [path, bad])
