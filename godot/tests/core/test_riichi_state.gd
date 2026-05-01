extends GutTest

# RiichiState (spec §5)：一座位的立直状态对象。
# 状态机迁移由调用方驱动，本对象只提供数据 + 简单 helper。

func test_default_not_declared():
	var r := RiichiState.new()
	assert_false(r.declared)
	assert_false(r.double_riichi)
	assert_false(r.ippatsu_window)
	assert_false(r.riichi_stick_paid)

func test_declare_sets_flags_and_opens_ippatsu():
	var r := RiichiState.new()
	r.declare(5, false)
	assert_true(r.declared)
	assert_eq(r.declared_turn, 5)
	assert_false(r.double_riichi)
	assert_true(r.ippatsu_window)

func test_declare_double_riichi():
	var r := RiichiState.new()
	r.declare(1, true)
	assert_true(r.declared)
	assert_true(r.double_riichi)
	assert_true(r.ippatsu_window)

func test_consume_ippatsu_closes_window():
	var r := RiichiState.new()
	r.declare(3, false)
	assert_true(r.ippatsu_window)
	r.consume_ippatsu()
	assert_false(r.ippatsu_window)
	assert_true(r.declared, "consume_ippatsu 不影响立直本身")

func test_pay_stick_marks_paid():
	var r := RiichiState.new()
	r.declare(3, false)
	r.pay_stick()
	assert_true(r.riichi_stick_paid)

func test_consume_ippatsu_when_not_in_window_is_safe():
	var r := RiichiState.new()
	r.consume_ippatsu()  # 没立直也不该崩
	assert_false(r.ippatsu_window)
