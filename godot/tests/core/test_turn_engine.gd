extends GutTest

# TurnEngine: 状态机最小骨架（plan 0e）。
# 范围：draw_for_current / discard / advance_to_next_seat / declare_riichi。
# 鸣牌应用 (chi/pon/kan) 与胡牌应用 (ron/tsumo) 留下一计划。

func _new_engine() -> TurnEngine:
	var state := BattleState.for_east_round(42, 0, 1, 0, 0)
	return TurnEngine.new(state)

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
	var ok := e.discard(t.id)
	assert_true(ok)
	assert_eq(e.state.seats[0].hand.size(), 13)
	assert_eq(e.state.discards_per_seat[0].size(), 1)
	assert_eq(e.state.discards_per_seat[0][0].id, t.id)
	assert_eq(e.state.phase, BattlePhase.Kind.CLAIM)

func test_discard_returns_false_when_not_in_hand():
	var e := _new_engine()
	e.draw_for_current()
	# 弃个手里肯定没有的牌（W9 假设不在 — 但起手随机；先 draw 下记下手有什么）
	# 改：弃一个肯定不在的"伪 id"，但 id 必须是 0..33 范围。直接弃 dora indicator
	# 用确定不在手里的：直接弃 5 次同 id 必失败
	var fake_id: int = TileId.W1
	# 清空手中 W1 张数（如果有）
	while e.state.seats[0].hand.count_of(fake_id) > 0:
		e.state.seats[0].hand.remove_by_id(fake_id)
	assert_false(e.discard(fake_id))

# ---- advance_to_next_seat ----

func test_advance_rotates_current_seat_and_resets_phase():
	var e := _new_engine()
	e.draw_for_current()
	e.discard(e.state.seats[0].hand.to_id_array()[0])
	e.advance_to_next_seat()
	assert_eq(e.state.current_seat, 1)
	assert_eq(e.state.phase, BattlePhase.Kind.DRAW)

func test_advance_full_round_increments_turn_count():
	var e := _new_engine()
	# 4 家各摸 1 弃 1
	for _i in range(4):
		e.draw_for_current()
		var first_id: int = e.state.seats[e.state.current_seat].hand.to_id_array()[0]
		e.discard(first_id)
		e.advance_to_next_seat()
	# 回到 dealer，turn_count 应 = 1（第 1 巡完成）
	assert_eq(e.state.current_seat, 0)
	assert_eq(e.state.turn_count, 1)

func test_first_round_active_cleared_after_round_2():
	var e := _new_engine()
	# 跑 2 巡（8 次 draw/discard/advance）
	for _i in range(8):
		e.draw_for_current()
		var first_id: int = e.state.seats[e.state.current_seat].hand.to_id_array()[0]
		e.discard(first_id)
		e.advance_to_next_seat()
	assert_eq(e.state.turn_count, 2)
	assert_false(e.state.first_round_active, "第 2 巡开始后清")

# ---- declare_riichi ----

func test_declare_riichi_succeeds_when_valid():
	var e := _new_engine()
	# 替换 seat 0 hand 成可立直型（13 张听牌、门清、点数足）
	e.state.seats[0].hand = Hand.new()
	for tid in [
		TileId.W2, TileId.W4,    # 等 W3
		TileId.T2, TileId.T3, TileId.T4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S5, TileId.S5,
	]:
		e.state.seats[0].add_to_hand(Tile.new(tid))
	var ok := e.declare_riichi(0)
	assert_true(ok)
	assert_true(e.state.seats[0].riichi.declared)
	assert_eq(e.state.seats[0].points, 24000, "扣 1000 立直棒")
	assert_eq(e.state.riichi_sticks, 1, "桌上立直棒 +1")

func test_declare_riichi_fails_when_invalid():
	var e := _new_engine()
	# 不替换 hand 起手大概率不听 → riichi 拒绝
	# 但也可能恰巧听，所以强制不听：清空手放 13 张全散
	e.state.seats[0].hand = Hand.new()
	for tid in [
		TileId.W1, TileId.W3, TileId.W5, TileId.W7, TileId.W9,
		TileId.T1, TileId.T3, TileId.T5, TileId.T7, TileId.T9,
		TileId.S1, TileId.S3, TileId.S5,
	]:
		e.state.seats[0].add_to_hand(Tile.new(tid))
	var ok := e.declare_riichi(0)
	assert_false(ok)
	assert_false(e.state.seats[0].riichi.declared)
	assert_eq(e.state.seats[0].points, 25000, "未扣点")

# ---- apply_chi/pon/minkan ----

func _setup_after_dealer_discards(e: TurnEngine, discard_id: int) -> Tile:
	# 让 dealer 摸 + 弃 discard_id；返回弃出的 Tile
	e.state.seats[0].hand = Hand.new()
	for tid in range(13):
		e.state.seats[0].add_to_hand(Tile.new(TileId.W1 + (tid % 9)))
	e.state.seats[0].add_to_hand(Tile.new(discard_id))  # 14 张
	e.state.phase = BattlePhase.Kind.DISCARD
	e.discard(discard_id)
	# discards_per_seat[0] 末张是刚弃的
	return e.state.discards_per_seat[0][-1]

func test_apply_chi_success():
	var e := _new_engine()
	# claimant=1（下家），手中有 W2 + W4 → 吃 W3
	e.state.seats[1].hand = Hand.new()
	e.state.seats[1].add_to_hand(Tile.new(TileId.W2))
	e.state.seats[1].add_to_hand(Tile.new(TileId.W4))
	var tile := _setup_after_dealer_discards(e, TileId.W3)
	var ok := e.apply_chi(1, tile, [TileId.W2, TileId.W4])
	assert_true(ok)
	assert_eq(e.state.seats[1].melds.size(), 1)
	assert_eq(e.state.seats[1].melds[0].kind, Meld.Kind.CHI)
	assert_eq(e.state.seats[1].hand.size(), 0)
	assert_eq(e.state.discards_per_seat[0].size(), 0, "弃牌被取走")
	assert_eq(e.state.current_seat, 1)
	assert_eq(e.state.phase, BattlePhase.Kind.DISCARD)
	assert_false(e.state.first_round_active, "鸣牌打破第一巡")

func test_apply_chi_rejected_for_non_next_seat():
	var e := _new_engine()
	e.state.seats[2].hand = Hand.new()
	e.state.seats[2].add_to_hand(Tile.new(TileId.W2))
	e.state.seats[2].add_to_hand(Tile.new(TileId.W4))
	var tile := _setup_after_dealer_discards(e, TileId.W3)
	var ok := e.apply_chi(2, tile, [TileId.W2, TileId.W4])
	assert_false(ok, "对家不可吃")

func test_apply_pon_success():
	var e := _new_engine()
	e.state.seats[2].hand = Hand.new()
	e.state.seats[2].add_to_hand(Tile.new(TileId.W5))
	e.state.seats[2].add_to_hand(Tile.new(TileId.W5))
	var tile := _setup_after_dealer_discards(e, TileId.W5)
	var ok := e.apply_pon(2, tile)
	assert_true(ok)
	assert_eq(e.state.seats[2].melds[0].kind, Meld.Kind.PON)
	assert_eq(e.state.current_seat, 2)
	assert_eq(e.state.phase, BattlePhase.Kind.DISCARD)

func test_apply_minkan_reveals_new_dora_and_takes_rinshan():
	var e := _new_engine()
	e.state.seats[2].hand = Hand.new()
	for _i in range(3):
		e.state.seats[2].add_to_hand(Tile.new(TileId.W5))
	var initial_dora_count := e.state.dora_indicators.visible.size()
	var tile := _setup_after_dealer_discards(e, TileId.W5)
	var ok := e.apply_minkan(2, tile)
	assert_true(ok)
	assert_eq(e.state.seats[2].melds[0].kind, Meld.Kind.MINKAN)
	assert_eq(e.state.dora_indicators.visible.size(), initial_dora_count + 1, "明杠翻 dora")
	assert_eq(e.state.seats[2].hand.size(), 1, "摸岭上后 1 张")
	assert_eq(e.state.phase, BattlePhase.Kind.DISCARD)

# ---- apply_ankan / apply_added_kan ----

func test_apply_ankan_success():
	var e := _new_engine()
	# 自家回合摸了 14 张含 4 张同
	e.state.seats[0].hand = Hand.new()
	for _i in range(4):
		e.state.seats[0].add_to_hand(Tile.new(TileId.W5))
	for tid in range(10):
		e.state.seats[0].add_to_hand(Tile.new(TileId.T1 + tid))
	var initial_dora_count := e.state.dora_indicators.visible.size()
	var ok := e.apply_ankan(0, TileId.W5)
	assert_true(ok)
	assert_eq(e.state.seats[0].melds[0].kind, Meld.Kind.ANKAN)
	assert_eq(e.state.seats[0].melds[0].tiles.size(), 4, "暗杠 4 张")
	assert_eq(e.state.dora_indicators.visible.size(), initial_dora_count + 1)
	# 注：count_of(W5) 不能为 0 — 岭上摸到的可能恰是 W5
	assert_eq(e.state.phase, BattlePhase.Kind.DISCARD)

func test_apply_added_kan_success():
	var e := _new_engine()
	# 已有 PON W5 副露 + 手中第 4 张 W5
	var pon := Meld.make_pon(
		[Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)], 1)
	e.state.seats[0].melds.append(pon)
	e.state.seats[0].hand = Hand.new()
	e.state.seats[0].add_to_hand(Tile.new(TileId.W5))
	for tid in range(10):
		e.state.seats[0].add_to_hand(Tile.new(TileId.T1 + tid))
	var ok := e.apply_added_kan(0, TileId.W5)
	assert_true(ok)
	assert_eq(e.state.seats[0].melds[0].kind, Meld.Kind.ADDED_KAN)
	assert_eq(e.state.seats[0].melds[0].tiles.size(), 4, "加杠 4 张")

# ---- apply_ron / apply_tsumo ----

func test_apply_ron_advances_to_settle():
	var e := _new_engine()
	e.state.phase = BattlePhase.Kind.CLAIM
	var ok := e.apply_ron(2, Tile.new(TileId.W5))
	assert_true(ok)
	assert_eq(e.state.phase, BattlePhase.Kind.SETTLE)

func test_apply_tsumo_advances_to_settle():
	var e := _new_engine()
	e.state.phase = BattlePhase.Kind.DISCARD
	var ok := e.apply_tsumo(0, Tile.new(TileId.W5))
	assert_true(ok)
	assert_eq(e.state.phase, BattlePhase.Kind.SETTLE)
