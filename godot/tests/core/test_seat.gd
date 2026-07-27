extends GutTest

# Seat (spec §5)：一座位的数据 + 简单 helper。
# Seat 作为聚合根同时持有手牌、牌河与副露。
# deck_owner 字段属于卡组系统（里程碑 4），0e 不实装。

func test_factory_defaults():
	var s := Seat.new(1, TileId.S_WIND)
	assert_eq(s.seat_id, 1)
	assert_eq(s.seat_wind, TileId.S_WIND)
	assert_eq(s.points, 25000, "起家点数默认 25000")
	assert_eq(s.hand.size(), 0)
	assert_eq(s.melds.size(), 0)
	assert_not_null(s.riichi)
	assert_not_null(s.furiten)

func test_factory_custom_points():
	var s := Seat.new(0, TileId.E, 30000)
	assert_eq(s.points, 30000)

func test_add_to_hand_appends_tile():
	var s := Seat.new(0, TileId.E)
	s.add_to_hand(Tile.new(TileId.W5))
	assert_eq(s.hand.size(), 1)

func test_discard_from_hand_removes_first_match():
	# 有效 instance_id 实体 fixture：精确删除指定实体，剩余业务断言不变
	var s := Seat.new(0, TileId.E)
	s.add_to_hand(_tile(TileId.W5, 11))
	s.add_to_hand(_tile(TileId.W3, 12))
	assert_true(s.discard_from_hand(11))
	assert_eq(s.hand.size(), 1)
	assert_eq(s.hand.to_id_array(), [TileId.W3])

func test_discard_from_hand_returns_false_when_absent():
	# 有效 instance_id 实体 fixture：缺失 id 时不删、返回 false
	var s := Seat.new(0, TileId.E)
	s.add_to_hand(_tile(TileId.W5, 21))
	assert_false(s.discard_from_hand(99))
	assert_eq(s.hand.size(), 1)

func test_is_concealed_hand_no_melds():
	var s := Seat.new(0, TileId.E)
	assert_true(s.is_concealed_hand(), "无副露 → 门清")

func test_is_concealed_hand_with_ankan_still_concealed():
	var s := Seat.new(0, TileId.E)
	var ankan := Meld.make_ankan([
		Tile.new(TileId.W1), Tile.new(TileId.W1),
		Tile.new(TileId.W1), Tile.new(TileId.W1)])
	s.melds.add_existing(ankan)
	assert_true(s.is_concealed_hand(), "暗杠不破坏门清")

func test_is_concealed_hand_with_pon_breaks():
	var s := Seat.new(0, TileId.E)
	var pon := Meld.make_pon(
		[Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1)], 1)
	s.melds.add_existing(pon)
	assert_false(s.is_concealed_hand(), "pon 破坏门清")

func test_adjust_points():
	var s := Seat.new(0, TileId.E)
	s.adjust_points(-1500)
	assert_eq(s.points, 23500)
	s.adjust_points(3000)
	assert_eq(s.points, 26500)


func test_meld_ids_are_unique_across_all_seats_and_monotonic_per_seat() -> void:
	var seats: Array[Seat] = []
	for seat_id in range(4):
		seats.append(Seat.new(seat_id, TileId.E))
	var first_ids: Array = []
	var second_ids: Array = []
	for seat in seats:
		var first: Meld = seat.melds.add_ankan([
			Tile.new(TileId.W1), Tile.new(TileId.W1),
			Tile.new(TileId.W1), Tile.new(TileId.W1),
		])
		assert_not_null(first)
		first_ids.append(first.meld_id)
	for seat in seats:
		var second: Meld = seat.melds.add_ankan([
			Tile.new(TileId.W2), Tile.new(TileId.W2),
			Tile.new(TileId.W2), Tile.new(TileId.W2),
		])
		assert_not_null(second)
		second_ids.append(second.meld_id)
	assert_eq(first_ids, [0, 1, 2, 3], "首个副露 ID 按座位唯一")
	assert_eq(second_ids, [4, 5, 6, 7], "同座下一副露跨过四席且保持全局唯一")
	var all_ids: Array = first_ids + second_ids
	var unique: Dictionary = {}
	for meld_id in all_ids:
		unique[meld_id] = true
	assert_eq(unique.size(), all_ids.size(), "公共快照内 meld_id 不得跨座重复")


# ---------------------------------------------------------------------------
# E2-02 / #232 Red：discard_from_hand 正式参数 = instance_id（无 tile_id fallback）
# 真实 Seat/Tile/Hand，不 mock。生产仍按 tile_id 删除时应失败。
# ---------------------------------------------------------------------------

func _tile(tid: int, iid: int, red: bool = false, p_owner: int = Tile.NO_OWNER) -> Tile:
	return Tile.new(tid, red, p_owner, iid)


func _hand_snapshot(seat: Seat) -> Array:
	# 有序实体指纹：id / instance_id / is_red_dora / owner_seat
	var out: Array = []
	for t in seat.hand.tiles():
		out.append({
			"id": t.id,
			"instance_id": t.instance_id,
			"is_red_dora": t.is_red_dora,
			"owner_seat": t.owner_seat,
		})
	return out


func test_discard_from_hand_by_instance_id_removes_exact_red_or_normal_w5() -> void:
	# 同 TileId.W5 的赤牌与普通牌、不同 instance_id → 精确移除指定实体，不误伤同 id 其它张
	var s := Seat.new(0, TileId.E)
	var red_w5 := _tile(TileId.W5, 101, true, 0)
	var normal_w5_a := _tile(TileId.W5, 102, false, 0)
	var normal_w5_b := _tile(TileId.W5, 103, false, 1)
	var other := _tile(TileId.W3, 104, false, 0)
	s.add_to_hand(red_w5)
	s.add_to_hand(normal_w5_a)
	s.add_to_hand(normal_w5_b)
	s.add_to_hand(other)

	assert_true(s.discard_from_hand(102), "应按 instance_id=102 移除普通 W5，不得按 tile_id 猜")
	assert_eq(s.hand.size(), 3)
	var after_102: Array = _hand_snapshot(s)
	assert_eq(after_102.size(), 3)
	assert_eq(int(after_102[0]["instance_id"]), 101)
	assert_true(bool(after_102[0]["is_red_dora"]), "赤 W5 必须保留")
	assert_eq(int(after_102[1]["instance_id"]), 103)
	assert_false(bool(after_102[1]["is_red_dora"]))
	assert_eq(int(after_102[2]["instance_id"]), 104)
	assert_eq(int(after_102[2]["id"]), TileId.W3)

	assert_true(s.discard_from_hand(101), "再精确移除赤 W5 instance_id=101")
	var after_101: Array = _hand_snapshot(s)
	assert_eq(after_101.size(), 2)
	assert_eq(int(after_101[0]["instance_id"]), 103)
	assert_eq(int(after_101[0]["id"]), TileId.W5)
	assert_false(bool(after_101[0]["is_red_dora"]))
	assert_eq(int(after_101[1]["instance_id"]), 104)


func test_discard_from_hand_does_not_fallback_to_tile_id() -> void:
	# instance_id 故意等于 TileId.W5(=4)，但那张是 W3；W5 实体用另一 iid。
	# 正式语义：discard(4) 移除 instance_id=4 的 W3，绝不能按 tile_id 删 W5。
	var s := Seat.new(0, TileId.E)
	var w5 := _tile(TileId.W5, 200, false, 0)
	var w3_with_w5_as_iid := _tile(TileId.W3, TileId.W5, false, 0)
	s.add_to_hand(w5)
	s.add_to_hand(w3_with_w5_as_iid)

	assert_true(s.discard_from_hand(TileId.W5), "参数是 instance_id，值=TileId.W5 时命中 W3 实体")
	assert_eq(s.hand.size(), 1)
	assert_eq(s.hand.tiles()[0].id, TileId.W5, "W5 实体必须保留（无 tile_id fallback）")
	assert_eq(s.hand.tiles()[0].instance_id, 200)


func test_discard_from_hand_invalid_or_missing_instance_id_returns_false_zero_mod() -> void:
	var s := Seat.new(0, TileId.E)
	s.add_to_hand(_tile(TileId.W5, 201, true, 0))
	s.add_to_hand(_tile(TileId.W5, 202, false, 1))
	s.add_to_hand(_tile(TileId.W3, 203, false, 0))
	var before: Array = _hand_snapshot(s)

	assert_false(s.discard_from_hand(Tile.INVALID_INSTANCE_ID),
		"INVALID_INSTANCE_ID 必须 false")
	assert_eq(_hand_snapshot(s), before, "INVALID_INSTANCE_ID：手牌内容与顺序零修改")

	assert_false(s.discard_from_hand(99999), "缺失 instance_id 必须 false")
	assert_eq(_hand_snapshot(s), before, "缺失 instance_id：手牌内容与顺序零修改")
	assert_eq(s.hand.size(), 3)
