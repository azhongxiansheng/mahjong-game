extends GutTest

# 麻将王 — SeatPanel.split_hand_for_display 单测（spec 2026-05-08 bug 2 fix）
# E2-02 / #232：drawn 分离只认 last_drawn_instance_id；INVALID 不拆。
#
# 测纯算法：给定 Hand + drawn_instance_id → sorted + drawn 实体
# 不依赖 SceneTree / TextureExtractor / 任何 UI。

func _hand(ids: Array) -> Hand:
	var h := Hand.new()
	var serial: int = 0
	for tid in ids:
		h.add(Tile.new(tid, false, 0, serial))
		serial += 1
	return h


func _hand_entities(entries: Array) -> Hand:
	# entries: Array[{id, iid, red?}]
	var h := Hand.new()
	for e in entries:
		h.add(Tile.new(int(e["id"]), bool(e.get("red", false)), 0, int(e["iid"])))
	return h

# ---- drawn_instance_id INVALID：全 sorted ----

func test_no_drawn_returns_all_sorted():
	# 13 张混乱顺序 + INVALID → sorted 13 张，drawn_ids = []
	var h := _hand([
		TileId.W5, TileId.W2, TileId.HAKU,
		TileId.S3, TileId.T6, TileId.W1,
		TileId.E, TileId.W2, TileId.S9,
		TileId.T2, TileId.W4, TileId.W3,
		TileId.S5,
	])
	var split: Dictionary = SeatPanel.split_hand_for_display(h, Tile.INVALID_INSTANCE_ID)
	assert_true(split.has("sorted_instance_ids") and split.has("drawn_instance_ids"),
		"split 须返回 sorted/drawn_instance_ids")
	assert_eq(split.sorted_ids.size(), 13)
	assert_eq(split.drawn_ids.size(), 0)
	assert_eq(split.drawn_instance_ids.size(), 0)
	assert_eq(split.sorted_instance_ids.size(), 13)
	# sorted 升序 — 验证全部相邻顺序
	for i in range(split.sorted_ids.size() - 1):
		assert_true(int(split.sorted_ids[i]) <= int(split.sorted_ids[i + 1]),
			"sorted_ids 升序: idx %d (%d) <= idx %d (%d)" % [
				i, int(split.sorted_ids[i]), i + 1, int(split.sorted_ids[i + 1])])

# ---- drawn_instance_id 在 hand 中：分离 ----

func test_drawn_separated_at_right():
	# 14 张含刚摸的 W5；drawn instance 指向末张 → sorted 13 + drawn=[W5]
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.CHUN,
		TileId.W5,  # serial=13 = 刚摸
	])
	var drawn_iid: int = h._tiles[h._tiles.size() - 1].instance_id
	var split: Dictionary = SeatPanel.split_hand_for_display(h, drawn_iid)
	assert_eq(split.sorted_ids.size(), 13, "13 张 sorted")
	assert_eq(split.drawn_ids.size(), 1, "1 张 drawn")
	assert_eq(int(split.drawn_ids[0]), TileId.W5)
	assert_eq(int(split.drawn_instance_ids[0]), drawn_iid)
	# 验证 W5 不在 sorted 中（被 pop 掉）
	assert_false(split.sorted_ids.has(TileId.W5),
		"刚摸的 W5 不该在 sorted 中（已被弹出）")

# ---- drawn 凑 pair：只 pop 精确 instance，保留另一张 ----

func test_drawn_pair_only_one_separated():
	# 手牌已有 W5；又摸 1 张 W5 → 共 2 张 W5，instance 不同
	var h := _hand_entities([
		{"id": TileId.W2, "iid": 1}, {"id": TileId.W3, "iid": 2}, {"id": TileId.W4, "iid": 3},
		{"id": TileId.T2, "iid": 4}, {"id": TileId.T3, "iid": 5}, {"id": TileId.T4, "iid": 6},
		{"id": TileId.S2, "iid": 7}, {"id": TileId.S3, "iid": 8}, {"id": TileId.S4, "iid": 9},
		{"id": TileId.S6, "iid": 10}, {"id": TileId.S7, "iid": 11}, {"id": TileId.S8, "iid": 12},
		{"id": TileId.W5, "iid": 20},  # 已有
		{"id": TileId.W5, "iid": 21},  # 刚摸
	])
	var split: Dictionary = SeatPanel.split_hand_for_display(h, 21)
	assert_eq(split.sorted_ids.size(), 13)
	assert_eq(split.drawn_ids.size(), 1)
	assert_eq(int(split.drawn_instance_ids[0]), 21)
	assert_true(split.sorted_instance_ids.has(20), "sorted 中保留另一张 W5 实体")
	assert_false(split.sorted_instance_ids.has(21))
	var w5_count_in_sorted: int = 0
	for tid in split.sorted_ids:
		if int(tid) == TileId.W5:
			w5_count_in_sorted += 1
	assert_eq(w5_count_in_sorted, 1, "sorted 中保留 1 张 W5")

# ---- 同值赤/黑：必须拆出实际刚摸实体 ----

func test_drawn_red_black_same_value_picks_exact_entity():
	var h := _hand_entities([
		{"id": TileId.W2, "iid": 1}, {"id": TileId.W3, "iid": 2}, {"id": TileId.W4, "iid": 3},
		{"id": TileId.T2, "iid": 4}, {"id": TileId.T3, "iid": 5}, {"id": TileId.T4, "iid": 6},
		{"id": TileId.S2, "iid": 7}, {"id": TileId.S3, "iid": 8}, {"id": TileId.S4, "iid": 9},
		{"id": TileId.S6, "iid": 10}, {"id": TileId.S7, "iid": 11}, {"id": TileId.S8, "iid": 12},
		{"id": TileId.W5, "iid": 30, "red": false},
		{"id": TileId.W5, "iid": 31, "red": true},  # 刚摸赤
	])
	var split: Dictionary = SeatPanel.split_hand_for_display(h, 31)
	assert_eq(int(split.drawn_instance_ids[0]), 31)
	assert_true(bool(split.drawn_reds[0]))
	assert_true(split.sorted_instance_ids.has(30))
	# 若误按 tile_id 从末尾/首张 pop，可能拆错实体
	assert_false(split.sorted_instance_ids.has(31))

# ---- drawn 不在 hand 中：fallback 全 sorted ----

func test_drawn_not_in_hand_fallback_all_sorted():
	# 异常：drawn instance 不在 hand → fallback 全 sorted
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.CHUN,
	])
	var split: Dictionary = SeatPanel.split_hand_for_display(h, 99999)
	assert_eq(split.sorted_ids.size(), 13, "fallback 13 张全 sorted")
	assert_eq(split.drawn_ids.size(), 0, "drawn_ids 空")
	assert_eq(split.drawn_instance_ids.size(), 0)

# ---- 边界：空 hand ----

func test_empty_hand():
	var h := Hand.new()
	var split: Dictionary = SeatPanel.split_hand_for_display(h, Tile.INVALID_INSTANCE_ID)
	assert_eq(split.sorted_ids.size(), 0)
	assert_eq(split.drawn_ids.size(), 0)
	assert_eq(split.sorted_instance_ids.size(), 0)

# ---- 边界：drawn 是字牌 ----

func test_drawn_honor_tile():
	# 摸到字牌 (HAKU) — 算法应正常分离
	var h := _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.CHUN,
		TileId.HAKU,  # 刚摸 serial=13
	])
	var drawn_iid: int = h._tiles[h._tiles.size() - 1].instance_id
	var split: Dictionary = SeatPanel.split_hand_for_display(h, drawn_iid)
	assert_eq(split.sorted_ids.size(), 13)
	assert_eq(split.drawn_ids.size(), 1)
	assert_eq(int(split.drawn_ids[0]), TileId.HAKU)
	assert_eq(int(split.drawn_instance_ids[0]), drawn_iid)

# ---- 同 tile_id 多实体：按 original_index 保持相对顺序 ----

func test_same_tile_id_preserves_original_index_order():
	# Hand 原始序：W3,W1,W3,W1,W3 → 排序后同值按 original_index 稳定
	# 期望 sorted_instance_ids = [11,13, 10,12,14]
	var h := _hand_entities([
		{"id": TileId.W3, "iid": 10},
		{"id": TileId.W1, "iid": 11},
		{"id": TileId.W3, "iid": 12},
		{"id": TileId.W1, "iid": 13},
		{"id": TileId.W3, "iid": 14},
	])
	var split: Dictionary = SeatPanel.split_hand_for_display(h, Tile.INVALID_INSTANCE_ID)
	assert_eq(split.sorted_instance_ids, [11, 13, 10, 12, 14],
		"同 tile_id 必须按 Hand 原始下标 original_index 保序，禁止仅按 tile_id 不稳定排序")
	# 赤/黑同值：黑在前、赤在后（原始序），不得因 instance_id 大小颠倒
	var h2 := _hand_entities([
		{"id": TileId.W5, "iid": 200, "red": false},
		{"id": TileId.W2, "iid": 201},
		{"id": TileId.W5, "iid": 30, "red": true},  # 后出现的赤 5，instance 更小
	])
	var split2: Dictionary = SeatPanel.split_hand_for_display(h2, Tile.INVALID_INSTANCE_ID)
	assert_eq(split2.sorted_instance_ids, [201, 200, 30],
		"同值赤黑按 original_index，不得用 instance_id 作 tie-break")
