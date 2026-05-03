extends GutTest

# 麻将王 — M6 收尾：ChapterConfig boss_id 单测

func test_chapter_1_boss_is_iron_curtain():
	assert_eq(ChapterConfig.get_boss_id(1), &"boss1_iron_curtain_v1")

func test_chapter_2_boss_is_fortune_runner():
	assert_eq(ChapterConfig.get_boss_id(2), &"boss2_fortune_runner_v1")

func test_chapter_3_boss_is_kanmon():
	assert_eq(ChapterConfig.get_boss_id(3), &"boss3_kanmon_v1")

func test_unknown_chapter_returns_empty():
	assert_eq(ChapterConfig.get_boss_id(99), &"")
	assert_eq(ChapterConfig.get_boss_id(0), &"")

func test_each_chapter_dict_has_boss_id_field():
	for i in range(1, ChapterConfig.chapter_count() + 1):
		var cfg: Dictionary = ChapterConfig.get_chapter(i)
		assert_true(cfg.has("boss_id"), "chapter %d 应有 boss_id 字段" % i)

func test_boss_id_is_known_in_factory():
	# 防止 chapter_config 与 BossAbilityFactory 漂移
	var known: Array = BossAbilityFactory.known_boss_ids()
	for i in range(1, ChapterConfig.chapter_count() + 1):
		var bid: StringName = ChapterConfig.get_boss_id(i)
		assert_true(known.has(bid), "chapter %d boss_id %s 必须在 BossAbilityFactory 注册" % [i, bid])
