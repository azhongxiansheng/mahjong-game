extends GutTest

# ExhaustiveDraw: 牌墙耗尽流局
# - 不听罚符共享 3000：听家共收 3000、不听家共出 3000
# - 4 家全听 / 全不听 → 0 罚符
# - 庄家听 → 连庄

# ---- noten_payout ----

func test_all_tenpai_no_payment():
	var p := ExhaustiveDraw.noten_payout([true, true, true, true])
	for seat in range(4):
		assert_eq(p[seat], 0, "seat %d 应 0" % seat)

func test_all_noten_no_payment():
	var p := ExhaustiveDraw.noten_payout([false, false, false, false])
	for seat in range(4):
		assert_eq(p[seat], 0)

func test_one_tenpai_three_noten():
	# 1 听家收 3000，3 不听家各 -1000
	var p := ExhaustiveDraw.noten_payout([true, false, false, false])
	assert_eq(p[0], 3000)
	assert_eq(p[1], -1000)
	assert_eq(p[2], -1000)
	assert_eq(p[3], -1000)

func test_two_tenpai_two_noten():
	# 每听 +1500，每不听 -1500
	var p := ExhaustiveDraw.noten_payout([true, true, false, false])
	assert_eq(p[0], 1500)
	assert_eq(p[1], 1500)
	assert_eq(p[2], -1500)
	assert_eq(p[3], -1500)

func test_three_tenpai_one_noten():
	# 每听 +1000，1 不听 -3000
	var p := ExhaustiveDraw.noten_payout([true, true, true, false])
	assert_eq(p[0], 1000)
	assert_eq(p[1], 1000)
	assert_eq(p[2], 1000)
	assert_eq(p[3], -3000)

# ---- 庄家连庄 ----

func test_dealer_tenpai_renchan():
	assert_true(ExhaustiveDraw.is_dealer_renchan(0, [true, false, false, false]))

func test_dealer_noten_no_renchan():
	assert_false(ExhaustiveDraw.is_dealer_renchan(0, [false, true, true, true]))

func test_dealer_renchan_with_seat_2():
	assert_true(ExhaustiveDraw.is_dealer_renchan(2, [false, false, true, false]))
