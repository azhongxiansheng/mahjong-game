extends GutTest

# 日麻 §6.6 天和(tenhou) / 地和(chiihou) / 修复前 dead code:
# is_dealer_first_hand / is_non_dealer_first_draw 在生产代码中从未被设值
# → 役満永不命中。修:BC._step_draw / _step_draw_async 算 first-hand 标志
# 透传到 _check_tsumo → _build_game_ctx → GameContext。本测试只验透传链路,
# 不验完整 tsumo 流(那需要构造真实可胡的 14 张配牌,留 yaku/test_tenhou
# 单元测试)。


# _build_game_ctx 透传 is_tenhou=true 到 GameContext.is_dealer_first_hand
func test_build_ctx_tenhou_flag_propagates() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	var seat: Seat = bc.state.seats[0]
	var ctx = bc._build_game_ctx(seat, true, false, false, false, true, false)
	assert_true(ctx.is_dealer_first_hand, "is_tenhou=true 应进 ctx")


# _build_game_ctx 透传 is_chiihou=true 到 GameContext.is_non_dealer_first_draw
func test_build_ctx_chiihou_flag_propagates() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	var seat: Seat = bc.state.seats[1]
	var ctx = bc._build_game_ctx(seat, true, false, false, false, false, true)
	assert_true(ctx.is_non_dealer_first_draw, "is_chiihou=true 应进 ctx")


# 荣胡路径 is_tsumo=false → 即使 is_tenhou 传 true 也应 false(天和只能 tsumo)
func test_tenhou_false_on_ron_path() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	var seat: Seat = bc.state.seats[0]
	var ctx = bc._build_game_ctx(seat, false, false, false, false, true, false)
	assert_false(ctx.is_dealer_first_hand, "荣胡路径下 tenhou 应强制 false")


# 默认参数(都不传 first-hand 标志)→ ctx 两 flag 都是 false
func test_default_no_first_hand_flags() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	var seat: Seat = bc.state.seats[0]
	var ctx = bc._build_game_ctx(seat, true)
	assert_false(ctx.is_dealer_first_hand)
	assert_false(ctx.is_non_dealer_first_draw)
