extends GutTest

# 麻将王 — M5 第 1 步：PityState 单测

func test_initial_no_streak():
	var p := PityState.new()
	assert_eq(p.node_single_no_epic_streak, 0)
	assert_false(p.node_single_pity_active())

func test_record_common_increments_streak():
	var p := PityState.new()
	p.record_draw(Rarity.Kind.COMMON)
	assert_eq(p.node_single_no_epic_streak, 1)
	p.record_draw(Rarity.Kind.UNCOMMON)
	assert_eq(p.node_single_no_epic_streak, 2)

func test_record_epic_resets_streak():
	var p := PityState.new()
	for i in range(5):
		p.record_draw(Rarity.Kind.COMMON)
	p.record_draw(Rarity.Kind.EPIC)
	assert_eq(p.node_single_no_epic_streak, 0)

func test_record_legendary_resets_streak():
	var p := PityState.new()
	p.record_draw(Rarity.Kind.UNCOMMON)
	p.record_draw(Rarity.Kind.LEGENDARY)
	assert_eq(p.node_single_no_epic_streak, 0)

func test_pity_active_at_threshold():
	var p := PityState.new()
	for i in range(PityState.NODE_SINGLE_PITY_THRESHOLD):
		p.record_draw(Rarity.Kind.COMMON)
	assert_true(p.node_single_pity_active(), "刚好 8 次无史诗+ 应触发保底")

func test_pity_not_active_before_threshold():
	var p := PityState.new()
	for i in range(PityState.NODE_SINGLE_PITY_THRESHOLD - 1):
		p.record_draw(Rarity.Kind.COMMON)
	assert_false(p.node_single_pity_active(), "7 次还不应触发")

func test_threshold_is_8():
	# spec §9.2：节点抽卡连续 8 次无史诗+ → 下一抽必史诗+
	assert_eq(PityState.NODE_SINGLE_PITY_THRESHOLD, 8)

func test_reset():
	var p := PityState.new()
	for i in range(PityState.NODE_SINGLE_PITY_THRESHOLD):
		p.record_draw(Rarity.Kind.COMMON)
	p.reset()
	assert_eq(p.node_single_no_epic_streak, 0)
	assert_false(p.node_single_pity_active())
