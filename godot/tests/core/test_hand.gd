extends GutTest

func _make_hand_from_ids(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

func test_empty_hand_size_is_zero():
	var h := Hand.new()
	assert_eq(h.size(), 0)

func test_add_increases_size():
	var h := Hand.new()
	h.add(Tile.new(TileId.W1))
	assert_eq(h.size(), 1)

func test_remove_by_id_returns_true_and_decreases():
	var h := _make_hand_from_ids([TileId.W1, TileId.W2, TileId.W3])
	assert_true(h.remove_by_id(TileId.W2))
	assert_eq(h.size(), 2)

func test_remove_by_id_when_absent_returns_false():
	var h := _make_hand_from_ids([TileId.W1])
	assert_false(h.remove_by_id(TileId.S5))
	assert_eq(h.size(), 1)

func test_to_id_array_returns_sorted_ascending():
	var h := _make_hand_from_ids([TileId.S5, TileId.W1, TileId.E, TileId.W1])
	var ids := h.to_id_array()
	assert_eq(ids, [TileId.W1, TileId.W1, TileId.S5, TileId.E])

func test_count_of_id():
	var h := _make_hand_from_ids([TileId.W1, TileId.W1, TileId.W1, TileId.W2])
	assert_eq(h.count_of(TileId.W1), 3)
	assert_eq(h.count_of(TileId.W2), 1)
	assert_eq(h.count_of(TileId.W9), 0)

func test_id_count_dict_returns_map():
	var h := _make_hand_from_ids([TileId.W1, TileId.W1, TileId.W2])
	var d := h.id_count_dict()
	assert_eq(d.get(TileId.W1), 2)
	assert_eq(d.get(TileId.W2), 1)
	assert_false(d.has(TileId.W3))

func test_clone_independent():
	var h := _make_hand_from_ids([TileId.W1])
	var c := h.clone()
	c.add(Tile.new(TileId.W2))
	assert_eq(h.size(), 1)
	assert_eq(c.size(), 2)

# ---- M3 收尾：owner_seat 跟踪 ----

func test_clone_preserves_owner_seat():
	var h := Hand.new()
	h.add(Tile.new(TileId.W1, false, 0))
	h.add(Tile.new(TileId.W2, false, 2))
	h.add(Tile.new(TileId.S5, true, 1))
	var c := h.clone()
	assert_eq(c.size(), 3)
	# 内部顺序保留
	assert_eq(c._tiles[0].owner_seat, 0)
	assert_eq(c._tiles[1].owner_seat, 2)
	assert_eq(c._tiles[2].owner_seat, 1)
	# 赤 dora 也保留
	assert_true(c._tiles[2].is_red_dora)

func test_to_owner_array_in_internal_order():
	var h := Hand.new()
	h.add(Tile.new(TileId.W1, false, 3))
	h.add(Tile.new(TileId.E, false, 0))
	h.add(Tile.new(TileId.S_WIND, false, 2))
	var owners := h.to_owner_array()
	# 不排序，按 _tiles 顺序
	assert_eq(owners, [3, 0, 2])

func test_to_owner_array_default_no_owner():
	# 用 Tile.new(id) 默认无主
	var h := Hand.new()
	h.add(Tile.new(TileId.W1))
	h.add(Tile.new(TileId.W2))
	var owners := h.to_owner_array()
	assert_eq(owners, [Tile.NO_OWNER, Tile.NO_OWNER])

func test_to_owner_array_empty_hand():
	var h := Hand.new()
	assert_eq(h.to_owner_array(), [])
