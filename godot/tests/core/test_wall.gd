extends GutTest

func test_default_wall_has_136_tiles():
	var w := Wall.new_full_set()
	assert_eq(w.size(), 136)

func test_each_tile_id_appears_exactly_4_times():
	var w := Wall.new_full_set()
	var counts := {}
	for tile in w._tiles:
		counts[tile.id] = counts.get(tile.id, 0) + 1
	assert_eq(counts.size(), 34, "应有 34 种牌")
	for tid in counts:
		assert_eq(counts[tid], 4, "牌 %d 应有 4 张" % tid)

func test_red_dora_count_is_3_by_default():
	var w := Wall.new_full_set()
	var red_count := 0
	for tile in w._tiles:
		if tile.is_red_dora:
			red_count += 1
	assert_eq(red_count, 3, "默认 5m/5p/5s 各 1 张赤")

func test_shuffle_with_seed_is_deterministic():
	var w1 := Wall.new_full_set()
	var w2 := Wall.new_full_set()
	w1.shuffle(42)
	w2.shuffle(42)
	for i in range(w1.size()):
		assert_eq(w1._tiles[i].id, w2._tiles[i].id, "种子相同顺序相同 i=%d" % i)

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
