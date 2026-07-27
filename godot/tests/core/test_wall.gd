extends GutTest

func test_default_wall_has_136_tiles():
	var w := Wall.new_full_set()
	assert_eq(w.size(), 136)

func test_each_tile_id_appears_exactly_4_times():
	var w := Wall.new_full_set()
	var counts := {}
	for tile in w.authority_tiles():
		counts[tile.id] = counts.get(tile.id, 0) + 1
	assert_eq(counts.size(), 34, "应有 34 种牌")
	for tid in counts:
		assert_eq(counts[tid], 4, "牌 %d 应有 4 张" % tid)

func test_red_dora_count_is_3_by_default():
	var w := Wall.new_full_set()
	var red_count := 0
	for tile in w.authority_tiles():
		if tile.is_red_dora:
			red_count += 1
	assert_eq(red_count, 3, "默认 5m/5p/5s 各 1 张赤")

func test_shuffle_with_seed_is_deterministic():
	var w1 := Wall.new_full_set()
	var w2 := Wall.new_full_set()
	w1.shuffle(42)
	w2.shuffle(42)
	for i in range(w1.size()):
		assert_eq(w1.authority_tiles()[i].id, w2.authority_tiles()[i].id, "种子相同顺序相同 i=%d" % i)

func test_draw_returns_top_and_decrements():
	var w := Wall.new_full_set()
	w.shuffle(1)
	var initial := w.size()
	var t := w.draw()
	assert_not_null(t)
	assert_eq(w.size(), initial - 1)

func test_draw_when_empty_returns_null():
	var w := Wall.new_full_set()
	for _i in range(136):
		w.draw()
	assert_eq(w.size(), 0)
	assert_null(w.draw())

func test_remaining_count_alias():
	var w := Wall.new_full_set()
	assert_eq(w.remaining(), w.size())
	w.shuffle(0)
	w.draw()
	assert_eq(w.remaining(), 135)

# ---- M3 收尾：owner_seat 分配 ----

func test_each_owner_owns_34_tiles():
	# v1 卡组合并占位：4 家各 34 张完整集合
	var w := Wall.new_full_set()
	var owner_counts := {0: 0, 1: 0, 2: 0, 3: 0}
	for t in w.authority_tiles():
		owner_counts[t.owner_seat] = owner_counts.get(t.owner_seat, 0) + 1
	assert_eq(owner_counts[0], 34, "seat 0 拥有 34 张")
	assert_eq(owner_counts[1], 34)
	assert_eq(owner_counts[2], 34)
	assert_eq(owner_counts[3], 34)

func test_each_owner_has_exactly_one_of_every_tile_id():
	# 每家应拥有所有 34 种 TileId 各 1 张
	var w := Wall.new_full_set()
	var per_owner_id_counts := {0: {}, 1: {}, 2: {}, 3: {}}
	for t in w.authority_tiles():
		var d: Dictionary = per_owner_id_counts[t.owner_seat]
		d[t.id] = d.get(t.id, 0) + 1
	for owner in [0, 1, 2, 3]:
		var d: Dictionary = per_owner_id_counts[owner]
		assert_eq(d.size(), 34, "seat %d 应有 34 种" % owner)
		for tid in d:
			assert_eq(d[tid], 1, "seat %d tile %d 应只有 1 张" % [owner, tid])

func test_shuffle_preserves_owner_seat():
	# 洗牌只重排 _tiles 顺序，不改 Tile.owner_seat 内容
	var w := Wall.new_full_set()
	var owners_before := []
	for t in w.authority_tiles():
		owners_before.append(t.owner_seat)
	w.shuffle(42)
	var owners_after := []
	for t in w.authority_tiles():
		owners_after.append(t.owner_seat)
	# 排序后两数组应相等（多重集相同）
	owners_before.sort()
	owners_after.sort()
	assert_eq(owners_before, owners_after)
