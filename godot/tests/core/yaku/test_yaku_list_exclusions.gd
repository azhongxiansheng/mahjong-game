extends GutTest

func test_ryanpeikou_excludes_iipeikou():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.IIPEIKOU, 1, false, 0))
	l.add(YakuEntry.new(YakuId.RYANPEIKOU, 3, false, 0))
	l.apply_exclusions()
	assert_false(l.id_list().has(YakuId.IIPEIKOU), "二杯口排除一杯口")
	assert_true(l.id_list().has(YakuId.RYANPEIKOU))

func test_chinitsu_excludes_honitsu():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.HONITSU, 3, false, 0))
	l.add(YakuEntry.new(YakuId.CHINITSU, 6, false, 0))
	l.apply_exclusions()
	assert_false(l.id_list().has(YakuId.HONITSU), "清一色排除混一色")
	assert_eq(l.total_han(), 6)

func test_junchan_excludes_honchanta():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.HONCHANTA, 2, false, 0))
	l.add(YakuEntry.new(YakuId.JUNCHAN, 3, false, 0))
	l.apply_exclusions()
	assert_false(l.id_list().has(YakuId.HONCHANTA))

func test_daisangen_excludes_yakuhai_dragons_and_shousangen():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.YAKUHAI_HAKU, 1, false, 0))
	l.add(YakuEntry.new(YakuId.YAKUHAI_HATSU, 1, false, 0))
	l.add(YakuEntry.new(YakuId.YAKUHAI_CHUN, 1, false, 0))
	l.add(YakuEntry.new(YakuId.SHOUSANGEN, 2, false, 0))
	l.add(YakuEntry.new(YakuId.DAISANGEN, 0, true, 1))
	l.apply_exclusions()
	assert_true(l.is_yakuman())
	assert_eq(l.yakuman_total_multiplier(), 1)
	assert_false(l.id_list().has(YakuId.YAKUHAI_HAKU))
	assert_false(l.id_list().has(YakuId.SHOUSANGEN))

func test_suuankou_excludes_toitoi_and_sanankou():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.TOITOI, 2, false, 0))
	l.add(YakuEntry.new(YakuId.SANANKOU, 2, false, 0))
	l.add(YakuEntry.new(YakuId.SUUANKOU, 0, true, 1))
	l.apply_exclusions()
	assert_true(l.is_yakuman())
	assert_false(l.id_list().has(YakuId.TOITOI))
	assert_false(l.id_list().has(YakuId.SANANKOU))

func test_kokushi_13_excludes_kokushi():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.KOKUSHI, 0, true, 1))
	l.add(YakuEntry.new(YakuId.KOKUSHI_13, 0, true, 2))
	l.apply_exclusions()
	assert_eq(l.yakuman_total_multiplier(), 2, "13面双倍生效，单倍被排除")

func test_no_exclusions_when_no_trigger():
	var l := YakuList.new()
	l.add(YakuEntry.new(YakuId.RIICHI, 1, false, 0))
	l.add(YakuEntry.new(YakuId.MENZEN_TSUMO, 1, false, 0))
	l.apply_exclusions()
	assert_eq(l.size(), 2, "无 trigger → 不动")
