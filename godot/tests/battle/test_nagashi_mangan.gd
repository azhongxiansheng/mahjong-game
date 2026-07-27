extends GutTest

# 日麻 §6.5 流し満貫(nagashi mangan)接入:流局时若某座所有弃牌都是幺九
# (terminals/honors)且无人鸣过其弃牌 → 按满贯计算(自摸式支付)。
# v1 简化:多家同时满足时返第一个匹配 seat。


# Helper:把指定 tile_id 列表塞到 seat 弃牌堆
func _set_discards(state: BattleState, seat: int, tile_ids: Array) -> void:
	state.seats[seat].river.restore([])
	for tid in tile_ids:
		state.seats[seat].river.append_discard(Tile.new(tid))


# Helper:构造 GameDriver,seat 0 是 dealer
func _make_driver_with_battle(dealer_seat: int = 0) -> GameDriver:
	var driver := GameDriver.new(42, 4, 4)
	driver.dealer_seat = dealer_seat
	var bc := BattleController.new(42, dealer_seat, false, TileId.E)
	driver.battle = bc
	# 拍照初始 state.scores(供 _apply_in_hand_skill_deltas)
	for i in range(4):
		driver._pre_hand_state_scores[i] = bc.state.scores[i]
	return driver


# ---- detection ----

func test_nagashi_seat_detected_when_all_yaochu_and_uncalled() -> void:
	var driver := _make_driver_with_battle()
	# seat 0 弃 9 张全幺九
	_set_discards(driver.battle.state, 0, [
		TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.HAKU
	])
	var s: int = NagashiMangan.detect_winner_seat(driver.battle.state)
	assert_eq(s, 0, "seat 0 全幺九 + 无人鸣 → 应命中")


func test_nagashi_seat_not_detected_when_has_non_yaochu() -> void:
	var driver := _make_driver_with_battle()
	# seat 0 弃 8 张幺九 + 1 张数中 W5
	_set_discards(driver.battle.state, 0, [
		TileId.W1, TileId.W9, TileId.T1, TileId.T9, TileId.S1, TileId.S9,
		TileId.E, TileId.W5
	])
	var s: int = NagashiMangan.detect_winner_seat(driver.battle.state)
	assert_eq(s, -1, "含 W5 数中 → 不命中")


func test_nagashi_seat_not_detected_when_called() -> void:
	var driver := _make_driver_with_battle()
	_set_discards(driver.battle.state, 0, [TileId.W1, TileId.W9])
	# seat 1 melds 中有一个 from_seat=0(模拟 seat 1 鸣了 seat 0 的弃牌)
	var meld := Meld.make_pon(
		[Tile.new(TileId.T5), Tile.new(TileId.T5), Tile.new(TileId.T5)], 0)
	driver.battle.state.seats[1].melds.add_existing(meld)
	var s: int = NagashiMangan.detect_winner_seat(driver.battle.state)
	assert_eq(s, -1, "被鸣过 → 不命中")


func test_nagashi_seat_returns_neg1_when_empty_discards() -> void:
	var driver := _make_driver_with_battle()
	# 4 家 discards 都空
	var s: int = NagashiMangan.detect_winner_seat(driver.battle.state)
	assert_eq(s, -1, "无任何弃牌 → 不命中")


# ---- payout ----

func test_payout_dealer_nagashi() -> void:
	var driver := _make_driver_with_battle(0)
	var deltas: Dictionary = NagashiMangan.payout(0, driver.dealer_seat)
	# 庄家流し:每家 -4000,庄 +12000
	assert_eq(int(deltas[0]), 12000, "dealer +12000")
	assert_eq(int(deltas[1]), -4000, "seat 1 -4000")
	assert_eq(int(deltas[2]), -4000, "seat 2 -4000")
	assert_eq(int(deltas[3]), -4000, "seat 3 -4000")
	# 守恒
	var total: int = int(deltas[0]) + int(deltas[1]) + int(deltas[2]) + int(deltas[3])
	assert_eq(total, 0, "支付守恒")


func test_payout_non_dealer_nagashi() -> void:
	var driver := _make_driver_with_battle(0)  # dealer = 0
	# winner_seat = 2(闲家)
	var deltas: Dictionary = NagashiMangan.payout(2, driver.dealer_seat)
	# 闲家流し:dealer -4000, 其它闲 -2000,自 +8000
	assert_eq(int(deltas[0]), -4000, "dealer -4000")
	assert_eq(int(deltas[1]), -2000, "seat 1 -2000")
	assert_eq(int(deltas[2]), 8000, "winner +8000")
	assert_eq(int(deltas[3]), -2000, "seat 3 -2000")
	var total: int = int(deltas[0]) + int(deltas[1]) + int(deltas[2]) + int(deltas[3])
	assert_eq(total, 0, "支付守恒")


# ---- apply_result + advance_or_finish 集成 ----

func test_apply_result_returns_nagashi_kind() -> void:
	var driver := _make_driver_with_battle()
	# seat 0 全幺九弃,其它座位空 → seat 0 命中
	_set_discards(driver.battle.state, 0, [TileId.W1, TileId.W9, TileId.T1])
	# 喂个空 events 列表让 apply_result 走"无 WIN_DECLARED"分支
	var result: Dictionary = driver.apply_result([])
	assert_eq(String(result.get("kind", "")), "nagashi_mangan", "kind=nagashi_mangan")
	assert_eq(int(result.get("winner_seat", -1)), 0, "winner=seat 0")


func test_advance_dealer_nagashi_keeps_dealer() -> void:
	var driver := _make_driver_with_battle(0)
	var advance: Dictionary = driver.advance_or_finish({
		"kind": "nagashi_mangan",
		"winner_seat": 0,
		"payout": {0: 12000, 1: -4000, 2: -4000, 3: -4000}
	})
	assert_true(advance.get("renchan"), "dealer 流し应连庄")
	assert_eq(driver.dealer_seat, 0, "dealer 不变")


func test_advance_non_dealer_nagashi_rotates_dealer() -> void:
	var driver := _make_driver_with_battle(0)
	var advance: Dictionary = driver.advance_or_finish({
		"kind": "nagashi_mangan",
		"winner_seat": 2,
		"payout": {0: -4000, 1: -2000, 2: 8000, 3: -2000}
	})
	assert_false(advance.get("renchan"), "非 dealer 流し应流转")
	assert_eq(driver.dealer_seat, 1, "dealer 顺转 → seat 1")
