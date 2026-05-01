extends GutTest

# FuritenChecker: 振听 = 自家弃牌河中含听牌张之一。
# 振听判定本身是纯函数；永久/暂时/立直振听的状态切换由调用方维护。

func test_no_overlap_not_furiten():
	var waits := [TileId.S5, TileId.S8]
	var pile := [TileId.W1, TileId.T2]
	assert_false(FuritenChecker.is_furiten(waits, pile))

func test_overlap_means_furiten():
	var waits := [TileId.S5, TileId.S8]
	var pile := [TileId.W1, TileId.S5, TileId.T2]
	assert_true(FuritenChecker.is_furiten(waits, pile))

func test_one_wait_in_pile():
	var waits := [TileId.S5, TileId.S8]
	var pile := [TileId.S8]
	assert_true(FuritenChecker.is_furiten(waits, pile), "听 2 张其中 1 张曾弃 → 振听")

func test_empty_waits_not_furiten():
	assert_false(FuritenChecker.is_furiten([], [TileId.S5]), "未听不存在振听")

func test_empty_pile_not_furiten():
	assert_false(FuritenChecker.is_furiten([TileId.S5], []))

func test_duplicate_in_pile_still_furiten():
	# 弃过 1 次和多次都算振听
	assert_true(FuritenChecker.is_furiten([TileId.S5], [TileId.S5, TileId.S5, TileId.S5]))

func test_dragon_wait_furiten():
	assert_true(FuritenChecker.is_furiten([TileId.HAKU], [TileId.HAKU]))
