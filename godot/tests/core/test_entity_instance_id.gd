extends GutTest

# E2-02 / #232 切片 Red：牌实体 instance_id 契约（Tile / Wall / Hand / Seat / Meld）
# 真实 core 类型，不 mock。生产实现前本文件应失败。


func _tile(tid: int, iid: int, red: bool = false, p_owner: int = Tile.NO_OWNER) -> Tile:
	return Tile.new(tid, red, p_owner, iid)


func _hand_iids(h: Hand) -> Array:
	var out: Array = []
	for t in h._tiles:
		out.append(t.instance_id)
	return out


func _hand_red_flags(h: Hand) -> Array:
	var out: Array = []
	for t in h._tiles:
		out.append(t.is_red_dora)
	return out


# ---------------------------------------------------------------------------
# Tile：instance_id / INVALID_INSTANCE_ID / owner_seat 非 identity / clone+序列化
# ---------------------------------------------------------------------------

func test_tile_instance_id_default_is_invalid() -> void:
	var t := Tile.new(TileId.W5)
	assert_eq(t.instance_id, Tile.INVALID_INSTANCE_ID, "默认 instance_id = INVALID_INSTANCE_ID")
	assert_eq(Tile.INVALID_INSTANCE_ID, -1)


func test_owner_seat_is_not_identity() -> void:
	# 同 owner、同 tile_id 的两张牌必须能以 instance_id 区分
	var a := _tile(TileId.W5, 10, false, 0)
	var b := _tile(TileId.W5, 11, false, 0)
	assert_eq(a.owner_seat, b.owner_seat)
	assert_eq(a.id, b.id)
	assert_ne(a.instance_id, b.instance_id, "identity 是 instance_id，不是 owner_seat")


func test_tile_clone_preserves_instance_id() -> void:
	var t := _tile(TileId.S5, 77, true, 2)
	var c: Tile = t.clone()
	assert_ne(c, t, "clone 是新对象")
	assert_eq(c.instance_id, 77)
	assert_eq(c.id, TileId.S5)
	assert_true(c.is_red_dora)
	assert_eq(c.owner_seat, 2)


func test_tile_serialize_roundtrip_preserves_instance_id() -> void:
	var t := _tile(TileId.T5, 42, true, 1)
	var d: Dictionary = t.to_dict()
	var restored: Tile = Tile.from_dict(d)
	assert_eq(restored.instance_id, 42)
	assert_eq(restored.id, TileId.T5)
	assert_true(restored.is_red_dora)
	assert_eq(restored.owner_seat, 1)


func test_rule_fixture_may_use_invalid_instance_id() -> void:
	# 纯规则 fixture 允许 INVALID_INSTANCE_ID；权威动作另测拒绝
	var t := Tile.new(TileId.W1)
	assert_eq(t.instance_id, Tile.INVALID_INSTANCE_ID)


# ---------------------------------------------------------------------------
# BattleState.hand_seq + Wall 分配：136 唯一、hand_seq 命名空间、shuffle 保留
# ---------------------------------------------------------------------------

func test_battle_state_hand_seq_defaults_to_zero() -> void:
	var s := BattleState.new()
	assert_eq(s.hand_seq, 0)


func test_wall_assigns_canonical_serial_instance_ids_before_shuffle() -> void:
	var w := Wall.new_full_set(0)
	assert_eq(w._tiles.size(), 136)
	for i in range(136):
		assert_eq(w._tiles[i].instance_id, i,
			"hand_seq=0 时 canonical serial i → instance_id=i (i=%d)" % i)


func test_wall_instance_ids_unique_and_stable_across_shuffle() -> void:
	var w := Wall.new_full_set(0)
	var before: Array = []
	for t in w._tiles:
		before.append(t.instance_id)
	before.sort()
	assert_eq(before.size(), 136)
	assert_eq(before[0], 0)
	assert_eq(before[135], 135)
	# 唯一
	for i in range(1, 136):
		assert_ne(before[i], before[i - 1], "instance_id 必须唯一")

	w.shuffle(42)
	var after: Array = []
	for t in w._tiles:
		after.append(t.instance_id)
	after.sort()
	assert_eq(after, before, "shuffle 只重排，不改写 instance_id")


func test_wall_hand_seq_namespaces_do_not_overlap() -> void:
	var w0 := Wall.new_full_set(0)
	var w1 := Wall.new_full_set(1)
	var w2 := Wall.new_full_set(2)
	var ids0: Dictionary = {}
	var ids1: Dictionary = {}
	var ids2: Dictionary = {}
	for i in range(136):
		assert_eq(w0._tiles[i].instance_id, 0 * 136 + i)
		assert_eq(w1._tiles[i].instance_id, 1 * 136 + i)
		assert_eq(w2._tiles[i].instance_id, 2 * 136 + i)
		ids0[w0._tiles[i].instance_id] = true
		ids1[w1._tiles[i].instance_id] = true
		ids2[w2._tiles[i].instance_id] = true
	for k in ids0.keys():
		assert_false(ids1.has(k), "hand_seq 0/1 不得重叠 id=%s" % str(k))
		assert_false(ids2.has(k), "hand_seq 0/2 不得重叠")
	for k in ids1.keys():
		assert_false(ids2.has(k), "hand_seq 1/2 不得重叠")


func test_for_east_round_assigns_unique_valid_instance_ids() -> void:
	var s := BattleState.for_east_round(42, 0, 1, 0, 0)
	assert_eq(s.hand_seq, 0)
	var seen: Dictionary = {}
	var count := 0
	for seat in s.seats:
		for t in seat.hand._tiles:
			assert_ne(t.instance_id, Tile.INVALID_INSTANCE_ID)
			assert_false(seen.has(t.instance_id), "发牌后 instance_id 重复 %d" % t.instance_id)
			seen[t.instance_id] = true
			count += 1
	# 剩余 live + dead 墙内未摸牌
	for t in s.wall._tiles:
		if seen.has(t.instance_id):
			continue
		assert_ne(t.instance_id, Tile.INVALID_INSTANCE_ID)
		seen[t.instance_id] = true
		count += 1
	assert_eq(count, 136, "一局正式墙牌共 136 张有效唯一 instance_id")
	assert_eq(seen.size(), 136)


func test_hand_clone_preserves_instance_ids() -> void:
	var h := Hand.new()
	h.add(_tile(TileId.W1, 5))
	h.add(_tile(TileId.W2, 6, false, 3))
	var c := h.clone()
	assert_eq(_hand_iids(c), [5, 6])
	assert_eq(c._tiles[1].owner_seat, 3)
	# 独立性
	c.take_by_instance_id(5)
	assert_eq(h.size(), 2, "clone 后 take 不影响原 hand")


# ---------------------------------------------------------------------------
# Hand：find / take / take_many 精确实体、赤黑、原子失败零修改
# ---------------------------------------------------------------------------

func test_find_and_take_by_instance_id_selects_exact_red_or_black() -> void:
	var h := Hand.new()
	# 手牌顺序：黑 5m、赤 5m、黑 5m — 与选择顺序无关
	h.add(_tile(TileId.W5, 201, false))
	h.add(_tile(TileId.W5, 202, true))
	h.add(_tile(TileId.W5, 203, false))

	var found_red: Tile = h.find_by_instance_id(202)
	assert_not_null(found_red)
	assert_true(found_red.is_red_dora)
	assert_eq(h.size(), 3, "find 不移除")

	var taken_black: Tile = h.take_by_instance_id(203)
	assert_not_null(taken_black)
	assert_false(taken_black.is_red_dora)
	assert_eq(taken_black.instance_id, 203)
	assert_eq(_hand_iids(h), [201, 202])

	var taken_red: Tile = h.take_by_instance_id(202)
	assert_not_null(taken_red)
	assert_true(taken_red.is_red_dora)
	assert_eq(_hand_iids(h), [201])


func test_take_many_order_independent_exact_entities() -> void:
	var h := Hand.new()
	h.add(_tile(TileId.W5, 10, true))
	h.add(_tile(TileId.W3, 11))
	h.add(_tile(TileId.W5, 12, false))
	# 请求顺序与手牌顺序相反：先黑 5m 再赤 5m
	var taken: Variant = h.take_many_by_instance_ids([12, 10])
	assert_not_null(taken)
	assert_eq(taken.size(), 2)
	var t0: Tile = taken[0]
	var t1: Tile = taken[1]
	assert_eq(t0.instance_id, 12)
	assert_false(t0.is_red_dora)
	assert_eq(t1.instance_id, 10)
	assert_true(t1.is_red_dora)
	assert_eq(_hand_iids(h), [11], "只移走指定实体，剩余顺序不变")


func test_take_many_empty_array_fails_zero_mod() -> void:
	var h := Hand.new()
	h.add(_tile(TileId.W1, 1))
	h.add(_tile(TileId.W2, 2))
	var snap := _hand_iids(h)
	var reds := _hand_red_flags(h)
	var result: Variant = h.take_many_by_instance_ids([])
	assert_null(result, "空数组非法 size → 失败")
	assert_eq(_hand_iids(h), snap)
	assert_eq(_hand_red_flags(h), reds)


func test_take_many_duplicate_ids_fails_zero_mod() -> void:
	var h := Hand.new()
	h.add(_tile(TileId.W1, 1))
	h.add(_tile(TileId.W1, 2))
	var snap := _hand_iids(h)
	var result: Variant = h.take_many_by_instance_ids([1, 1])
	assert_null(result, "重复 id 失败")
	assert_eq(_hand_iids(h), snap, "逐实例逐顺序零修改")


func test_take_many_missing_id_fails_zero_mod() -> void:
	var h := Hand.new()
	h.add(_tile(TileId.W1, 1))
	h.add(_tile(TileId.W2, 2))
	var snap := _hand_iids(h)
	var result: Variant = h.take_many_by_instance_ids([1, 99])
	assert_null(result)
	assert_eq(_hand_iids(h), snap, "缺失时不得先扣掉已匹配的 1")


func test_take_many_invalid_id_fails_zero_mod() -> void:
	var h := Hand.new()
	h.add(_tile(TileId.W1, 1))
	h.add(_tile(TileId.W2, 2))
	var snap := _hand_iids(h)
	var result: Variant = h.take_many_by_instance_ids([1, Tile.INVALID_INSTANCE_ID])
	assert_null(result, "INVALID_INSTANCE_ID 失败")
	assert_eq(_hand_iids(h), snap)


func test_take_by_instance_id_missing_returns_null_zero_mod() -> void:
	var h := Hand.new()
	h.add(_tile(TileId.W1, 1))
	assert_null(h.take_by_instance_id(99))
	assert_null(h.take_by_instance_id(Tile.INVALID_INSTANCE_ID))
	assert_eq(_hand_iids(h), [1])


# ---------------------------------------------------------------------------
# Seat：last_drawn_instance_id
# ---------------------------------------------------------------------------

func test_seat_last_drawn_instance_id_defaults_invalid() -> void:
	var s := Seat.new(0, TileId.E)
	assert_eq(s.last_drawn_instance_id, Tile.INVALID_INSTANCE_ID)


func test_meld_called_tile_derived_from_instance_id_in_tiles() -> void:
	var called := _tile(TileId.W3, 50)
	var a := _tile(TileId.W2, 51)
	var b := _tile(TileId.W4, 52)
	var m := Meld.make_chi([a, called, b], 0, 3, called)
	assert_eq(m.meld_id, 3)
	assert_eq(m.called_tile_instance_id, 50)
	assert_eq(m.added_tile_instance_id, Tile.INVALID_INSTANCE_ID, "非加杠无 added")
	# called_tile 从 tiles 按 instance_id 派生
	assert_not_null(m.called_tile)
	assert_eq(m.called_tile.instance_id, m.called_tile_instance_id)
	var found_in_tiles := false
	for t in m.tiles:
		if t.instance_id == m.called_tile_instance_id:
			assert_same(m.called_tile, t)
			found_in_tiles = true
	assert_true(found_in_tiles, "called_tile 必须是 tiles 内对应实体")
