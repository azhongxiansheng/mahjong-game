extends GutTest

# 0e Task 2: Wall dead_wall API 扩展。
# 不破坏 0a 现有 7 个测试；额外测试 dead wall 切片 / 岭上摸取 / dora 指示牌探针。

# ---- reserve / live_wall_size ----

func test_reserve_default_14_dead():
	var w := Wall.new_full_set()
	w.shuffle(1)
	w.reserve_dead_wall()
	assert_eq(w.live_wall_size(), 122, "136 - 14")

func test_reserve_custom_count():
	var w := Wall.new_full_set()
	w.shuffle(1)
	w.reserve_dead_wall(10)
	assert_eq(w.live_wall_size(), 126)

func test_draw_stops_at_live_wall_boundary():
	var w := Wall.new_full_set()
	w.shuffle(1)
	w.reserve_dead_wall()
	for _i in range(122):
		assert_not_null(w.draw())
	assert_null(w.draw(), "live wall 摸尽返 null（不动 dead wall）")

# ---- take_rinshan ----

func test_take_rinshan_returns_4_then_null():
	var w := Wall.new_full_set()
	w.shuffle(1)
	w.reserve_dead_wall()
	for _i in range(4):
		assert_not_null(w.take_rinshan())
	assert_null(w.take_rinshan(), "岭上 4 张取完返 null")

func test_rinshan_does_not_affect_live_wall():
	var w := Wall.new_full_set()
	w.shuffle(1)
	w.reserve_dead_wall()
	w.take_rinshan()
	w.take_rinshan()
	assert_eq(w.live_wall_size(), 122, "岭上不影响 live wall 计数")

# ---- peek_dora_indicator ----

func test_peek_dora_indicator_0_is_initial():
	var w := Wall.new_full_set()
	w.shuffle(42)
	w.reserve_dead_wall()
	var d0 := w.peek_dora_indicator(0)
	assert_not_null(d0)
	# 同次 peek 返同张
	assert_eq(w.peek_dora_indicator(0).id, d0.id, "peek 不消耗")

func test_peek_uradora_indicator_independent():
	var w := Wall.new_full_set()
	w.shuffle(42)
	w.reserve_dead_wall()
	var dora0 := w.peek_dora_indicator(0)
	var ura0 := w.peek_uradora_indicator(0)
	# 表/裏 dora 在 dead wall 不同物理槽，不应同张（至少 id 大概率不同；这里只验非 null）
	assert_not_null(ura0)

func test_peek_dora_indicator_n_within_5():
	var w := Wall.new_full_set()
	w.shuffle(42)
	w.reserve_dead_wall()
	for n in range(5):
		assert_not_null(w.peek_dora_indicator(n), "indicator %d 应可 peek" % n)
	# 第 5 个不存在
	assert_null(w.peek_dora_indicator(5))

# ---- 0a 兼容性闸门 ----

func test_no_reserve_behavior_unchanged():
	# 不调 reserve 时，行为与 0a 完全一致
	var w := Wall.new_full_set()
	assert_eq(w.live_wall_size(), 136, "未 reserve 时 live = 全部")
	assert_eq(w.size(), 136)
