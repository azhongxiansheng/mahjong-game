extends GutTest

func test_empty_list():
	var l := YakuList.new()
	assert_eq(l.size(), 0)
	assert_eq(l.total_han(), 0)
	assert_false(l.is_yakuman())

func test_add_one_normal():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.RIICHI, 1, false, 0))
	assert_eq(l.size(), 1)
	assert_eq(l.total_han(), 1)

func test_add_two_normal_sums_han():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.RIICHI, 1, false, 0))
	l.add(YakuEntry.new(YakuId.PINFU, 1, false, 0))
	assert_eq(l.total_han(), 2)

func test_yakuman_excludes_normal():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.RIICHI, 1, false, 0))
	l.add(YakuEntry.new(YakuId.DAISANGEN, 0, true, 1))
	assert_true(l.is_yakuman())
	assert_eq(l.yakuman_total_multiplier(), 1)

func test_double_yakuman_stacks():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.DAISUUSHI, 0, true, 2))
	l.add(YakuEntry.new(YakuId.SUUANKOU_TANKI, 0, true, 2))
	assert_eq(l.yakuman_total_multiplier(), 4)
