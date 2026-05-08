extends GutTest

# 麻将王 — SeatPanel.split_hand_for_display 单测（spec 2026-05-08 bug 2 fix）
#
# 测纯算法：给定 Hand + drawn_tile_id → {sorted_ids: 13 张升序, drawn_ids: [drawn]}
# 不依赖 SceneTree / TextureExtractor / 任何 UI。

func _hand(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

# ---- drawn_tile_id < 0：全 sorted ----

func test_no_drawn_returns_all_sorted():
	# 13 张混乱顺序 + drawn=-1 → sorted 13 张，drawn_ids = []
	var h := _hand([
		TileId.W5, TileId.W2, TileId.HAKU,
		TileId.S3, TileId.T6, TileId.W1,
		TileId.E, TileId.W2, TileId.S9,
		TileId.T2, TileId.W4, TileId.W3,
		TileId.S5,
	])
	var split: Dictionary = SeatPanel.split_hand_for_display(h, -1)
	assert_eq(split.sorted_ids.size(), 13)
	assert_eq(split.drawn_ids.size(), 0)
	# sorted 升序 — 验证全部相邻顺序
	for i in range(split.sorted_ids.size() - 1):
		assert_true(int(split.sorted_ids[i]) <= int(split.sorted_ids[i + 1]),
			"sorted_ids 升序: idx %d (%d) <= idx %d (%d)" % [
				i, int(split.sorted_ids[i]), i + 1, int(split.sorted_ids[i + 1])])

# ---- drawn_tile_id >= 0 在 hand 中：分离 ----

func test_drawn_separated_at_right():
	# 14 张含刚摸的 W5；drawn=W5 → sorted 13 张升序 + drawn=[W5]
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.CHUN,
		TileId.W5,  # 最后插入 = 刚摸的
	])
	var split: Dictionary = SeatPanel.split_hand_for_display(h, TileId.W5)
	assert_eq(split.sorted_ids.size(), 13, "13 张 sorted")
	assert_eq(split.drawn_ids.size(), 1, "1 张 drawn")
	assert_eq(int(split.drawn_ids[0]), TileId.W5)
	# 验证 W5 不在 sorted 中（被 pop 掉）
	assert_false(split.sorted_ids.has(TileId.W5),
		"刚摸的 W5 不该在 sorted 中（已被弹出）")

# ---- drawn 凑 pair：只 pop 1 张，保留其余按 sorted 渲染 ----

func test_drawn_pair_only_one_separated():
	# 手牌已有 W5；又摸 1 张 W5 → 共 2 张 W5
	# split 应只 pop 1 张到 drawn，另 1 张留在 sorted
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.W5,        # 已有 1 张 W5
		TileId.W5,        # 刚摸 1 张 W5（最后插入）
	])
	var split: Dictionary = SeatPanel.split_hand_for_display(h, TileId.W5)
	assert_eq(split.sorted_ids.size(), 13)
	assert_eq(split.drawn_ids.size(), 1)
	# sorted 中应仍有 1 张 W5（因为只 pop 了 1 张）
	var w5_count_in_sorted: int = 0
	for tid in split.sorted_ids:
		if int(tid) == TileId.W5:
			w5_count_in_sorted += 1
	assert_eq(w5_count_in_sorted, 1, "sorted 中保留 1 张 W5")

# ---- drawn 不在 hand 中：fallback 全 sorted ----

func test_drawn_not_in_hand_fallback_all_sorted():
	# 异常：drawn=W5 但 hand 没有 W5 → fallback 全 sorted
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.CHUN,
	])
	var split: Dictionary = SeatPanel.split_hand_for_display(h, TileId.W5)
	assert_eq(split.sorted_ids.size(), 13, "fallback 13 张全 sorted")
	assert_eq(split.drawn_ids.size(), 0, "drawn_ids 空")

# ---- 边界：空 hand ----

func test_empty_hand():
	var h := Hand.new()
	var split: Dictionary = SeatPanel.split_hand_for_display(h, -1)
	assert_eq(split.sorted_ids.size(), 0)
	assert_eq(split.drawn_ids.size(), 0)

# ---- 边界：drawn 是字牌 ----

func test_drawn_honor_tile():
	# 摸到字牌 (HAKU) — 算法应正常分离
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.CHUN,
		TileId.HAKU,  # 刚摸
	])
	var split: Dictionary = SeatPanel.split_hand_for_display(h, TileId.HAKU)
	assert_eq(split.sorted_ids.size(), 13)
	assert_eq(split.drawn_ids.size(), 1)
	assert_eq(int(split.drawn_ids[0]), TileId.HAKU)
