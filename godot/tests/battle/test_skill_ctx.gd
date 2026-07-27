extends GutTest

func _make_state() -> BattleState:
	return BattleState.new()

func _make_event() -> BattleEvent:
	return BattleEvent.make(&"WIN_DECLARED", 0)

func test_add_han_accumulates_in_han_deltas():
	var ctx := SkillCtx.new(_make_state(), _make_event())
	ctx.add_han(0, 1)
	ctx.add_han(0, 2)
	assert_eq(ctx.han_deltas.get(0, 0), 3)

func test_cancel_ron_writes_state():
	var st := _make_state()
	var ctx := SkillCtx.new(st, _make_event())
	ctx.cancel_ron(2)
	assert_true(st.ron_cancelled[2])

func test_steal_score_transfers_fraction():
	var st := _make_state()
	st.scores[1] = 8000
	st.scores[0] = 25000
	var ctx := SkillCtx.new(st, _make_event())
	ctx.steal_score(1, 0, 0.3)
	assert_eq(st.scores[1], 8000 - 2400)
	assert_eq(st.scores[0], 25000 + 2400)

func test_reveal_tile_to_appends_entry():
	var st := _make_state()
	var ti := TileSkillAnchor.make(Tile.new(TileId.W1), 0)
	var ctx := SkillCtx.new(st, _make_event())
	ctx.reveal_tile_to(ti, 1)
	assert_eq(st.revealed_tiles.size(), 1)
	assert_eq(st.revealed_tiles[0]["tile"], ti)
	assert_true(st.revealed_tiles[0]["visible_to"].has(1))

func test_clear_furiten_writes_state():
	var st := _make_state()
	st.furiten_flags[0] = true
	var ctx := SkillCtx.new(st, _make_event())
	ctx.clear_furiten(0)
	assert_false(st.furiten_flags[0])

func test_force_tsumo_writes_state():
	var st := _make_state()
	var ctx := SkillCtx.new(st, _make_event())
	ctx.force_tsumo(2)
	assert_eq(st.haitei_forced_seat, 2)

func test_get_score_reads_state():
	var st := _make_state()
	var ctx := SkillCtx.new(st, _make_event())
	assert_eq(ctx.get_score(0), 25000)

func test_is_furiten_reads_state():
	var st := _make_state()
	st.furiten_flags[3] = true
	var ctx := SkillCtx.new(st, _make_event())
	assert_true(ctx.is_furiten(3))
	assert_false(ctx.is_furiten(0))

func test_get_event_returns_input():
	var ev := _make_event()
	var ctx := SkillCtx.new(_make_state(), ev)
	assert_eq(ctx.get_event(), ev)
