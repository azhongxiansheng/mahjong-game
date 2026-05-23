extends GutTest

# 日麻 §3.2 三种途中流局接入 BattleController 主循环验证。
# 九種九牌走 _step_draw_async 单独路径(已由 test_kyuusyu_kyuuhai_flow 覆盖),
# 本文件聚焦剩余 3 种由 _check_and_emit_abortive_draws 处理的:
#   - 四风连打(suufon renda):第一巡 4 家弃同一字风牌
#   - 四家立直(suucha riichi):4 家全部宣告立直
#   - 四杠散了(suukantsu sanra):4 杠成立且至少 2 人参与


func _make_bc() -> BattleController:
	return BattleController.new(42, 0, false, TileId.E)


# 四风连打:第一巡内 4 家都弃了同一张字风牌 → 命中
func test_suufon_renda_triggers_abortive_draw() -> void:
	var bc := _make_bc()
	# 强制 state.first_round_active = true,然后每家 discards 第一张都是东风
	bc.state.first_round_active = true
	for seat_id in range(4):
		bc.state.discards_per_seat[seat_id] = [Tile.new(TileId.E)]

	bc._check_and_emit_abortive_draws()

	assert_true(bc._settled, "命中四风连打应 settle")
	var last: BattleEvent = bc.events[bc.events.size() - 1]
	assert_eq(last.type, &"ABORTIVE_DRAW")
	assert_eq(String(last.extra.get("reason", "")), "suufon_renda")


# 四风连打:4 家弃牌不同风 → 不命中
func test_suufon_renda_mixed_winds_no_trigger() -> void:
	var bc := _make_bc()
	bc.state.first_round_active = true
	bc.state.discards_per_seat[0] = [Tile.new(TileId.E)]
	bc.state.discards_per_seat[1] = [Tile.new(TileId.S_WIND)]
	bc.state.discards_per_seat[2] = [Tile.new(TileId.E)]
	bc.state.discards_per_seat[3] = [Tile.new(TileId.E)]

	bc._check_and_emit_abortive_draws()

	assert_false(bc._settled, "风不一致不应 settle")


# 四风连打:非字风牌(数牌)即使 4 家一致也不应触发
func test_suufon_renda_non_wind_no_trigger() -> void:
	var bc := _make_bc()
	bc.state.first_round_active = true
	for seat_id in range(4):
		bc.state.discards_per_seat[seat_id] = [Tile.new(TileId.W1)]

	bc._check_and_emit_abortive_draws()

	assert_false(bc._settled, "数牌不应触发四风")


# 四风连打:非第一巡(first_round_active=false)即使 4 家弃相同风也不应触发
func test_suufon_renda_after_first_round_no_trigger() -> void:
	var bc := _make_bc()
	bc.state.first_round_active = false  # 已过第一巡
	for seat_id in range(4):
		bc.state.discards_per_seat[seat_id] = [Tile.new(TileId.E)]

	bc._check_and_emit_abortive_draws()

	assert_false(bc._settled, "非第一巡不应触发四风")


# 四家立直:4 家全部 declared → 命中
func test_suucha_riichi_triggers_abortive_draw() -> void:
	var bc := _make_bc()
	for seat in bc.state.seats:
		seat.riichi.declared = true

	bc._check_and_emit_abortive_draws()

	assert_true(bc._settled, "4 家全立直应 settle")
	var last: BattleEvent = bc.events[bc.events.size() - 1]
	assert_eq(last.type, &"ABORTIVE_DRAW")
	assert_eq(String(last.extra.get("reason", "")), "suucha_riichi")


# 四家立直:仅 3 家立直 → 不命中
func test_suucha_riichi_three_only_no_trigger() -> void:
	var bc := _make_bc()
	for i in range(3):
		bc.state.seats[i].riichi.declared = true

	bc._check_and_emit_abortive_draws()

	assert_false(bc._settled, "仅 3 家立直不应 settle")


# 四杠散了:4 杠跨 ≥2 人 → 命中
func test_suukantsu_sanra_triggers_abortive_draw() -> void:
	var bc := _make_bc()
	# seat 0 暗杠 2 个(萬 1 / 萬 9),seat 1 暗杠 1 个(筒 5),seat 2 暗杠 1 个(索 9)
	var seats = bc.state.seats
	seats[0].melds.append(Meld.make_ankan(
		[Tile.new(TileId.W1), Tile.new(TileId.W1),
		Tile.new(TileId.W1), Tile.new(TileId.W1)]))
	seats[0].melds.append(Meld.make_ankan(
		[Tile.new(TileId.W9), Tile.new(TileId.W9),
		Tile.new(TileId.W9), Tile.new(TileId.W9)]))
	seats[1].melds.append(Meld.make_ankan(
		[Tile.new(TileId.T5), Tile.new(TileId.T5),
		Tile.new(TileId.T5), Tile.new(TileId.T5)]))
	seats[2].melds.append(Meld.make_ankan(
		[Tile.new(TileId.S9), Tile.new(TileId.S9),
		Tile.new(TileId.S9), Tile.new(TileId.S9)]))

	bc._check_and_emit_abortive_draws()

	assert_true(bc._settled, "4 杠跨多家应 settle")
	var last: BattleEvent = bc.events[bc.events.size() - 1]
	assert_eq(last.type, &"ABORTIVE_DRAW")
	assert_eq(String(last.extra.get("reason", "")), "suukantsu_sanra")


# 四杠散了:同 1 人 4 杠 → 不命中(那是四杠子役満,不是流局)
func test_suukantsu_sanra_all_one_seat_no_trigger() -> void:
	var bc := _make_bc()
	var s0: Seat = bc.state.seats[0]
	# 同一 seat 4 个暗杠
	for tid in [TileId.W1, TileId.W9, TileId.T5, TileId.S9]:
		s0.melds.append(Meld.make_ankan(
			[Tile.new(tid), Tile.new(tid), Tile.new(tid), Tile.new(tid)]))

	bc._check_and_emit_abortive_draws()

	assert_false(bc._settled, "同 1 人 4 杠不应 settle(那是役満)")


# 四杠散了:3 杠 → 不命中
func test_suukantsu_sanra_three_kans_no_trigger() -> void:
	var bc := _make_bc()
	var seats = bc.state.seats
	seats[0].melds.append(Meld.make_ankan(
		[Tile.new(TileId.W1), Tile.new(TileId.W1),
		Tile.new(TileId.W1), Tile.new(TileId.W1)]))
	seats[1].melds.append(Meld.make_ankan(
		[Tile.new(TileId.T5), Tile.new(TileId.T5),
		Tile.new(TileId.T5), Tile.new(TileId.T5)]))
	seats[2].melds.append(Meld.make_ankan(
		[Tile.new(TileId.S9), Tile.new(TileId.S9),
		Tile.new(TileId.S9), Tile.new(TileId.S9)]))

	bc._check_and_emit_abortive_draws()

	assert_false(bc._settled, "3 杠不应触发四杠")


# 三种条件都不命中 → bc 保持未 settle
func test_no_abortive_condition_keeps_state() -> void:
	var bc := _make_bc()
	bc._check_and_emit_abortive_draws()
	assert_false(bc._settled, "无任何条件命中不应 settle")
	# 不应 emit ABORTIVE_DRAW
	for ev in bc.events:
		assert_ne(ev.type, &"ABORTIVE_DRAW", "无条件不应 emit ABORTIVE_DRAW")
