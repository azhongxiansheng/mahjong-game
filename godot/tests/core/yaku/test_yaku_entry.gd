extends GutTest

func test_construct_normal_yaku():
	var e := YakuEntry.new(YakuId.RIICHI, 1, false, 0)
	assert_eq(e.yaku_id, YakuId.RIICHI)
	assert_eq(e.han, 1)
	assert_false(e.is_yakuman)

func test_construct_yakuman():
	var e := YakuEntry.new(YakuId.DAISANGEN, 0, true, 1)
	assert_true(e.is_yakuman)
	assert_eq(e.yakuman_multiplier, 1)

func test_construct_double_yakuman():
	var e := YakuEntry.new(YakuId.DAISUUSHI, 0, true, 2)
	assert_eq(e.yakuman_multiplier, 2)

func test_name_zh_lookup():
	var e := YakuEntry.new(YakuId.PINFU, 1, false, 0)
	assert_eq(e.name_zh(), "平和")
