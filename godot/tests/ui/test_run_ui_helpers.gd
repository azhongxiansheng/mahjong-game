extends GutTest

# 麻将王 — M4 第 3 步：5 个 Run UI 组件的纯静态 helper 单测
#
# 视觉布局留 F6 烟测人测（M4 第 4 步会出 run_flow_smoke.tscn）。

# ---- RunHud ----

func test_run_hud_format_chapter_text():
	assert_eq(RunHud.format_chapter_text(1, "3"), "Chapter 1 / Floor 3")
	assert_eq(RunHud.format_chapter_text(3, "?"), "Chapter 3 / Floor ?")

func test_run_hud_format_hp_text():
	assert_eq(RunHud.format_hp_text(5, 5), "HP: 5 / 5")
	assert_eq(RunHud.format_hp_text(0, 5), "HP: 0 / 5")
	assert_eq(RunHud.format_hp_text(2, 5), "HP: 2 / 5")

func test_run_hud_format_gold_text():
	assert_eq(RunHud.format_gold_text(0), "金币: 0")
	assert_eq(RunHud.format_gold_text(80), "金币: 80")

# ---- PlaceholderNode ----

func test_placeholder_title_camp():
	assert_eq(PlaceholderNode.title_for_kind(NodeKind.Kind.CAMP), "营地")

func test_placeholder_title_shop():
	assert_eq(PlaceholderNode.title_for_kind(NodeKind.Kind.SHOP), "商店")

func test_placeholder_title_event():
	assert_eq(PlaceholderNode.title_for_kind(NodeKind.Kind.EVENT), "事件")

func test_placeholder_title_fallback_for_battle_kind():
	# 战斗节点不该走 placeholder，但 fallback 到 NodeKind.display_name
	assert_eq(PlaceholderNode.title_for_kind(NodeKind.Kind.NORMAL), "普通桌")

func test_placeholder_description_mentions_M5():
	for kind in [NodeKind.Kind.CAMP, NodeKind.Kind.SHOP, NodeKind.Kind.EVENT]:
		var d := PlaceholderNode.description_for_kind(kind)
		assert_true(d.find("M5") >= 0, "占位描述应提示 M5 实装")

# ---- ChapterMapView ----

func test_chapter_map_format_option_normal():
	var nr := NodeRef.new(5, 1, NodeKind.Kind.NORMAL)
	var s: String = ChapterMapView.format_option_text(1, nr)
	assert_true(s.begins_with("[1] 普通桌"))
	assert_true(s.find("vs 3 SimpleAi") >= 0)

func test_chapter_map_format_option_elite():
	var nr := NodeRef.new(7, 2, NodeKind.Kind.ELITE)
	var s: String = ChapterMapView.format_option_text(2, nr)
	assert_true(s.find("精英") >= 0)

func test_chapter_map_format_option_boss():
	var nr := NodeRef.new(11, 6, NodeKind.Kind.BOSS)
	var s: String = ChapterMapView.format_option_text(1, nr)
	assert_true(s.find("Boss") >= 0)

func test_chapter_map_format_option_placeholder_kinds():
	for kind in [NodeKind.Kind.CAMP, NodeKind.Kind.SHOP, NodeKind.Kind.EVENT]:
		var nr := NodeRef.new(3, 1, kind)
		var s: String = ChapterMapView.format_option_text(1, nr)
		assert_true(s.find("M5") >= 0, "占位节点选项应提示 M5")

func test_chapter_map_format_option_null_safe():
	var s: String = ChapterMapView.format_option_text(1, null)
	assert_eq(s, "[1] ?")

func test_chapter_map_format_last_result_no_loss():
	var nr := NodeRef.new(3, 1, NodeKind.Kind.NORMAL)
	var r := NodeResult.new(2)  # rank 2: hp_delta=0
	var s: String = ChapterMapView.format_last_result(nr, r)
	assert_true(s.find("普通桌") >= 0)
	assert_true(s.find("排名 2") >= 0)
	assert_true(s.find("无血损") >= 0)

func test_chapter_map_format_last_result_with_loss():
	var nr := NodeRef.new(3, 1, NodeKind.Kind.NORMAL)
	var r := NodeResult.new(4)  # rank 4: hp_delta=-2
	var s: String = ChapterMapView.format_last_result(nr, r)
	assert_true(s.find("-2 HP") >= 0)

func test_chapter_map_format_last_result_null_safe():
	assert_eq(ChapterMapView.format_last_result(null, null), "")

# ---- StarterPackPicker ----

func test_starter_pack_picker_format_card_available():
	var p: Dictionary = StarterPacks.control_pack()
	var s: String = StarterPackPicker.format_card_text(p)
	assert_true(s.find("控场型") >= 0)
	assert_false(s.find("（M6 实装）") >= 0, "可用包不该有 M6 标记")

func test_starter_pack_picker_format_card_aggro_now_available():
	# M6 内容生产：aggro pack 已 available，不再显示 M6 标记
	var p: Dictionary = StarterPacks.aggro_pack()
	var s: String = StarterPackPicker.format_card_text(p)
	assert_false(s.find("（M6 实装）") >= 0, "M6 后 aggro 已 available")

# ---- RunSummary ----

func test_run_summary_outcome_title_won():
	assert_true(RunSummary.format_outcome_title(true).find("通关") >= 0)

func test_run_summary_outcome_title_lost():
	assert_true(RunSummary.format_outcome_title(false).find("失败") >= 0)

func test_run_summary_format_summary():
	var rs := RunState.new(42)
	rs.hp = 3
	rs.gold = 75
	rs.chapter = 2
	rs.history.append(NodeRef.new(0, 0, NodeKind.Kind.NORMAL))
	var s: String = RunSummary.format_summary(rs)
	assert_true(s.find("章节: 2") >= 0)
	assert_true(s.find("HP: 3") >= 0)
	assert_true(s.find("金币: 75") >= 0)
	assert_true(s.find("访问节点: 1") >= 0)

func test_run_summary_renown_won_higher_than_lost():
	# 通关 +50 / 失败 +5（v1 占位）
	var won_text := RunSummary.format_renown_placeholder(true)
	var lost_text := RunSummary.format_renown_placeholder(false)
	assert_true(won_text.find("+50") >= 0)
	assert_true(lost_text.find("+5") >= 0)
