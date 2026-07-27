extends GutTest
## E2-02: hand_seq 命名空间 — BattleController 第5参 + GameDriver 递增计数


class ProbeController extends IAuthoritativeBattleController:
	func _init(seed, dealer, round_wind, hand_seq, with_state: bool = true) -> void:
		if with_state:
			state = BattleState.for_east_round(seed, dealer, 1, 0, 0, round_wind, hand_seq)
			if state != null:
				engine = TurnEngine.new(state)
				ai = SimpleAi.new(seed + 1)


class FactoryProbe extends RefCounted:
	var mode: String = "ok"
	var calls: Array = []

	func build(seed: int, dealer: int, use_heuristic: bool, round_wind: int, hand_seq: int) -> IBattleController:
		calls.append([seed, dealer, use_heuristic, round_wind, hand_seq].duplicate(true))
		if mode == "null":
			return null
		if mode == "state_null":
			return ProbeController.new(seed, dealer, round_wind, hand_seq, false)
		return ProbeController.new(seed, dealer, round_wind, hand_seq, true)


## 动态构造 BattleController，避免第5参在产品仍为4参时的静态 Parse Error。
## 缺参/调用失败时返回 null，由断言在运行时 Red，而非脚本无法收集。
## script 声明为 Variant，用动态 new(5参) 绕过编译器对 BattleController 4参签名的静态检查。
func _new_battle_controller(args: Array):
	var script: Variant = load("res://battle/battle_controller.gd")
	if script == null:
		return null
	return script.new(args[0], args[1], args[2], args[3], args[4])


func _wall_tile_order(bc) -> Array:
	var order: Array = []
	for t in bc.state.wall.authority_tiles():
		order.append([t.id, t.is_red_dora])
	return order


func _wall_instance_ids(bc) -> Array:
	var ids: Array = []
	for t in bc.state.wall.authority_tiles():
		ids.append(t.instance_id)
	return ids


func test_battle_controller_default_hand_seq_is_zero() -> void:
	var bc = BattleController.new(42, 0, false, TileId.E)
	assert_not_null(bc)
	assert_not_null(bc.state)
	assert_eq(bc.state.hand_seq, 0)


func test_battle_controller_fifth_param_hand_seq_exact() -> void:
	var bc1 = _new_battle_controller([42, 0, false, TileId.E, 1])
	assert_not_null(bc1)
	if bc1 != null:
		assert_not_null(bc1.state)
		assert_eq(bc1.state.hand_seq, 1)

	var bc_max = _new_battle_controller([42, 0, false, TileId.E, Wall.MAX_HAND_SEQ])
	assert_not_null(bc_max)
	if bc_max != null:
		assert_not_null(bc_max.state)
		assert_eq(bc_max.state.hand_seq, Wall.MAX_HAND_SEQ)


func test_battle_controller_hand_seq_out_of_range_nulls_state_and_engine() -> void:
	var bc_neg = _new_battle_controller([42, 0, false, TileId.E, -1])
	assert_not_null(bc_neg)
	if bc_neg != null:
		assert_null(bc_neg.state)
		assert_null(bc_neg.engine)

	var bc_over = _new_battle_controller([42, 0, false, TileId.E, Wall.MAX_HAND_SEQ + 1])
	assert_not_null(bc_over)
	if bc_over != null:
		assert_null(bc_over.state)
		assert_null(bc_over.engine)


func test_game_driver_next_hand_seq_starts_at_zero() -> void:
	var driver = GameDriver.new(100)
	assert_eq(driver.next_hand_seq, 0)


func test_game_driver_start_hand_twice_same_hand_index_increments_hand_seq() -> void:
	var driver = GameDriver.new(100)
	assert_eq(driver.hand_index, 0)

	var bc0 = driver.start_hand()
	assert_not_null(bc0)
	if bc0 != null:
		assert_not_null(bc0.state)
		assert_eq(bc0.state.hand_seq, 0)
	assert_eq(driver.next_hand_seq, 1)
	assert_eq(driver.hand_index, 0)

	var order0: Array = []
	var ids0: Array = []
	if bc0 != null:
		order0 = _wall_tile_order(bc0)
		ids0 = _wall_instance_ids(bc0)

	var adv = driver.advance_or_finish({"kind": "abortive_draw"})
	assert_true(adv.renchan)
	assert_null(driver.battle)
	assert_eq(driver.hand_index, 0)

	var bc1 = driver.start_hand()
	assert_not_null(bc1)
	if bc1 != null:
		assert_not_null(bc1.state)
		assert_eq(bc1.state.hand_seq, 1)
	assert_eq(driver.next_hand_seq, 2)
	assert_eq(driver.hand_index, 0)

	var order1: Array = []
	var ids1: Array = []
	if bc1 != null:
		order1 = _wall_tile_order(bc1)
		ids1 = _wall_instance_ids(bc1)

	if bc0 != null and bc1 != null:
		assert_ne(order0, order1, "同 hand_index 连续两局 wall tile order 应不同")
		assert_ne(ids0, ids1, "同 hand_index 连续两局 wall instance_id 应不同")


func test_game_driver_same_seed_reproduces_hand_seq_tile_orders() -> void:
	var d_a = GameDriver.new(8123)
	var a0 = d_a.start_hand()
	assert_not_null(a0)
	var adv_a = d_a.advance_or_finish({"kind": "abortive_draw"})
	assert_true(adv_a.renchan)
	assert_eq(d_a.hand_index, 0)
	var a1 = d_a.start_hand()
	assert_not_null(a1)
	var order_a0: Array = []
	var order_a1: Array = []
	if a0 != null:
		order_a0 = _wall_tile_order(a0)
	if a1 != null:
		order_a1 = _wall_tile_order(a1)

	var d_b = GameDriver.new(8123)
	var b0 = d_b.start_hand()
	assert_not_null(b0)
	var adv_b = d_b.advance_or_finish({"kind": "abortive_draw"})
	assert_true(adv_b.renchan)
	assert_eq(d_b.hand_index, 0)
	var b1 = d_b.start_hand()
	assert_not_null(b1)
	var order_b0: Array = []
	var order_b1: Array = []
	if b0 != null:
		order_b0 = _wall_tile_order(b0)
	if b1 != null:
		order_b1 = _wall_tile_order(b1)

	if a0 != null and b0 != null:
		assert_eq(order_a0, order_b0, "相同 seed 第1局 tile order 应相等")
	if a1 != null and b1 != null:
		assert_eq(order_a1, order_b1, "相同 seed 第2局 tile order 应相等")
	if a0 != null and a1 != null:
		assert_ne(order_a0, order_a1, "同 driver 第1局与第2局 tile order 应不同")


func test_game_driver_half_game_hand_index_four_south_wind_hand_seq_zero() -> void:
	# total_hands=8, hands_per_round=4 → hand_index=4 进入半庄南场
	var driver = GameDriver.new(200, 8, 4)
	driver.hand_index = 4
	assert_eq(driver.hand_index, 4)
	assert_eq(driver.next_hand_seq, 0)

	var bc = driver.start_hand()
	assert_not_null(bc)
	if bc != null:
		assert_not_null(bc.state)
		assert_eq(bc.state.round_wind, TileId.S_WIND)
		assert_eq(bc.state.hand_seq, 0)


func test_factory_success() -> void:
	var driver = GameDriver.new(500)
	var probe := FactoryProbe.new()
	driver.bc_factory = probe.build
	var bc = driver.start_hand()
	assert_not_null(bc)
	assert_eq(probe.calls.size(), 1)
	assert_eq(probe.calls[0], [500, 0, false, TileId.E, 0])
	if bc != null:
		assert_not_null(bc.state)
		assert_eq(bc.state.hand_seq, 0)
	assert_eq(driver.next_hand_seq, 1)


func test_factory_null_and_state_null() -> void:
	for mode in ["null", "state_null"]:
		var driver = GameDriver.new(500)
		var probe := FactoryProbe.new()
		probe.mode = mode
		driver.bc_factory = probe.build
		var bc = driver.start_hand()
		assert_null(bc)
		assert_null(driver.battle)
		assert_eq(driver.next_hand_seq, 0)
		assert_eq(probe.calls.size(), 1)


func test_active_battle_reentry() -> void:
	var driver = GameDriver.new(500)
	var probe := FactoryProbe.new()
	driver.bc_factory = probe.build
	var first = driver.start_hand()
	assert_not_null(first)
	var second = driver.start_hand()
	assert_null(second)
	assert_true(driver.battle == first or is_same(driver.battle, first))
	assert_eq(probe.calls.size(), 1)
	assert_eq(driver.next_hand_seq, 1)


func test_hand_seq_max_then_overflow_rejected_without_factory_call() -> void:
	var driver = GameDriver.new(700)
	var probe := FactoryProbe.new()
	driver.bc_factory = probe.build
	driver.next_hand_seq = Wall.MAX_HAND_SEQ

	var bc = driver.start_hand()
	assert_not_null(bc)
	assert_eq(probe.calls.size(), 1)
	assert_eq(probe.calls[0][4], Wall.MAX_HAND_SEQ)
	if bc != null:
		assert_not_null(bc.state)
		assert_eq(bc.state.hand_seq, Wall.MAX_HAND_SEQ)
	assert_eq(driver.next_hand_seq, Wall.MAX_HAND_SEQ + 1)

	var hand_index_before: int = driver.hand_index
	driver.advance_or_finish({"kind": "abortive_draw"})
	assert_null(driver.battle)
	assert_eq(driver.hand_index, hand_index_before)

	var bc2 = driver.start_hand()
	assert_null(bc2)
	assert_eq(probe.calls.size(), 1)
	assert_eq(driver.next_hand_seq, Wall.MAX_HAND_SEQ + 1)
	assert_null(driver.battle)
