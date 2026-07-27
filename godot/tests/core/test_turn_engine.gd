extends GutTest

# TurnEngine: 状态机 + E2-02 实体 instance_id 权威 API。
# 范围：draw_for_current / discard / advance_to_next_seat /
# declare_riichi_and_discard 与 chi/pon/kan/ron/tsumo 实体路径。

func _tile(tid: int, iid: int, red: bool = false) -> Tile:
	return Tile.new(tid, red, Tile.NO_OWNER, iid)


func _new_engine() -> TurnEngine:
	var state := BattleState.for_east_round(42, 0, 1, 0, 0)
	return TurnEngine.new(state)


func _set_hand(seat: Seat, tiles: Array) -> void:
	seat.hand = Hand.new()
	for t in tiles:
		seat.hand.add(t)


func _first_hand_iid(seat: Seat) -> int:
	return seat.hand.tiles()[0].instance_id


# ---- draw_for_current ----

func test_draw_for_current_gives_tile_and_advances_phase():
	var e := _new_engine()
	assert_eq(e.state.phase, BattlePhase.Kind.DRAW)
	assert_eq(e.state.seats[0].hand.size(), 13)
	var t := e.draw_for_current()
	assert_not_null(t)
	assert_eq(e.state.seats[0].hand.size(), 14, "摸 1 张后 14")
	assert_eq(e.state.phase, BattlePhase.Kind.DISCARD)

func test_draw_when_live_wall_empty_returns_null():
	var e := _new_engine()
	# 直接抽干 live wall（70 张）
	for _i in range(70):
		e.state.wall.draw()
	var t := e.draw_for_current()
	assert_null(t, "live wall 空时摸返 null")

# ---- discard ----

func test_discard_moves_tile_to_pile_and_advances_phase():
	var e := _new_engine()
	var t := e.draw_for_current()
	assert_eq(e.state.seats[0].hand.size(), 14)
	var ok := e.discard(t.instance_id)
	assert_true(ok)
	assert_eq(e.state.seats[0].hand.size(), 13)
	assert_eq(e.state.seats[0].river.size(), 1)
	assert_eq(e.state.seats[0].river.tiles()[0].instance_id, t.instance_id)
	assert_eq(e.state.seats[0].river.tiles()[0].id, t.id)
	assert_eq(e.state.phase, BattlePhase.Kind.CLAIM)

func test_discard_returns_false_when_not_in_hand():
	var e := _new_engine()
	e.draw_for_current()
	assert_false(e.discard(999999))
	assert_false(e.discard(Tile.INVALID_INSTANCE_ID))

# ---- advance_to_next_seat ----

func test_advance_rotates_current_seat_and_resets_phase():
	var e := _new_engine()
	e.draw_for_current()
	e.discard(_first_hand_iid(e.state.seats[0]))
	e.advance_to_next_seat()
	assert_eq(e.state.current_seat, 1)
	assert_eq(e.state.phase, BattlePhase.Kind.DRAW)

func test_advance_full_round_increments_turn_count():
	var e := _new_engine()
	# 4 家各摸 1 弃 1
	for _i in range(4):
		e.draw_for_current()
		var seat: Seat = e.state.seats[e.state.current_seat]
		e.discard(_first_hand_iid(seat))
		e.advance_to_next_seat()
	# 回到 dealer，turn_count 应 = 1（第 1 巡完成）
	assert_eq(e.state.current_seat, 0)
	assert_eq(e.state.turn_count, 1)

func test_first_round_active_cleared_after_round_2():
	var e := _new_engine()
	# 跑 2 巡（8 次 draw/discard/advance）
	for _i in range(8):
		e.draw_for_current()
		var seat: Seat = e.state.seats[e.state.current_seat]
		e.discard(_first_hand_iid(seat))
		e.advance_to_next_seat()
	assert_eq(e.state.turn_count, 2)
	assert_false(e.state.first_round_active, "第 2 巡开始后清")

# ---- declare_riichi_and_discard（原子：14 张手 + 弃牌实体）----

# 14 张：弃 W3(iid=900) 后 13 张听 W3
func _tenpai_14_with_discard_w3() -> Array:
	return [
		_tile(TileId.W2, 901), _tile(TileId.W4, 902),
		_tile(TileId.T2, 903), _tile(TileId.T3, 904), _tile(TileId.T4, 905),
		_tile(TileId.T5, 906), _tile(TileId.T6, 907), _tile(TileId.T7, 908),
		_tile(TileId.S2, 909), _tile(TileId.S3, 910), _tile(TileId.S4, 911),
		_tile(TileId.S5, 912), _tile(TileId.S5, 913),
		_tile(TileId.W3, 900),
	]

func test_declare_riichi_succeeds_when_valid():
	var e := _new_engine()
	_set_hand(e.state.seats[0], _tenpai_14_with_discard_w3())
	e.state.phase = BattlePhase.Kind.DISCARD
	e.state.seats[0].last_drawn_instance_id = 900
	var ok := e.declare_riichi_and_discard(0, 900)
	assert_true(ok)
	assert_true(e.state.seats[0].riichi.declared)
	assert_eq(e.state.seats[0].points, 24000, "扣 1000 立直棒")
	assert_eq(e.state.riichi_sticks, 1, "桌上立直棒 +1")
	assert_eq(e.state.seats[0].hand.size(), 13)
	assert_null(e.state.seats[0].hand.find_by_instance_id(900))
	assert_eq(e.state.seats[0].river.tiles()[-1].instance_id, 900)
	assert_eq(e.state.phase, BattlePhase.Kind.CLAIM)
	assert_eq(e.state.seats[0].last_drawn_instance_id, Tile.INVALID_INSTANCE_ID)

func test_declare_riichi_fails_when_invalid():
	var e := _new_engine()
	# 14 张散牌，弃任一张也不听
	var tiles: Array = []
	var ids := [
		TileId.W1, TileId.W3, TileId.W5, TileId.W7, TileId.W9,
		TileId.T1, TileId.T3, TileId.T5, TileId.T7, TileId.T9,
		TileId.S1, TileId.S3, TileId.S5, TileId.S7,
	]
	for i in range(14):
		tiles.append(_tile(ids[i], i + 1))
	_set_hand(e.state.seats[0], tiles)
	e.state.phase = BattlePhase.Kind.DISCARD
	var hand_iids: Array = []
	for t in e.state.seats[0].hand.tiles():
		hand_iids.append(t.instance_id)
	var points: int = e.state.seats[0].points
	var sticks: int = e.state.riichi_sticks
	var phase := e.state.phase
	var ok := e.declare_riichi_and_discard(0, 1)
	assert_false(ok)
	assert_false(e.state.seats[0].riichi.declared)
	assert_eq(e.state.seats[0].points, 25000, "未扣点")
	assert_eq(e.state.seats[0].points, points)
	assert_eq(e.state.riichi_sticks, sticks)
	assert_eq(e.state.seats[0].river.size(), 0)
	assert_eq(e.state.phase, phase)
	var after_iids: Array = []
	for t in e.state.seats[0].hand.tiles():
		after_iids.append(t.instance_id)
	assert_eq(after_iids, hand_iids)

# ---- apply_chi/pon/minkan ----

func _setup_after_dealer_discards(e: TurnEngine, discard_tid: int, discard_iid: int = 1000) -> Tile:
	# 让 dealer 弃 discard；返回弃出的 Tile
	var hand_tiles: Array = []
	for i in range(13):
		hand_tiles.append(_tile(TileId.W1 + (i % 9), 100 + i))
	hand_tiles.append(_tile(discard_tid, discard_iid))
	_set_hand(e.state.seats[0], hand_tiles)
	e.state.phase = BattlePhase.Kind.DISCARD
	e.discard(discard_iid)
	return e.state.seats[0].river.tiles()[-1]

func test_apply_chi_success():
	var e := _new_engine()
	# claimant=1（下家），手中有 W2 + W4 → 吃 W3
	_set_hand(e.state.seats[1], [_tile(TileId.W2, 501), _tile(TileId.W4, 502)])
	var tile := _setup_after_dealer_discards(e, TileId.W3, 500)
	var ok := e.apply_chi(1, tile.instance_id, [501, 502])
	assert_true(ok)
	assert_eq(e.state.seats[1].melds.size(), 1)
	assert_eq(e.state.seats[1].melds.all()[0].kind, Meld.Kind.CHI)
	assert_same(e.state.seats[1].melds.all()[0].called_tile, tile,
		"TurnEngine 必须把河里的真实叫牌写进 Meld")
	assert_eq(e.state.seats[1].hand.size(), 0)
	assert_eq(e.state.seats[0].river.size(), 0, "弃牌被取走")
	assert_eq(e.state.current_seat, 1)
	assert_eq(e.state.phase, BattlePhase.Kind.DISCARD)
	assert_false(e.state.first_round_active, "鸣牌打破第一巡")

func test_apply_chi_rejected_for_non_next_seat():
	var e := _new_engine()
	_set_hand(e.state.seats[2], [_tile(TileId.W2, 501), _tile(TileId.W4, 502)])
	var tile := _setup_after_dealer_discards(e, TileId.W3, 500)
	var ok := e.apply_chi(2, tile.instance_id, [501, 502])
	assert_false(ok, "对家不可吃")

func test_apply_pon_success():
	var e := _new_engine()
	_set_hand(e.state.seats[2], [_tile(TileId.W5, 601), _tile(TileId.W5, 602)])
	var tile := _setup_after_dealer_discards(e, TileId.W5, 600)
	var ok := e.apply_pon(2, tile.instance_id, [601, 602])
	assert_true(ok)
	assert_eq(e.state.seats[2].melds.all()[0].kind, Meld.Kind.PON)
	assert_same(e.state.seats[2].melds.all()[0].called_tile, tile)
	assert_eq(e.state.current_seat, 2)
	assert_eq(e.state.phase, BattlePhase.Kind.DISCARD)

func test_apply_minkan_reveals_new_dora_and_takes_rinshan():
	var e := _new_engine()
	_set_hand(e.state.seats[2], [
		_tile(TileId.W5, 701), _tile(TileId.W5, 702), _tile(TileId.W5, 703),
	])
	var initial_dora_count := e.state.dora_indicators.visible_tiles().size()
	var tile := _setup_after_dealer_discards(e, TileId.W5, 700)
	var ok := e.apply_minkan(2, tile.instance_id, [701, 702, 703])
	assert_true(ok)
	assert_eq(e.state.seats[2].melds.all()[0].kind, Meld.Kind.MINKAN)
	assert_same(e.state.seats[2].melds.all()[0].called_tile, tile)
	assert_eq(e.state.dora_indicators.visible_tiles().size(), initial_dora_count + 1, "明杠翻 dora")
	assert_eq(e.state.seats[2].hand.size(), 1, "摸岭上后 1 张")
	assert_eq(e.state.phase, BattlePhase.Kind.DISCARD)

# ---- apply_ankan / apply_added_kan ----

func test_apply_ankan_success():
	var e := _new_engine()
	# 自家回合摸了 14 张含 4 张同
	var tiles: Array = [
		_tile(TileId.W5, 801), _tile(TileId.W5, 802),
		_tile(TileId.W5, 803), _tile(TileId.W5, 804),
	]
	for i in range(10):
		tiles.append(_tile(TileId.T1 + i, 810 + i))
	_set_hand(e.state.seats[0], tiles)
	e.state.phase = BattlePhase.Kind.DISCARD
	var initial_dora_count := e.state.dora_indicators.visible_tiles().size()
	var ok := e.apply_ankan(0, [801, 802, 803, 804])
	assert_true(ok)
	assert_eq(e.state.seats[0].melds.all()[0].kind, Meld.Kind.ANKAN)
	assert_eq(e.state.seats[0].melds.all()[0].tiles.size(), 4, "暗杠 4 张")
	assert_eq(e.state.dora_indicators.visible_tiles().size(), initial_dora_count + 1)
	assert_eq(e.state.phase, BattlePhase.Kind.DISCARD)

func test_apply_added_kan_success():
	var e := _new_engine()
	# 已有 PON W5 副露 + 手中第 4 张 W5
	var called := _tile(TileId.W5, 900)
	var pon := Meld.make_pon(
		[called, _tile(TileId.W5, 901), _tile(TileId.W5, 902)], 1, 0, called)
	e.state.seats[0].melds.add_existing(pon)
	assert_true(e.state.seats[0].melds.restore(e.state.seats[0].melds.all(), 1))
	_set_hand(e.state.seats[0], [_tile(TileId.W5, 903)])
	for i in range(10):
		e.state.seats[0].hand.add(_tile(TileId.T1 + i, 910 + i))
	e.state.phase = BattlePhase.Kind.DISCARD
	var ok := e.apply_added_kan(0, 0, 903)
	assert_true(ok)
	assert_eq(e.state.seats[0].melds.all()[0].kind, Meld.Kind.ADDED_KAN)
	assert_eq(e.state.seats[0].melds.all()[0].meld_id, 0, "加杠保留 meld_id")
	assert_eq(e.state.seats[0].melds.all()[0].tiles.size(), 4, "加杠 4 张")
	assert_eq(e.state.seats[0].melds.all()[0].added_tile_instance_id, 903)

# ---- apply_ron / apply_tsumo ----
# 成功路径必须用真实标准和牌 fixture（不可依赖随机起手 / 未校验的假和）。

# 标准型 13 张听 W5 嵌张：234m 234p 234s 4-6m 55s
func _standard_tenpai_waiting_w5(start_iid: int) -> Array:
	var ids := [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W4, TileId.W6,
		TileId.S5, TileId.S5,
	]
	var tiles: Array = []
	for i in range(ids.size()):
		tiles.append(_tile(ids[i], start_iid + i))
	return tiles


func test_apply_ron_advances_to_settle():
	var e := _new_engine()
	# dealer 弃真实和牌张 W5；claimant=2 持 13 张标准听牌
	_set_hand(e.state.seats[0], [_tile(TileId.W5, 1000)])
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(1000))
	_set_hand(e.state.seats[2], _standard_tenpai_waiting_w5(2000))
	assert_true(ClaimValidator.can_ron(
		e.state.seats[2].hand, e.state.seats[2].melds.all(),
		e.state.seats[0].river.tiles()[-1], e.state.seats[2].furiten))
	var ok := e.apply_ron(2, 1000)
	assert_true(ok)
	assert_eq(e.state.phase, BattlePhase.Kind.SETTLE)

func test_apply_tsumo_advances_to_settle():
	var e := _new_engine()
	# 14 张：13 标准听 + last_drawn 和牌实体 W5
	var win_iid: int = 1500
	var tiles: Array = _standard_tenpai_waiting_w5(1400)
	tiles.append(_tile(TileId.W5, win_iid))
	_set_hand(e.state.seats[0], tiles)
	e.state.phase = BattlePhase.Kind.DISCARD
	e.state.seats[0].last_drawn_instance_id = win_iid
	var without := Hand.new()
	for t in e.state.seats[0].hand.tiles():
		if t.instance_id != win_iid:
			without.add(t)
	var drawn: Tile = e.state.seats[0].hand.find_by_instance_id(win_iid)
	assert_true(ClaimValidator.can_tsumo(without, e.state.seats[0].melds.all(), drawn))
	var ok := e.apply_tsumo(0, win_iid)
	assert_true(ok)
	assert_eq(e.state.phase, BattlePhase.Kind.SETTLE)

# ---- last_drawn_instance_id 跟踪 ----

func test_last_drawn_instance_id_initial_is_invalid():
	var e := _new_engine()
	for i in range(4):
		assert_eq(e.state.seats[i].last_drawn_instance_id, Tile.INVALID_INSTANCE_ID,
			"seat %d 初始 last_drawn_instance_id = INVALID_INSTANCE_ID" % i)

func test_draw_for_current_sets_last_drawn_instance_id():
	var e := _new_engine()
	var t := e.draw_for_current()
	assert_eq(e.state.seats[0].last_drawn_instance_id, t.instance_id,
		"摸完后 last_drawn = 摸到的实体")

func test_discard_clears_last_drawn_instance_id():
	var e := _new_engine()
	var t := e.draw_for_current()
	assert_eq(e.state.seats[0].last_drawn_instance_id, t.instance_id)
	e.discard(t.instance_id)
	assert_eq(e.state.seats[0].last_drawn_instance_id, Tile.INVALID_INSTANCE_ID,
		"弃牌后 last_drawn 清回 INVALID_INSTANCE_ID")

func test_advance_to_next_seat_does_not_touch_last_drawn():
	# advance 后 next seat 摸牌前 last_drawn 应仍 INVALID_INSTANCE_ID
	var e := _new_engine()
	var t := e.draw_for_current()
	e.discard(t.instance_id)
	e.advance_to_next_seat()
	assert_eq(e.state.seats[0].last_drawn_instance_id, Tile.INVALID_INSTANCE_ID)
	assert_eq(e.state.seats[1].last_drawn_instance_id, Tile.INVALID_INSTANCE_ID)

func test_apply_chi_clears_claimant_last_drawn():
	var e := _new_engine()
	e.state.current_seat = 0
	_set_hand(e.state.seats[1], [_tile(TileId.W2, 501), _tile(TileId.W4, 502)])
	e.state.seats[1].last_drawn_instance_id = 999
	_set_hand(e.state.seats[0], [_tile(TileId.W3, 500)])
	e.state.phase = BattlePhase.Kind.DISCARD
	e.discard(500)
	var ok := e.apply_chi(1, 500, [501, 502])
	assert_true(ok)
	assert_eq(e.state.seats[1].last_drawn_instance_id, Tile.INVALID_INSTANCE_ID,
		"chi 后 claimant last_drawn 清 INVALID_INSTANCE_ID")

func test_apply_pon_clears_claimant_last_drawn():
	var e := _new_engine()
	e.state.current_seat = 0
	_set_hand(e.state.seats[2], [_tile(TileId.W5, 601), _tile(TileId.W5, 602)])
	e.state.seats[2].last_drawn_instance_id = 999
	_set_hand(e.state.seats[0], [_tile(TileId.W5, 600)])
	e.state.phase = BattlePhase.Kind.DISCARD
	e.discard(600)
	var ok := e.apply_pon(2, 600, [601, 602])
	assert_true(ok)
	assert_eq(e.state.seats[2].last_drawn_instance_id, Tile.INVALID_INSTANCE_ID,
		"pon 后 claimant last_drawn 清 INVALID_INSTANCE_ID")

func test_apply_minkan_sets_last_drawn_to_rinshan():
	var e := _new_engine()
	e.state.current_seat = 0
	_set_hand(e.state.seats[2], [
		_tile(TileId.W5, 701), _tile(TileId.W5, 702), _tile(TileId.W5, 703),
	])
	_set_hand(e.state.seats[0], [_tile(TileId.W5, 700)])
	e.state.phase = BattlePhase.Kind.DISCARD
	e.discard(700)
	var ok := e.apply_minkan(2, 700, [701, 702, 703])
	assert_true(ok)
	assert_ne(e.state.seats[2].last_drawn_instance_id, Tile.INVALID_INSTANCE_ID,
		"minkan 后 last_drawn = rinshan 实体")

func test_apply_ankan_sets_last_drawn_to_rinshan():
	var e := _new_engine()
	e.state.current_seat = 0
	_set_hand(e.state.seats[0], [
		_tile(TileId.W5, 801), _tile(TileId.W5, 802),
		_tile(TileId.W5, 803), _tile(TileId.W5, 804),
	])
	e.state.phase = BattlePhase.Kind.DISCARD
	e.state.seats[0].last_drawn_instance_id = 804
	var ok := e.apply_ankan(0, [801, 802, 803, 804])
	assert_true(ok)
	assert_ne(e.state.seats[0].last_drawn_instance_id, Tile.INVALID_INSTANCE_ID,
		"ankan 后 last_drawn = rinshan 实体")
