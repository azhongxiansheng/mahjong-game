extends GutTest

# 日麻 §6.4 岭上开花(rinshan kaihou)修复:
# 修复前 dead code:WinContext.is_rinshan / GameContext.is_rinshan 仅在测试设值,
# 生产代码从未设。导致玩家明杠/暗杠/加杠后岭上摸胡牌都丢了 +1 han 役。
# 修复方案:Seat.last_draw_is_rinshan + TurnEngine 维护 + BC._step_discard 检 tsumo


func _tile(tid: int, iid: int) -> Tile:
	return Tile.new(tid, false, Tile.NO_OWNER, iid)


# ---- Seat.last_draw_is_rinshan 默认 + 普通摸牌不触发 ----

func test_seat_last_draw_is_rinshan_defaults_false() -> void:
	var seat := Seat.new(0, TileId.E)
	assert_false(seat.last_draw_is_rinshan, "新 Seat 不应是岭上")


# TurnEngine.draw_for_current 摸普通牌 → last_draw_is_rinshan=false
func test_draw_for_current_clears_rinshan_flag() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	# 人工先设 true,模拟前轮岭上残留
	bc.state.seats[0].last_draw_is_rinshan = true
	bc.engine.draw_for_current()
	assert_false(bc.state.seats[0].last_draw_is_rinshan, "正常摸应清岭上标记")


# ---- _take_rinshan_to 触发 last_draw_is_rinshan=true ----

# 明杠后 _take_rinshan_to 应设 seat.last_draw_is_rinshan=true
func test_apply_minkan_sets_rinshan_flag() -> void:
	var bc := BattleController.new(99, 0, false, TileId.E)
	bc.state.seats[1].hand = Hand.new()
	bc.state.seats[1].hand.add(_tile(TileId.W5, 701))
	bc.state.seats[1].hand.add(_tile(TileId.W5, 702))
	bc.state.seats[1].hand.add(_tile(TileId.W5, 703))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc.state.seats[0].river.restore([_tile(TileId.W5, 700)])
	var ok: bool = bc.engine.apply_minkan(1, 700, [701, 702, 703])
	assert_true(ok, "minkan 应成立")
	assert_true(bc.state.seats[1].last_draw_is_rinshan,
		"明杠后岭上摸 → last_draw_is_rinshan=true")


# 暗杠后 _take_rinshan_to 同样设标记
func test_apply_ankan_sets_rinshan_flag() -> void:
	var bc := BattleController.new(99, 0, false, TileId.E)
	bc.state.seats[0].hand = Hand.new()
	for i in range(4):
		bc.state.seats[0].hand.add(_tile(TileId.W1, 800 + i))
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD
	var ok: bool = bc.engine.apply_ankan(0, [800, 801, 802, 803])
	assert_true(ok)
	assert_true(bc.state.seats[0].last_draw_is_rinshan,
		"暗杠后岭上摸 → last_draw_is_rinshan=true")


# ---- BC._build_game_ctx 透传 is_rinshan ----

func test_build_game_ctx_rinshan_true_when_flagged() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	var seat: Seat = bc.state.seats[0]
	var ctx = bc._build_game_ctx(seat, true, false, false, true)
	assert_true(ctx.is_rinshan, "is_rinshan=true 应传到 GameContext")


# 荣胡时(is_tsumo=false)即使 is_rinshan 传 true 也应过滤为 false
func test_build_game_ctx_rinshan_false_when_ron() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	var seat: Seat = bc.state.seats[0]
	var ctx = bc._build_game_ctx(seat, false, false, false, true)
	assert_false(ctx.is_rinshan, "荣胡路径下岭上无意义,应被强制 false")


# ---- _check_tsumo 透传 is_rinshan 到 yaku ----

# _check_tsumo 加 is_rinshan 参数后,非 rinshan 默认 false
func test_check_tsumo_default_no_rinshan() -> void:
	# 用一个能轻松构造听牌的 seat 不容易,这里 indirect 验:
	# _check_tsumo(drawn) 不传 is_rinshan → 内部 _build_game_ctx 收到 false
	# 通过看返回结构是否含 wp 来确认未崩。具体 yaku 验在 yaku/test_rinshan.gd 里。
	var bc := BattleController.new(42, 0, false, TileId.E)
	# 构造一个 noop drawn,既不胡也不崩
	var drawn := _tile(TileId.W1, 900)
	# seat 手空,无法胡 — 应返 is_winning=false
	bc.state.seats[0].hand = Hand.new()
	bc.state.seats[0].hand.add(drawn)
	var result = bc._check_tsumo(drawn, false, false)
	assert_false(result.get("is_winning", true), "非胡牌手应返 is_winning=false")
