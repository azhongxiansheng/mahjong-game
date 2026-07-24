extends GutTest

# E2-02 / #232 切片 Red：TurnEngine 权威变更 API 全走实体 instance_id。
# 失败零修改；不信客户端 Tile 对象。真实 BattleState/TurnEngine，不 mock。


func _tile(tid: int, iid: int, red: bool = false) -> Tile:
	return Tile.new(tid, red, Tile.NO_OWNER, iid)


func _new_engine() -> TurnEngine:
	return TurnEngine.new(BattleState.for_east_round(42, 0, 1, 0, 0))


func _set_hand(seat: Seat, tiles: Array) -> void:
	seat.hand = Hand.new()
	for t in tiles:
		seat.hand.add(t)


func _hand_iids(seat: Seat) -> Array:
	var out: Array = []
	for t in seat.hand._tiles:
		out.append(t.instance_id)
	return out


func _river_iids(state: BattleState, seat_id: int) -> Array:
	var out: Array = []
	for t in state.discards_per_seat[seat_id]:
		out.append(t.instance_id)
	return out


func _meld_snapshot(seat: Seat) -> Array:
	var out: Array = []
	for m in seat.melds:
		var tile_iids: Array = []
		for t in m.tiles:
			tile_iids.append(t.instance_id)
		out.append({
			"meld_id": m.meld_id,
			"kind": m.kind,
			"from_seat": m.from_seat,
			"called_iid": m.called_tile_instance_id,
			"added_iid": m.added_tile_instance_id,
			"tiles": tile_iids,
		})
	return out


func _furiten_snap(seat: Seat) -> Dictionary:
	return {
		"permanent": seat.furiten.permanent,
		"temporary": seat.furiten.temporary,
		"waits": seat.furiten.waits.duplicate(),
	}


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


# 14 张：上述 13 + 和牌实体 W5（last_drawn）
func _standard_tsumo_14_winning_w5(start_iid: int, win_iid: int) -> Array:
	var tiles: Array = _standard_tenpai_waiting_w5(start_iid)
	tiles.append(_tile(TileId.W5, win_iid))
	return tiles


# ---- discard 精确实体 ----

func test_discard_by_instance_id_selects_exact_entity() -> void:
	var e := _new_engine()
	var keep := _tile(TileId.W5, 301, false)
	var red := _tile(TileId.W5, 302, true)
	var other := _tile(TileId.W1, 303)
	_set_hand(e.state.seats[0], [keep, red, other])
	e.state.phase = BattlePhase.Kind.DISCARD
	e.state.seats[0].last_drawn_instance_id = 303

	assert_true(e.discard(302))
	assert_eq(_hand_iids(e.state.seats[0]), [301, 303])
	assert_eq(e.state.discards_per_seat[0].size(), 1)
	assert_eq(e.state.discards_per_seat[0][0].instance_id, 302)
	assert_true(e.state.discards_per_seat[0][0].is_red_dora)
	assert_eq(e.state.seats[0].last_drawn_instance_id, Tile.INVALID_INSTANCE_ID)
	assert_eq(e.state.phase, BattlePhase.Kind.CLAIM)


func test_discard_rejects_invalid_and_missing_zero_mod() -> void:
	var e := _new_engine()
	var a := _tile(TileId.W1, 10)
	var b := _tile(TileId.W2, 11)
	_set_hand(e.state.seats[0], [a, b])
	e.state.phase = BattlePhase.Kind.DISCARD
	var hand_snap := _hand_iids(e.state.seats[0])
	var phase := e.state.phase

	assert_false(e.discard(Tile.INVALID_INSTANCE_ID))
	assert_false(e.discard(9999))
	assert_eq(_hand_iids(e.state.seats[0]), hand_snap)
	assert_eq(e.state.discards_per_seat[0].size(), 0)
	assert_eq(e.state.phase, phase)


# ---- 立直 + 弃牌原子 ----

func _tenpai_14_with_discard_w3() -> Array:
	# 弃 W3(iid=900) 后 13 张听 W3：W2 W4 | T234 | T567 | S234 | S55
	return [
		_tile(TileId.W2, 901), _tile(TileId.W4, 902),
		_tile(TileId.T2, 903), _tile(TileId.T3, 904), _tile(TileId.T4, 905),
		_tile(TileId.T5, 906), _tile(TileId.T6, 907), _tile(TileId.T7, 908),
		_tile(TileId.S2, 909), _tile(TileId.S3, 910), _tile(TileId.S4, 911),
		_tile(TileId.S5, 912), _tile(TileId.S5, 913),
		_tile(TileId.W3, 900),
	]


func test_declare_riichi_and_discard_atomic_success() -> void:
	var e := _new_engine()
	_set_hand(e.state.seats[0], _tenpai_14_with_discard_w3())
	e.state.phase = BattlePhase.Kind.DISCARD
	e.state.seats[0].last_drawn_instance_id = 900

	assert_true(e.declare_riichi_and_discard(0, 900))
	assert_true(e.state.seats[0].riichi.declared)
	assert_eq(e.state.seats[0].points, 24000)
	assert_eq(e.state.riichi_sticks, 1)
	assert_eq(e.state.seats[0].hand.size(), 13)
	assert_null(e.state.seats[0].hand.find_by_instance_id(900))
	assert_eq(e.state.discards_per_seat[0][-1].instance_id, 900)
	assert_eq(e.state.phase, BattlePhase.Kind.CLAIM)
	assert_eq(e.state.seats[0].last_drawn_instance_id, Tile.INVALID_INSTANCE_ID)


func test_declare_riichi_and_discard_fail_not_tenpai_zero_mod() -> void:
	var e := _new_engine()
	# 14 张散牌，弃任一张也不听
	var tiles: Array = []
	var iids := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
	var ids := [
		TileId.W1, TileId.W3, TileId.W5, TileId.W7, TileId.W9,
		TileId.T1, TileId.T3, TileId.T5, TileId.T7, TileId.T9,
		TileId.S1, TileId.S3, TileId.S5, TileId.S7,
	]
	for i in range(14):
		tiles.append(_tile(ids[i], iids[i]))
	_set_hand(e.state.seats[0], tiles)
	e.state.phase = BattlePhase.Kind.DISCARD
	var hand_snap := _hand_iids(e.state.seats[0])
	var points: int = e.state.seats[0].points
	var sticks: int = e.state.riichi_sticks
	var phase := e.state.phase

	assert_false(e.declare_riichi_and_discard(0, 1))
	assert_false(e.state.seats[0].riichi.declared)
	assert_eq(_hand_iids(e.state.seats[0]), hand_snap)
	assert_eq(e.state.discards_per_seat[0].size(), 0)
	assert_eq(e.state.seats[0].points, points)
	assert_eq(e.state.riichi_sticks, sticks)
	assert_eq(e.state.phase, phase)


func test_declare_riichi_and_discard_fail_invalid_id_zero_mod() -> void:
	var e := _new_engine()
	_set_hand(e.state.seats[0], _tenpai_14_with_discard_w3())
	e.state.phase = BattlePhase.Kind.DISCARD
	var hand_snap := _hand_iids(e.state.seats[0])
	var points: int = e.state.seats[0].points
	var sticks: int = e.state.riichi_sticks

	assert_false(e.declare_riichi_and_discard(0, Tile.INVALID_INSTANCE_ID))
	assert_false(e.declare_riichi_and_discard(0, 9999))
	assert_false(e.state.seats[0].riichi.declared)
	assert_eq(_hand_iids(e.state.seats[0]), hand_snap)
	assert_eq(e.state.discards_per_seat[0].size(), 0)
	assert_eq(e.state.seats[0].points, points)
	assert_eq(e.state.riichi_sticks, sticks)


# ---- draw / rinshan → last_drawn_instance_id；tsumo 只认权威 ----

func test_draw_for_current_writes_last_drawn_instance_id() -> void:
	var e := _new_engine()
	var t := e.draw_for_current()
	assert_not_null(t)
	assert_ne(t.instance_id, Tile.INVALID_INSTANCE_ID)
	assert_eq(e.state.seats[0].last_drawn_instance_id, t.instance_id)


func test_rinshan_after_minkan_writes_last_drawn_instance_id() -> void:
	var e := _new_engine()
	var claimed := _tile(TileId.W5, 400)
	var c1 := _tile(TileId.W5, 401)
	var c2 := _tile(TileId.W5, 402)
	var c3 := _tile(TileId.W5, 403)
	_set_hand(e.state.seats[0], [claimed])
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(400))
	_set_hand(e.state.seats[2], [c1, c2, c3])
	assert_true(e.apply_minkan(2, 400, [401, 402, 403]))
	assert_ne(e.state.seats[2].last_drawn_instance_id, Tile.INVALID_INSTANCE_ID)
	var drawn_iid: int = e.state.seats[2].last_drawn_instance_id
	var found: Tile = e.state.seats[2].hand.find_by_instance_id(drawn_iid)
	assert_not_null(found, "岭上实体必须留在手牌")
	assert_eq(found.instance_id, drawn_iid)


func test_tsumo_accepts_only_authoritative_last_drawn() -> void:
	# 真实标准和牌 14 张；last_drawn 是和牌实体 W5
	var e := _new_engine()
	var win_iid: int = 1500
	_set_hand(e.state.seats[0], _standard_tsumo_14_winning_w5(1400, win_iid))
	e.state.phase = BattlePhase.Kind.DISCARD
	e.state.seats[0].last_drawn_instance_id = win_iid
	var good_iid: int = win_iid
	# 错误 / INVALID_INSTANCE_ID → 零修改
	assert_false(e.apply_tsumo(0, Tile.INVALID_INSTANCE_ID))
	assert_false(e.apply_tsumo(0, good_iid + 99999))
	assert_eq(e.state.phase, BattlePhase.Kind.DISCARD)
	assert_eq(e.state.seats[0].last_drawn_instance_id, good_iid)
	# 权威 last drawn + 真实可和
	assert_true(e.apply_tsumo(0, good_iid))
	assert_eq(e.state.phase, BattlePhase.Kind.SETTLE)


# ---- chi / pon / minkan / ankan：明确实体 + 非法零修改 ----

func test_apply_chi_uses_explicit_entities() -> void:
	var e := _new_engine()
	var claimed := _tile(TileId.W3, 500)
	var c_w2 := _tile(TileId.W2, 501)
	var c_w4 := _tile(TileId.W4, 502)
	_set_hand(e.state.seats[0], [claimed, _tile(TileId.S1, 599)])
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(500))
	_set_hand(e.state.seats[1], [c_w2, c_w4])

	assert_true(e.apply_chi(1, 500, [501, 502]))
	assert_eq(e.state.seats[1].melds.size(), 1)
	var m: Meld = e.state.seats[1].melds[0]
	assert_eq(m.kind, Meld.Kind.CHI)
	assert_ne(m.meld_id, Tile.INVALID_INSTANCE_ID)
	assert_eq(m.called_tile_instance_id, 500)
	assert_eq(m.called_tile.instance_id, 500)
	assert_eq(m.from_seat, 0)
	assert_eq(e.state.seats[1].hand.size(), 0)
	assert_eq(e.state.discards_per_seat[0].size(), 0)
	assert_eq(e.state.current_seat, 1)


func test_apply_chi_illegal_entity_zero_mod() -> void:
	var e := _new_engine()
	var claimed := _tile(TileId.W3, 500)
	_set_hand(e.state.seats[0], [claimed])
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(500))
	var c_w2 := _tile(TileId.W2, 501)
	var c_w4 := _tile(TileId.W4, 502)
	_set_hand(e.state.seats[1], [c_w2, c_w4])
	var hand_snap := _hand_iids(e.state.seats[1])
	var meld_snap := _meld_snapshot(e.state.seats[1])
	var river_snap := _river_iids(e.state, 0)
	var cur := e.state.current_seat
	var phase := e.state.phase

	# 重复 companion / 缺失 / INVALID_INSTANCE_ID / 伪造 claimed
	assert_false(e.apply_chi(1, 500, [501, 501]))
	assert_false(e.apply_chi(1, 500, [501, 999]))
	assert_false(e.apply_chi(1, 500, [501, Tile.INVALID_INSTANCE_ID]))
	assert_false(e.apply_chi(1, Tile.INVALID_INSTANCE_ID, [501, 502]))
	assert_false(e.apply_chi(1, 777, [501, 502]), "不在河的 claimed 拒绝（不信客户端）")

	assert_eq(_hand_iids(e.state.seats[1]), hand_snap)
	assert_eq(_meld_snapshot(e.state.seats[1]), meld_snap)
	assert_eq(_river_iids(e.state, 0), river_snap)
	assert_eq(e.state.current_seat, cur)
	assert_eq(e.state.phase, phase)


func test_apply_pon_uses_explicit_entities_and_illegal_zero_mod() -> void:
	var e := _new_engine()
	var claimed := _tile(TileId.W5, 600, true)
	_set_hand(e.state.seats[0], [claimed])
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(600))
	var black_a := _tile(TileId.W5, 601, false)
	var black_b := _tile(TileId.W5, 602, false)
	_set_hand(e.state.seats[2], [black_a, black_b, _tile(TileId.S1, 603)])

	# 非法：缺一张 / INVALID_INSTANCE_ID
	var hand_snap := _hand_iids(e.state.seats[2])
	var river_snap := _river_iids(e.state, 0)
	assert_false(e.apply_pon(2, 600, [601, Tile.INVALID_INSTANCE_ID]))
	assert_false(e.apply_pon(2, 600, [601, 999]))
	assert_eq(_hand_iids(e.state.seats[2]), hand_snap)
	assert_eq(_river_iids(e.state, 0), river_snap)
	assert_eq(e.state.seats[2].melds.size(), 0)
	assert_eq(e.state.current_seat, 0)

	assert_true(e.apply_pon(2, 600, [601, 602]))
	var m: Meld = e.state.seats[2].melds[0]
	assert_eq(m.kind, Meld.Kind.PON)
	assert_eq(m.called_tile_instance_id, 600)
	assert_true(m.called_tile.is_red_dora)
	assert_eq(m.from_seat, 0)
	assert_ne(m.meld_id, Tile.INVALID_INSTANCE_ID)
	assert_eq(_hand_iids(e.state.seats[2]), [603])


func test_apply_minkan_explicit_entities_illegal_zero_mod() -> void:
	var e := _new_engine()
	var claimed := _tile(TileId.W5, 700)
	_set_hand(e.state.seats[0], [claimed])
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(700))
	var cs: Array = [
		_tile(TileId.W5, 701), _tile(TileId.W5, 702), _tile(TileId.W5, 703),
		_tile(TileId.S1, 704),
	]
	_set_hand(e.state.seats[2], cs)
	var hand_snap := _hand_iids(e.state.seats[2])
	var river_snap := _river_iids(e.state, 0)

	assert_false(e.apply_minkan(2, 700, [701, 702, Tile.INVALID_INSTANCE_ID]))
	assert_false(e.apply_minkan(2, 700, [701, 702, 999]))
	assert_eq(_hand_iids(e.state.seats[2]), hand_snap)
	assert_eq(_river_iids(e.state, 0), river_snap)
	assert_eq(e.state.seats[2].melds.size(), 0)

	assert_true(e.apply_minkan(2, 700, [701, 702, 703]))
	assert_eq(e.state.seats[2].melds[0].kind, Meld.Kind.MINKAN)
	assert_eq(e.state.seats[2].melds[0].called_tile_instance_id, 700)
	assert_eq(e.state.seats[2].melds[0].tiles.size(), 4)


func test_apply_ankan_explicit_entities_illegal_zero_mod() -> void:
	var e := _new_engine()
	var tiles: Array = [
		_tile(TileId.W5, 801), _tile(TileId.W5, 802),
		_tile(TileId.W5, 803), _tile(TileId.W5, 804),
		_tile(TileId.T1, 805),
	]
	_set_hand(e.state.seats[0], tiles)
	e.state.phase = BattlePhase.Kind.DISCARD
	e.state.seats[0].last_drawn_instance_id = 804
	var hand_snap := _hand_iids(e.state.seats[0])
	var phase := e.state.phase

	assert_false(e.apply_ankan(0, [801, 802, 803, Tile.INVALID_INSTANCE_ID]))
	assert_false(e.apply_ankan(0, [801, 802, 803, 999]))
	assert_false(e.apply_ankan(0, [801, 802, 803]))  # 非法 size
	assert_eq(_hand_iids(e.state.seats[0]), hand_snap)
	assert_eq(e.state.seats[0].melds.size(), 0)
	assert_eq(e.state.phase, phase)

	assert_true(e.apply_ankan(0, [801, 802, 803, 804]))
	assert_eq(e.state.seats[0].melds[0].kind, Meld.Kind.ANKAN)
	assert_eq(e.state.seats[0].melds[0].tiles.size(), 4)
	assert_eq(e.state.seats[0].melds[0].from_seat, Meld.NO_SOURCE_SEAT)
	assert_ne(e.state.seats[0].last_drawn_instance_id, Tile.INVALID_INSTANCE_ID)


# ---- added_kan：按 meld_id，保留 identity，只追加指定实体 ----

func test_apply_added_kan_preserves_meld_identity() -> void:
	var e := _new_engine()
	# 先 pon 建副露
	var claimed := _tile(TileId.W5, 900, true)
	_set_hand(e.state.seats[0], [claimed])
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(900))
	_set_hand(e.state.seats[1], [
		_tile(TileId.W5, 901, false), _tile(TileId.W5, 902, false),
	])
	assert_true(e.apply_pon(1, 900, [901, 902]))
	var m0: Meld = e.state.seats[1].melds[0]
	var keep_meld_id: int = m0.meld_id
	var keep_called: int = m0.called_tile_instance_id
	var keep_from: int = m0.from_seat
	assert_ne(keep_meld_id, Tile.INVALID_INSTANCE_ID)
	assert_eq(keep_called, 900)

	# claimant 摸到第 4 张后加杠（转 current 已是 1）
	var fourth := _tile(TileId.W5, 903, false)
	e.state.seats[1].hand.add(fourth)
	e.state.seats[1].last_drawn_instance_id = 903
	e.state.phase = BattlePhase.Kind.DISCARD

	assert_true(e.apply_added_kan(1, keep_meld_id, 903))
	assert_eq(e.state.seats[1].melds.size(), 1)
	var m1: Meld = e.state.seats[1].melds[0]
	assert_eq(m1.kind, Meld.Kind.ADDED_KAN)
	assert_eq(m1.meld_id, keep_meld_id, "加杠保留原 meld_id")
	assert_eq(m1.called_tile_instance_id, keep_called, "保留 called")
	assert_eq(m1.from_seat, keep_from, "保留 source seat")
	assert_eq(m1.added_tile_instance_id, 903)
	assert_eq(m1.tiles.size(), 4)
	var tile_iids: Array = []
	for t in m1.tiles:
		tile_iids.append(t.instance_id)
	assert_true(tile_iids.has(900))
	assert_true(tile_iids.has(901))
	assert_true(tile_iids.has(902))
	assert_true(tile_iids.has(903))
	assert_eq(m1.called_tile.instance_id, 900)


func test_apply_added_kan_illegal_zero_mod() -> void:
	var e := _new_engine()
	var claimed := _tile(TileId.W5, 900)
	_set_hand(e.state.seats[0], [claimed])
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(900))
	_set_hand(e.state.seats[1], [
		_tile(TileId.W5, 901), _tile(TileId.W5, 902),
	])
	assert_true(e.apply_pon(1, 900, [901, 902]))
	var meld_id: int = e.state.seats[1].melds[0].meld_id
	var fourth := _tile(TileId.W5, 903)
	var junk := _tile(TileId.S1, 904)
	e.state.seats[1].hand.add(fourth)
	e.state.seats[1].hand.add(junk)
	e.state.phase = BattlePhase.Kind.DISCARD

	var hand_snap := _hand_iids(e.state.seats[1])
	var meld_snap := _meld_snapshot(e.state.seats[1])
	var phase := e.state.phase
	var cur := e.state.current_seat

	assert_false(e.apply_added_kan(1, meld_id, Tile.INVALID_INSTANCE_ID))
	assert_false(e.apply_added_kan(1, meld_id, 9999))
	assert_false(e.apply_added_kan(1, meld_id + 99, 903), "错误 meld_id")
	assert_false(e.apply_added_kan(1, meld_id, 904), "非对应实体")

	assert_eq(_hand_iids(e.state.seats[1]), hand_snap)
	assert_eq(_meld_snapshot(e.state.seats[1]), meld_snap)
	assert_eq(e.state.phase, phase)
	assert_eq(e.state.current_seat, cur)


# ---- ron：实体 id；拒绝 INVALID；真实标准和牌 / 假和 / 振听 ----

func test_apply_ron_rejects_invalid_accepts_river_entity() -> void:
	# claimant 13 张真实听 W5；河末实体为 W5
	var e := _new_engine()
	var claimed := _tile(TileId.W5, 1000)
	_set_hand(e.state.seats[0], [claimed])
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(1000))
	_set_hand(e.state.seats[2], _standard_tenpai_waiting_w5(2000))
	# 契约：ClaimValidator 认定可荣
	assert_true(ClaimValidator.can_ron(
		e.state.seats[2].hand, e.state.seats[2].melds,
		e.state.discards_per_seat[0][-1], e.state.seats[2].furiten))
	var phase := e.state.phase
	var cur := e.state.current_seat

	assert_false(e.apply_ron(2, Tile.INVALID_INSTANCE_ID))
	assert_eq(e.state.phase, phase)
	assert_eq(e.state.current_seat, cur)

	assert_true(e.apply_ron(2, 1000))
	assert_eq(e.state.phase, BattlePhase.Kind.SETTLE)
	assert_eq(e.state.current_seat, 2)


func test_apply_ron_rejects_non_winning_identity_ok_zero_mod() -> void:
	# 河末 identity 正确，但 ClaimValidator.can_ron=false（非和牌张）
	var e := _new_engine()
	var claimed := _tile(TileId.HAKU, 1050)
	_set_hand(e.state.seats[0], [claimed])
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(1050))
	_set_hand(e.state.seats[2], _standard_tenpai_waiting_w5(2100))
	assert_false(ClaimValidator.can_ron(
		e.state.seats[2].hand, e.state.seats[2].melds,
		e.state.discards_per_seat[0][-1], e.state.seats[2].furiten),
		"白板不完成此型")

	var phase := e.state.phase
	var cur := e.state.current_seat
	var river_snap := _river_iids(e.state, 0)
	var hand_snap := _hand_iids(e.state.seats[2])
	var meld_snap := _meld_snapshot(e.state.seats[2])
	var furiten_snap := _furiten_snap(e.state.seats[2])

	assert_false(e.apply_ron(2, 1050))
	assert_eq(e.state.phase, phase)
	assert_eq(e.state.current_seat, cur)
	assert_eq(_river_iids(e.state, 0), river_snap)
	assert_eq(_hand_iids(e.state.seats[2]), hand_snap)
	assert_eq(_meld_snapshot(e.state.seats[2]), meld_snap)
	assert_eq(_furiten_snap(e.state.seats[2]), furiten_snap)


func test_apply_ron_rejects_furiten_permanent_zero_mod() -> void:
	# 真实可和牌 W5，但 claimant.furiten.permanent
	var e := _new_engine()
	var claimed := _tile(TileId.W5, 1060)
	_set_hand(e.state.seats[0], [claimed])
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(1060))
	_set_hand(e.state.seats[2], _standard_tenpai_waiting_w5(2200))
	e.state.seats[2].furiten.permanent = true
	assert_false(ClaimValidator.can_ron(
		e.state.seats[2].hand, e.state.seats[2].melds,
		e.state.discards_per_seat[0][-1], e.state.seats[2].furiten))

	var phase := e.state.phase
	var cur := e.state.current_seat
	var river_snap := _river_iids(e.state, 0)
	var hand_snap := _hand_iids(e.state.seats[2])
	var meld_snap := _meld_snapshot(e.state.seats[2])
	var furiten_snap := _furiten_snap(e.state.seats[2])

	assert_false(e.apply_ron(2, 1060))
	assert_eq(e.state.phase, phase)
	assert_eq(e.state.current_seat, cur)
	assert_eq(_river_iids(e.state, 0), river_snap)
	assert_eq(_hand_iids(e.state.seats[2]), hand_snap)
	assert_eq(_meld_snapshot(e.state.seats[2]), meld_snap)
	assert_eq(_furiten_snap(e.state.seats[2]), furiten_snap)


func test_apply_ron_rejects_furiten_temporary_zero_mod() -> void:
	# 真实可和牌 W5，但 claimant.furiten.temporary
	var e := _new_engine()
	var claimed := _tile(TileId.W5, 1070)
	_set_hand(e.state.seats[0], [claimed])
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(1070))
	_set_hand(e.state.seats[2], _standard_tenpai_waiting_w5(2300))
	e.state.seats[2].furiten.temporary = true
	assert_false(ClaimValidator.can_ron(
		e.state.seats[2].hand, e.state.seats[2].melds,
		e.state.discards_per_seat[0][-1], e.state.seats[2].furiten))

	var phase := e.state.phase
	var cur := e.state.current_seat
	var river_snap := _river_iids(e.state, 0)
	var hand_snap := _hand_iids(e.state.seats[2])
	var meld_snap := _meld_snapshot(e.state.seats[2])
	var furiten_snap := _furiten_snap(e.state.seats[2])

	assert_false(e.apply_ron(2, 1070))
	assert_eq(e.state.phase, phase)
	assert_eq(e.state.current_seat, cur)
	assert_eq(_river_iids(e.state, 0), river_snap)
	assert_eq(_hand_iids(e.state.seats[2]), hand_snap)
	assert_eq(_meld_snapshot(e.state.seats[2]), meld_snap)
	assert_eq(_furiten_snap(e.state.seats[2]), furiten_snap)


func test_apply_ron_rejects_discard_phase_zero_mod() -> void:
	# 河末实体合法，但 phase 非 CLAIM → 拒绝且零修改
	var e := _new_engine()
	var claimed := _tile(TileId.W5, 1100)
	_set_hand(e.state.seats[0], [claimed])
	e.state.phase = BattlePhase.Kind.DISCARD
	assert_true(e.discard(1100))
	_set_hand(e.state.seats[2], _standard_tenpai_waiting_w5(2400))
	e.state.phase = BattlePhase.Kind.DISCARD  # 故意偏离 CLAIM 窗口

	var phase := e.state.phase
	var cur := e.state.current_seat
	var river_snap := _river_iids(e.state, 0)
	var hand_snap := _hand_iids(e.state.seats[2])
	var meld_snap := _meld_snapshot(e.state.seats[2])
	var furiten_snap := _furiten_snap(e.state.seats[2])

	assert_false(e.apply_ron(2, 1100))
	assert_eq(e.state.phase, phase)
	assert_eq(e.state.current_seat, cur)
	assert_eq(_river_iids(e.state, 0), river_snap)
	assert_eq(_hand_iids(e.state.seats[2]), hand_snap)
	assert_eq(_meld_snapshot(e.state.seats[2]), meld_snap)
	assert_eq(_furiten_snap(e.state.seats[2]), furiten_snap)


func test_apply_tsumo_rejects_claim_phase_zero_mod() -> void:
	# 当前座位 last_drawn 合法且可和，但 phase=CLAIM → 拒绝且零修改
	var e := _new_engine()
	var win_iid: int = 1210
	_set_hand(e.state.seats[0], _standard_tsumo_14_winning_w5(1100, win_iid))
	e.state.seats[0].last_drawn_instance_id = win_iid
	e.state.phase = BattlePhase.Kind.CLAIM

	var phase := e.state.phase
	var cur := e.state.current_seat
	var hand_snap := _hand_iids(e.state.seats[0])
	var last_drawn: int = e.state.seats[0].last_drawn_instance_id

	assert_false(e.apply_tsumo(0, win_iid))
	assert_eq(e.state.phase, phase)
	assert_eq(e.state.current_seat, cur)
	assert_eq(_hand_iids(e.state.seats[0]), hand_snap)
	assert_eq(e.state.seats[0].last_drawn_instance_id, last_drawn)


func test_apply_tsumo_rejects_non_current_seat_zero_mod() -> void:
	# 非当前 seat 具备合法 last_drawn 实体与真实可和 14 张 → 拒绝且零修改
	var e := _new_engine()
	e.state.phase = BattlePhase.Kind.DISCARD
	e.state.current_seat = 0
	var win_iid: int = 1200
	_set_hand(e.state.seats[2], _standard_tsumo_14_winning_w5(1150, win_iid))
	e.state.seats[2].last_drawn_instance_id = win_iid

	var phase := e.state.phase
	var cur := e.state.current_seat
	var hand_snap := _hand_iids(e.state.seats[2])
	var last_drawn: int = e.state.seats[2].last_drawn_instance_id

	assert_false(e.apply_tsumo(2, win_iid))
	assert_eq(e.state.phase, phase)
	assert_eq(e.state.current_seat, cur)
	assert_eq(_hand_iids(e.state.seats[2]), hand_snap)
	assert_eq(e.state.seats[2].last_drawn_instance_id, last_drawn)


func test_apply_tsumo_rejects_non_winning_last_drawn_zero_mod() -> void:
	# last_drawn identity 正确且在 14 张手里，但移除后 13+winning 非和牌
	var e := _new_engine()
	var drawn_iid: int = 1300
	var tiles: Array = [
		_tile(TileId.W1, 1301), _tile(TileId.W3, 1302), _tile(TileId.W5, 1303),
		_tile(TileId.W7, 1304), _tile(TileId.W9, 1305),
		_tile(TileId.T1, 1306), _tile(TileId.T3, 1307), _tile(TileId.T5, 1308),
		_tile(TileId.T7, 1309), _tile(TileId.T9, 1310),
		_tile(TileId.S1, 1311), _tile(TileId.S3, 1312), _tile(TileId.S5, 1313),
		_tile(TileId.HAKU, drawn_iid),
	]
	_set_hand(e.state.seats[0], tiles)
	e.state.phase = BattlePhase.Kind.DISCARD
	e.state.seats[0].last_drawn_instance_id = drawn_iid
	# 契约：14 张中去掉 last_drawn 后 + last_drawn 不是和牌
	var without := Hand.new()
	for t in e.state.seats[0].hand._tiles:
		if t.instance_id != drawn_iid:
			without.add(t)
	var drawn: Tile = e.state.seats[0].hand.find_by_instance_id(drawn_iid)
	assert_not_null(drawn)
	assert_eq(without.size(), 13)
	assert_false(ClaimValidator.can_tsumo(without, e.state.seats[0].melds, drawn))

	var phase := e.state.phase
	var cur := e.state.current_seat
	var hand_snap := _hand_iids(e.state.seats[0])
	var last_drawn: int = e.state.seats[0].last_drawn_instance_id
	var meld_snap := _meld_snapshot(e.state.seats[0])
	var furiten_snap := _furiten_snap(e.state.seats[0])

	assert_false(e.apply_tsumo(0, drawn_iid))
	assert_eq(e.state.phase, phase)
	assert_eq(e.state.current_seat, cur)
	assert_eq(_hand_iids(e.state.seats[0]), hand_snap)
	assert_eq(e.state.seats[0].last_drawn_instance_id, last_drawn)
	assert_eq(_meld_snapshot(e.state.seats[0]), meld_snap)
	assert_eq(_furiten_snap(e.state.seats[0]), furiten_snap)
