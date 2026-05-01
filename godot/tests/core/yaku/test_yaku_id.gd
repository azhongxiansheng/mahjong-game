extends GutTest

func test_id_count_is_40():
	assert_eq(YakuId.ALL.size(), 40, "覆盖 40 个基础役（不含变体）")

func test_riichi_metadata():
	var meta := YakuId.metadata(YakuId.RIICHI)
	assert_eq(meta.name_zh, "立直")
	assert_eq(meta.base_han_closed, 1)
	assert_eq(meta.base_han_open, 0)
	assert_false(meta.is_yakuman)

func test_chinitsu_open_minus_one():
	var meta := YakuId.metadata(YakuId.CHINITSU)
	assert_eq(meta.base_han_closed, 6)
	assert_eq(meta.base_han_open, 5)

func test_kokushi_is_yakuman():
	var meta := YakuId.metadata(YakuId.KOKUSHI)
	assert_true(meta.is_yakuman)
	assert_eq(meta.yakuman_multiplier, 1)

func test_daisuushi_double_yakuman():
	var meta := YakuId.metadata(YakuId.DAISUUSHI)
	assert_true(meta.is_yakuman)
	assert_eq(meta.yakuman_multiplier, 2)
