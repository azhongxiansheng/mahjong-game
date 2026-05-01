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
