extends GutTest

# 麻将王 — M10 信息系：SkillCtx reveal API 单测
# 覆盖 reveal_random_from_seat / reveal_wall_top_to / reveal_dora_indicator_to /
# reveal_next_draw_for_seat 四个新 API（替代 5 个 hook 的占位 stub）

func _setup_ctx() -> SkillCtx:
	var st := BattleState.for_east_round(42, 0, 1, 0, 0)
	var ev := BattleEvent.make(&"GAME_BEGIN", 0)
	return SkillCtx.new(st, ev)

# ---- reveal_random_from_seat ----

func test_reveal_random_from_seat_appends_one_visible_to_viewer():
	var ctx := _setup_ctx()
	var ok: bool = ctx.reveal_random_from_seat(1, 0)
	assert_true(ok, "target seat 1 hand 非空 → 应成功")
	assert_eq(ctx._state.revealed_tiles.size(), 1, "1 个 reveal 入 state")
	var entry: Dictionary = ctx._state.revealed_tiles[0]
	assert_eq(int(entry.visible_to[0]), 0, "visible_to viewer=0")

func test_reveal_random_from_seat_picks_real_tile_holder():
	var ctx := _setup_ctx()
	ctx.reveal_random_from_seat(2, 0)
	var ti: TileInstance = ctx._state.revealed_tiles[0]["tile"]
	assert_eq(ti.holder_seat, 2, "tile.holder_seat = target seat 2")
	# 真实存在 — 来自 seat 2 起手 13 张之一
	var seat_2_ids: Array = []
	for t in ctx._state.seats[2].hand._tiles:
		seat_2_ids.append(t.id)
	assert_true(ti.tile.id in seat_2_ids, "reveal 的 id 在 seat 2 真手牌内")

func test_reveal_random_from_seat_invalid_target_returns_false():
	var ctx := _setup_ctx()
	assert_false(ctx.reveal_random_from_seat(-1, 0), "无效 target 返 false")
	assert_false(ctx.reveal_random_from_seat(99, 0), "越界 target 返 false")
	assert_eq(ctx._state.revealed_tiles.size(), 0, "无效调用不污染 state")

# ---- reveal_wall_top_to ----

func test_reveal_wall_top_to_appends_n_tiles():
	var ctx := _setup_ctx()
	var n: int = ctx.reveal_wall_top_to(0, 5)
	assert_eq(n, 5, "返 5 张 reveal")
	assert_eq(ctx._state.revealed_tiles.size(), 5)
	for entry in ctx._state.revealed_tiles:
		assert_eq(int(entry.visible_to[0]), 0)
		assert_eq(int(entry["tile"].holder_seat), -1, "牌墙顶 holder=-1")

func test_reveal_wall_top_to_zero_returns_zero():
	var ctx := _setup_ctx()
	var n: int = ctx.reveal_wall_top_to(0, 0)
	assert_eq(n, 0)
	assert_eq(ctx._state.revealed_tiles.size(), 0)

func test_reveal_wall_top_to_does_not_consume_wall():
	var ctx := _setup_ctx()
	var size_before: int = ctx._state.wall.size()
	ctx.reveal_wall_top_to(0, 10)
	assert_eq(ctx._state.wall.size(), size_before, "peek 不消耗牌墙")

# ---- reveal_dora_indicator_to ----

func test_reveal_dora_indicator_to_first():
	var ctx := _setup_ctx()
	var ok: bool = ctx.reveal_dora_indicator_to(0, 0)
	assert_true(ok)
	var ti: TileInstance = ctx._state.revealed_tiles[0]["tile"]
	# wall.peek_dora_indicator(0) 应等于此牌
	assert_eq(ti.tile.id, ctx._state.wall.peek_dora_indicator(0).id,
		"reveal 的 id 与 peek_dora_indicator(0) 一致")

func test_reveal_dora_indicator_to_out_of_range():
	var ctx := _setup_ctx()
	assert_false(ctx.reveal_dora_indicator_to(0, -1))
	assert_false(ctx.reveal_dora_indicator_to(0, 5))
	assert_eq(ctx._state.revealed_tiles.size(), 0)

# ---- reveal_next_draw_for_seat ----

func test_reveal_next_draw_for_seat_returns_top_of_wall():
	var ctx := _setup_ctx()
	var expected: Tile = ctx._state.wall.peek_next_draw()
	var ok: bool = ctx.reveal_next_draw_for_seat(0, 0)
	assert_true(ok)
	var ti: TileInstance = ctx._state.revealed_tiles[0]["tile"]
	assert_eq(ti.tile.id, expected.id, "reveal 的 id 等于 next_draw")
