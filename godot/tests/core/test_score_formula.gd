extends GutTest

# ScoreFormula：基本点 = fu × 2^(2+han)，钳到满贯档与役满。
# spec §14: 役满倍数上限 = 2 倍役满。
# 不实施"切上満貫"（30符4番 = 1920，按 1920 算，与天凤一致）。

func test_basic_30fu_1han():
	assert_eq(ScoreFormula.base_points(30, 1, 0), 240)

func test_basic_40fu_1han():
	assert_eq(ScoreFormula.base_points(40, 1, 0), 320)

func test_basic_30fu_2han():
	assert_eq(ScoreFormula.base_points(30, 2, 0), 480)

func test_basic_50fu_3han():
	assert_eq(ScoreFormula.base_points(50, 3, 0), 1600)

func test_30fu_4han_under_2000():
	# 30 × 64 = 1920 < 2000，不切上
	assert_eq(ScoreFormula.base_points(30, 4, 0), 1920)

func test_40fu_4han_clamps_to_mangan():
	# 40 × 64 = 2560 > 2000 → 钳到满贯 2000
	assert_eq(ScoreFormula.base_points(40, 4, 0), 2000)

func test_70fu_3han_clamps_to_mangan():
	# 70 × 32 = 2240 > 2000 → 钳到满贯
	assert_eq(ScoreFormula.base_points(70, 3, 0), 2000)

func test_5han_is_mangan():
	assert_eq(ScoreFormula.base_points(20, 5, 0), 2000)

func test_6han_is_haneman():
	assert_eq(ScoreFormula.base_points(20, 6, 0), 3000)

func test_7han_is_haneman():
	assert_eq(ScoreFormula.base_points(20, 7, 0), 3000)

func test_8han_is_baiman():
	assert_eq(ScoreFormula.base_points(20, 8, 0), 4000)

func test_10han_is_baiman():
	assert_eq(ScoreFormula.base_points(20, 10, 0), 4000)

func test_11han_is_sanbaiman():
	assert_eq(ScoreFormula.base_points(20, 11, 0), 6000)

func test_12han_is_sanbaiman():
	assert_eq(ScoreFormula.base_points(20, 12, 0), 6000)

func test_13han_is_kazoe_yakuman():
	assert_eq(ScoreFormula.base_points(20, 13, 0), 8000)

func test_25han_still_kazoe_yakuman():
	# 累计役满不再翻倍
	assert_eq(ScoreFormula.base_points(20, 25, 0), 8000)

func test_single_yakuman():
	assert_eq(ScoreFormula.base_points(0, 0, 1), 8000)

func test_double_yakuman():
	assert_eq(ScoreFormula.base_points(0, 0, 2), 16000)

func test_yakuman_clamped_to_2():
	# spec §14：上限 2 倍役满
	assert_eq(ScoreFormula.base_points(0, 0, 3), 16000)
	assert_eq(ScoreFormula.base_points(0, 0, 5), 16000)

func test_yakuman_overrides_han():
	# 役满旗位优先于 han（即使 han 很大）
	assert_eq(ScoreFormula.base_points(20, 13, 1), 8000)
