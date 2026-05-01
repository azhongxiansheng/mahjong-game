extends GutTest

# YakuList: 0c 与 0b 共享的役清单数据契约
# - yaku: Array[Dictionary] each {id: StringName, han: int}
# - dora_count: 含 Dora + 裏 Dora + 赤 Dora 累计
# - is_yakuman + yakuman_multiplier: 役满倍数（受 spec §14 上限 2 钳制由 ScoreFormula 处理）

func test_empty_factory():
	var y := YakuList.empty()
	assert_eq(y.yaku.size(), 0)
	assert_eq(y.dora_count, 0)
	assert_false(y.is_yakuman)
	assert_eq(y.yakuman_multiplier, 0)
	assert_eq(y.total_han(), 0)

func test_add_yaku_and_total_han():
	var y := YakuList.empty()
	y.add_yaku(&"riichi", 1)
	y.add_yaku(&"pinfu", 1)
	y.add_yaku(&"tanyao", 1)
	assert_eq(y.yaku.size(), 3)
	assert_eq(y.total_han(), 3, "无 dora 时 total_han = 役番和")

func test_total_han_includes_dora():
	var y := YakuList.empty()
	y.add_yaku(&"riichi", 1)
	y.dora_count = 2
	assert_eq(y.total_han(), 3, "Dora 计入 total_han")

func test_is_pinfu_lookup():
	var y := YakuList.empty()
	y.add_yaku(&"pinfu", 1)
	assert_true(y.is_pinfu())
	var y2 := YakuList.empty()
	y2.add_yaku(&"riichi", 1)
	assert_false(y2.is_pinfu())

func test_is_chiitoi_lookup():
	var y := YakuList.empty()
	y.add_yaku(&"chiitoitsu", 2)
	assert_true(y.is_chiitoi())
	var y2 := YakuList.empty()
	y2.add_yaku(&"riichi", 1)
	assert_false(y2.is_chiitoi())

func test_yakuman_state():
	var y := YakuList.empty()
	y.is_yakuman = true
	y.yakuman_multiplier = 1
	y.add_yaku(&"daisangen", 13)
	assert_true(y.is_yakuman)
	assert_eq(y.yakuman_multiplier, 1)

func test_double_yakuman_multiplier():
	var y := YakuList.empty()
	y.is_yakuman = true
	y.yakuman_multiplier = 2
	y.add_yaku(&"kokushi_thirteen_wait", 13)
	assert_eq(y.yakuman_multiplier, 2)

func test_has_yaku_predicate():
	var y := YakuList.empty()
	y.add_yaku(&"riichi", 1)
	assert_true(y.has_yaku(&"riichi"))
	assert_false(y.has_yaku(&"pinfu"))
