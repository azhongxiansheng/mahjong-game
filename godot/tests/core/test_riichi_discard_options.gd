extends GutTest

# Oracle 等价：批量 RIICHI discard-option API
# 必须与「逐张 clone + take_by_instance_id + WaitCalculator.wait_tiles」完全一致。
# 任何 mismatch 立即失败；不得改 oracle、删样本、放宽断言。

# ---- helpers ----

func _hand_from_ids(ids: Array, start_iid: int = 1000) -> Hand:
	var h := Hand.new()
	var iid: int = start_iid
	for tid in ids:
		assert_true(h.add(Tile.new(int(tid), false, Tile.NO_OWNER, iid)),
			"hand add iid=%d tid=%d" % [iid, tid])
		iid += 1
	return h


func _seat_from_ids(ids: Array, start_iid: int = 1000, points: int = 25000) -> Seat:
	var s := Seat.new(0, TileId.E, points)
	s.hand = _hand_from_ids(ids, start_iid)
	return s


## Oracle：对每个物理 Tile 实例 clone → take_by_instance_id → wait_tiles 非空。
func _oracle_tenpai_discard_iids(hand: Hand, melds: Array) -> Array:
	var out: Array = []
	for t in hand._tiles:
		if t == null:
			continue
		var sim: Hand = hand.clone()
		if sim.take_by_instance_id(t.instance_id) == null:
			continue
		if not WaitCalculator.wait_tiles(sim, melds).is_empty():
			out.append(t.instance_id)
	return out


func _sorted_iids(arr: Array) -> Array:
	var copy: Array = arr.duplicate()
	copy.sort()
	return copy


func _assert_iid_set_eq(got: Array, expected: Array, label: String) -> void:
	var g: Array = _sorted_iids(got)
	var e: Array = _sorted_iids(expected)
	if g != e:
		fail_test("MISMATCH %s: got=%s expected=%s" % [label, str(g), str(e)])
		return
	assert_eq(g, e, "match %s size=%d" % [label, e.size()])


func _iids_from_options(opts: Array) -> Array:
	var out: Array = []
	for o in opts:
		out.append(int(o.get("tile_instance_id", -1)))
	return out


# ---- fixtures: standard / chiitoi / kokushi 14 张 ----

# 标准型：123m 456m 789p 22s 33s + 多余 1m → 切 1m 听 2s/3s 等（至少听）
# 实际：123m 456m 789p 22s 345s 已是 14？用明确 14 张：
# 123m 456m 789p 22s 33s + 东（14）→ 切东 后 13 听 2s/3s 对倒；切 2s/3s 也可能听
func _standard_14_ids() -> Array:
	return [
		TileId.W1, TileId.W2, TileId.W3,
		TileId.W4, TileId.W5, TileId.W6,
		TileId.T7, TileId.T8, TileId.T9,
		TileId.S2, TileId.S2,
		TileId.S3, TileId.S3,
		TileId.E,
	]


# 七对：6 对 + 两单 → 切掉多余单张后听另一单
func _chiitoi_14_ids() -> Array:
	return [
		TileId.W1, TileId.W1,
		TileId.W3, TileId.W3,
		TileId.T2, TileId.T2,
		TileId.T5, TileId.T5,
		TileId.S6, TileId.S6,
		TileId.E, TileId.E,
		TileId.CHUN, TileId.HATSU,  # 两单：切其一听另一
	]


# 国士：13 幺九形 + 1 中张废牌 → 切废牌后听
func _kokushi_14_ids() -> Array:
	return [
		TileId.W1, TileId.W9,
		TileId.T1, TileId.T9,
		TileId.S1, TileId.S9,
		TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
		TileId.HAKU, TileId.HATSU, TileId.CHUN,
		TileId.W5,  # 废牌
	]


# ---- core oracle tests ----

func test_standard_oracle_equivalence() -> void:
	var hand: Hand = _hand_from_ids(_standard_14_ids(), 2000)
	var oracle: Array = _oracle_tenpai_discard_iids(hand, [])
	var api: Array = RiichiValidator.tenpai_discard_instance_ids(hand, [])
	_assert_iid_set_eq(api, oracle, "standard")
	assert_true(oracle.size() > 0, "standard fixture 应至少有 1 个可立直切牌")


func test_chiitoi_oracle_equivalence() -> void:
	var hand: Hand = _hand_from_ids(_chiitoi_14_ids(), 3000)
	var oracle: Array = _oracle_tenpai_discard_iids(hand, [])
	var api: Array = RiichiValidator.tenpai_discard_instance_ids(hand, [])
	_assert_iid_set_eq(api, oracle, "chiitoi")
	assert_true(oracle.size() > 0, "chiitoi fixture 应至少有 1 个可立直切牌")


func test_kokushi_oracle_equivalence() -> void:
	var hand: Hand = _hand_from_ids(_kokushi_14_ids(), 4000)
	var oracle: Array = _oracle_tenpai_discard_iids(hand, [])
	var api: Array = RiichiValidator.tenpai_discard_instance_ids(hand, [])
	_assert_iid_set_eq(api, oracle, "kokushi")
	assert_true(oracle.size() > 0, "kokushi fixture 应至少有 1 个可立直切牌")


func test_duplicate_type_distinct_instance_ids() -> void:
	# 同类型两张 S2 不同 iid；若弃 S2 后听，两个 iid 都必须在集合中
	var ids: Array = [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.S2, TileId.CHUN,  # 两张 S2 + 中；切中听 S2 单骑；切一张 S2 听中等
	]
	var hand: Hand = _hand_from_ids(ids, 5000)
	# 收集 S2 的两个 iid
	var s2_iids: Array = []
	for t in hand._tiles:
		if t.id == TileId.S2:
			s2_iids.append(t.instance_id)
	assert_eq(s2_iids.size(), 2, "应有两张 S2")
	assert_ne(s2_iids[0], s2_iids[1], "S2 instance_id 必须不同")

	var oracle: Array = _oracle_tenpai_discard_iids(hand, [])
	var api: Array = RiichiValidator.tenpai_discard_instance_ids(hand, [])
	_assert_iid_set_eq(api, oracle, "dup_type")

	# 若 oracle 含任一 S2，则两个 S2 iid 都必须出现（同 multiset）
	var oracle_has_s2: bool = false
	for iid in oracle:
		if iid == s2_iids[0] or iid == s2_iids[1]:
			oracle_has_s2 = true
			break
	if oracle_has_s2:
		assert_true(oracle.has(s2_iids[0]), "oracle 含 S2 则两 iid 都在")
		assert_true(oracle.has(s2_iids[1]), "oracle 含 S2 则两 iid 都在")
		assert_true(api.has(s2_iids[0]), "api 含 S2 则两 iid 都在")
		assert_true(api.has(s2_iids[1]), "api 含 S2 则两 iid 都在")


func test_menzen_and_open_melds() -> void:
	# 门清 14 张
	var hand_m: Hand = _hand_from_ids(_standard_14_ids(), 6000)
	_assert_iid_set_eq(
		RiichiValidator.tenpai_discard_instance_ids(hand_m, []),
		_oracle_tenpai_discard_iids(hand_m, []),
		"menzen"
	)

	# 有副露（PON）时：10 张暗牌 + 1 PON（等价 13 听牌期前需再摸 → 11 张弃前）
	# 构造：副露 PON 中 + 暗 11 张（弃一张后 10 = 13-3）
	var open_ids: Array = [
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7,  # 11 张；切后 10 + PON 听
	]
	var hand_o: Hand = _hand_from_ids(open_ids, 6100)
	var melds: Array = [
		Meld.make_pon([
			Tile.new(TileId.CHUN, false, Tile.NO_OWNER, 9001),
			Tile.new(TileId.CHUN, false, Tile.NO_OWNER, 9002),
			Tile.new(TileId.CHUN, false, Tile.NO_OWNER, 9003),
		], 1),
	]
	_assert_iid_set_eq(
		RiichiValidator.tenpai_discard_instance_ids(hand_o, melds),
		_oracle_tenpai_discard_iids(hand_o, melds),
		"open_melds"
	)


func test_gate_points_wall_already_riichi() -> void:
	var s: Seat = _seat_from_ids(_standard_14_ids(), 7000, 25000)
	# 正常应有 options
	var ok_opts: Array = RiichiValidator.riichi_discard_options(s, 50)
	var oracle_iids: Array = _oracle_tenpai_discard_iids(s.hand, s.melds)
	_assert_iid_set_eq(_iids_from_options(ok_opts), oracle_iids, "gate_ok")
	assert_true(ok_opts.size() > 0, "points/wall 合法时应有 options")

	# points < 1000
	var s_low: Seat = _seat_from_ids(_standard_14_ids(), 7100, 500)
	var low_opts: Array = RiichiValidator.riichi_discard_options(s_low, 50)
	assert_eq(low_opts.size(), 0, "points<1000 → 空 options")

	# wall < 4
	var s_wall: Seat = _seat_from_ids(_standard_14_ids(), 7200, 25000)
	var wall_opts: Array = RiichiValidator.riichi_discard_options(s_wall, 3)
	assert_eq(wall_opts.size(), 0, "wall<4 → 空 options")

	# 已立直
	var s_dec: Seat = _seat_from_ids(_standard_14_ids(), 7300, 25000)
	s_dec.riichi.declare(1, false)
	var dec_opts: Array = RiichiValidator.riichi_discard_options(s_dec, 50)
	assert_eq(dec_opts.size(), 0, "已立直 → 空 options")

	# 有明副露破门清
	var s_open: Seat = _seat_from_ids(_standard_14_ids(), 7400, 25000)
	s_open.melds.append(Meld.make_pon([
		Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5),
	], 1))
	var open_opts: Array = RiichiValidator.riichi_discard_options(s_open, 50)
	assert_eq(open_opts.size(), 0, "有明副露 → 空 options")


func test_fixed_seeds_battle_state_hands_0_to_9() -> void:
	# 固定 seeds 0..9：真实 BattleState 发牌后补摸至 14 张，四座全部 oracle 比对
	# 变量名避免 shadow 内置 seed()
	var total_comparisons: int = 0
	var total_mismatches: int = 0
	for battle_seed in range(10):
		var state: BattleState = BattleState.for_east_round(battle_seed, 0, 1, 0, 0)
		assert_not_null(state, "state seed=%d" % battle_seed)
		for seat_id in range(4):
			var seat: Seat = state.seats[seat_id]
			# 起手 13 → 再摸 1 成 14（与 TURN 弃前一致）
			assert_eq(seat.hand.size(), 13, "seed=%d seat=%d 起手 13" % [battle_seed, seat_id])
			var drawn: Tile = state.wall.draw()
			assert_not_null(drawn, "seed=%d seat=%d draw" % [battle_seed, seat_id])
			seat.add_to_hand(drawn)
			assert_eq(seat.hand.size(), 14, "seed=%d seat=%d 14 张" % [battle_seed, seat_id])

			var oracle: Array = _oracle_tenpai_discard_iids(seat.hand, seat.melds)
			var api: Array = RiichiValidator.tenpai_discard_instance_ids(seat.hand, seat.melds)
			var g: Array = _sorted_iids(api)
			var e: Array = _sorted_iids(oracle)
			total_comparisons += 1
			if g != e:
				total_mismatches += 1
				fail_test("MISMATCH seed=%d seat=%d got=%s expected=%s" % [
					battle_seed, seat_id, str(g), str(e)])
			else:
				pass_test("seed=%d seat=%d match n=%d" % [battle_seed, seat_id, e.size()])

			# 门槛 API 与 tenpai 集合在合法前置下一致
			var opts: Array = RiichiValidator.riichi_discard_options(seat, 50)
			_assert_iid_set_eq(_iids_from_options(opts), oracle,
				"seed=%d seat=%d options" % [battle_seed, seat_id])

	gut.p("fixed_seeds comparisons=%d mismatches=%d" % [total_comparisons, total_mismatches])
	assert_eq(total_mismatches, 0, "seeds 0..9 零 mismatch")
	assert_eq(total_comparisons, 40, "10 seeds × 4 seats = 40")


func test_shanten_zero_matches_wait_oracle_for_400_dealt_hands() -> void:
	var mismatches: int = 0
	for rng_seed in range(100):
		var state: BattleState = BattleState.for_east_round(rng_seed, 0, 1, 0, 0)
		for seat_id in range(4):
			var seat: Seat = state.seats[seat_id]
			var expected: bool = not WaitCalculator.wait_tiles(
				seat.hand, seat.melds).is_empty()
			var actual: bool = ShantenCalculator.calc(seat.hand, seat.melds) == 0
			if actual != expected:
				mismatches += 1
				fail_test("shanten/wait mismatch seed=%d seat=%d shanten=%d waits=%s" % [
					rng_seed, seat_id,
					ShantenCalculator.calc(seat.hand, seat.melds),
					str(WaitCalculator.wait_tiles(seat.hand, seat.melds)),
				])
	assert_eq(mismatches, 0, "400 手牌 shanten==0 与 WaitCalculator 听牌真值一致")
