extends GutTest

# 日麻 §6.4 一発(ippatsu)生命周期 — 修复前 bug:declare 设 ippatsu_window=true
# 后从未关闭,所有立直胡都错领 +1 han。本测试 cover:
#   1. TurnEngine.apply_chi/pon/minkan/ankan/added_kan → 关所有座位窗口
#   2. BattleController._close_ippatsu_if_lap_passed → 立直后下一巡自家弃牌关窗
#   3. tsumo on next own draw 时窗口仍 open(允许一発)
#   4. 同巡 declare 后的弃牌不应关窗(刚 declare,还在 declare_turn)


func _tile(tid: int, iid: int) -> Tile:
	return Tile.new(tid, false, Tile.NO_OWNER, iid)


# Helper:发牌一张构造立直前状态
func _bc_with_seat_riichi(seat_id: int, declared_turn: int = 0) -> BattleController:
	var bc := BattleController.new(99, 0, false, TileId.E)
	bc.state.turn_count = declared_turn
	bc.state.seats[seat_id].riichi.declare(declared_turn, false)
	return bc


# ---- TurnEngine 鸣牌关窗（真实成功实体路径）----

func test_apply_chi_clears_all_ippatsu_windows() -> void:
	var bc := _bc_with_seat_riichi(0)
	assert_true(bc.state.seats[0].riichi.ippatsu_window, "前置:seat0 一発开")
	# seat1 吃 seat0 河末 W1；companions W2/W3 唯一实体
	bc.state.seats[1].hand = Hand.new()
	bc.state.seats[1].hand.add(_tile(TileId.W2, 501))
	bc.state.seats[1].hand.add(_tile(TileId.W3, 502))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc.state.discards_per_seat[0] = [_tile(TileId.W1, 500)]
	var ok: bool = bc.engine.apply_chi(1, 500, [501, 502])
	assert_true(ok, "chi 应成立")
	assert_false(bc.state.seats[0].riichi.ippatsu_window, "chi 后 seat0 一発关")


# 直接构造 chi:把 W2/W3 注入 seat1 手,弃 W1 给 seat0 弃牌堆,然后调 apply_chi
func test_apply_chi_via_state_clears_window() -> void:
	var bc := _bc_with_seat_riichi(2)
	bc.state.seats[1].hand = Hand.new()
	bc.state.seats[1].hand.add(_tile(TileId.W2, 511))
	bc.state.seats[1].hand.add(_tile(TileId.W3, 512))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc.state.discards_per_seat[0] = [_tile(TileId.W1, 510)]
	# claimant 是下家 seat 1,日麻规定只能从上家吃 — seat1 上家=seat0 ✓
	var ok: bool = bc.engine.apply_chi(1, 510, [511, 512])
	assert_true(ok, "chi 应成立")
	assert_false(bc.state.seats[2].riichi.ippatsu_window, "chi 后 seat2 一発应关")


# 暗杠也关一発(国际标准日麻 §6.4)
func test_apply_ankan_clears_own_ippatsu() -> void:
	var bc := _bc_with_seat_riichi(0)
	bc.state.seats[0].hand = Hand.new()
	for i in range(4):
		bc.state.seats[0].hand.add(_tile(TileId.W1, 800 + i))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	var ok: bool = bc.engine.apply_ankan(0, [800, 801, 802, 803])
	assert_true(ok, "ankan 应成立")
	assert_false(bc.state.seats[0].riichi.ippatsu_window,
		"暗杠也关自家一発(国际日麻规则)")


# pon 关所有人的窗口
func test_apply_pon_clears_all_windows() -> void:
	var bc := _bc_with_seat_riichi(3)
	bc.state.seats[1].hand = Hand.new()
	bc.state.seats[1].hand.add(_tile(TileId.T5, 601))
	bc.state.seats[1].hand.add(_tile(TileId.T5, 602))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc.state.discards_per_seat[0] = [_tile(TileId.T5, 600)]
	var ok: bool = bc.engine.apply_pon(1, 600, [601, 602])
	assert_true(ok, "pon 应成立")
	assert_false(bc.state.seats[3].riichi.ippatsu_window, "pon 关 seat3 窗口")


# ---- BattleController 自家弃牌关窗 ----

# 在同一 declare-turn 内的弃牌不关窗(刚 declare,该巡还有效)
func test_close_lap_passed_keeps_open_in_same_turn() -> void:
	var bc := _bc_with_seat_riichi(0, 0)
	bc.state.turn_count = 0  # declared_turn == turn_count
	bc._close_ippatsu_if_lap_passed(bc.state.seats[0])
	assert_true(bc.state.seats[0].riichi.ippatsu_window, "同巡内不关窗")


# 立直后过了一巡(turn_count 推进 1)→ 关窗
func test_close_lap_passed_closes_after_lap() -> void:
	var bc := _bc_with_seat_riichi(0, 0)
	bc.state.turn_count = 1  # 已过一巡
	bc._close_ippatsu_if_lap_passed(bc.state.seats[0])
	assert_false(bc.state.seats[0].riichi.ippatsu_window,
		"过一巡后自家弃牌关窗")


# 未立直 seat 调用 helper 不报错
func test_close_lap_passed_skips_non_riichi() -> void:
	var bc := BattleController.new(99, 0, false, TileId.E)
	# seat 0 未声立直,ippatsu_window=false
	bc._close_ippatsu_if_lap_passed(bc.state.seats[0])
	assert_false(bc.state.seats[0].riichi.ippatsu_window, "未立直保持 false")
	assert_false(bc.state.seats[0].riichi.declared)


# 立直但窗口已关(被鸣牌关掉),helper 不重复关
func test_close_lap_passed_skips_already_closed() -> void:
	var bc := _bc_with_seat_riichi(0, 0)
	bc.state.seats[0].riichi.consume_ippatsu()  # 模拟被鸣牌关掉
	bc.state.turn_count = 1
	bc._close_ippatsu_if_lap_passed(bc.state.seats[0])
	assert_false(bc.state.seats[0].riichi.ippatsu_window, "已关保持关")


# ---- ippatsu_window 决定 ScoreCtx is_ippatsu 的旧路径仍 work ----

# 立直成立时窗口开;若该巡内 tsumo,_build_game_ctx 应注入 is_ippatsu=true
func test_build_game_ctx_passes_ippatsu_when_window_open() -> void:
	var bc := _bc_with_seat_riichi(0, 0)
	assert_true(bc.state.seats[0].riichi.ippatsu_window, "前置:窗口开")
	# 直接构造 game ctx 验:
	var seat: Seat = bc.state.seats[0]
	var ctx = bc._build_game_ctx(seat, true, false, false)
	assert_true(ctx.is_ippatsu, "窗口开 → ctx.is_ippatsu=true")


# 窗口关时 ctx.is_ippatsu 应 false
func test_build_game_ctx_no_ippatsu_when_window_closed() -> void:
	var bc := _bc_with_seat_riichi(0, 0)
	bc.state.seats[0].riichi.consume_ippatsu()
	var seat: Seat = bc.state.seats[0]
	var ctx = bc._build_game_ctx(seat, true, false, false)
	assert_false(ctx.is_ippatsu, "窗口关 → ctx.is_ippatsu=false")
