extends GutTest

# 麻将王 — 立直后强制 tsumogiri predicate 测试（spec 2026-05-08 bug 1 fix）
# E2-02 / #232：只认 seat.last_drawn_instance_id。
#
# 测 PlayableBattleController.should_auto_tsumogiri 静态 predicate；不依赖 UI
# / async / SceneTree，纯逻辑覆盖。

func _make_seat() -> Seat:
	return Seat.new(0, TileId.E)

# ---- 真表 ----

func test_riichi_declared_with_drawn_instance_returns_true():
	var s := _make_seat()
	s.riichi.declared = true
	s.last_drawn_instance_id = 1001
	assert_true(PlayableBattleController.should_auto_tsumogiri(s),
		"立直 + 有刚摸实体 → 强制 tsumogiri")

# ---- 假表 ----

func test_no_riichi_returns_false():
	var s := _make_seat()
	s.riichi.declared = false
	s.last_drawn_instance_id = 1001
	assert_false(PlayableBattleController.should_auto_tsumogiri(s),
		"未立直 → 不强制（玩家自由选）")

func test_riichi_but_invalid_drawn_instance_returns_false():
	# 立直状态但 last_drawn_instance_id = INVALID（如刚 chi/pon 后状态）
	var s := _make_seat()
	s.riichi.declared = true
	s.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
	assert_false(PlayableBattleController.should_auto_tsumogiri(s),
		"立直但无刚摸实体 → 不触发 auto")

func test_neither_riichi_nor_drawn_returns_false():
	var s := _make_seat()
	# 默认 riichi.declared=false, last_drawn_instance_id=INVALID
	assert_false(PlayableBattleController.should_auto_tsumogiri(s))


func test_auto_tsumogiri_discard_uses_exact_drawn_instance() -> void:
	# 同值两张时必须摸切刚摸实体，不得按 tile_id 拿第一张
	var bc := PlayableBattleController.new(3, 0, false)
	bc.set_ai_think_delay(0.0)
	var seat: Seat = bc.state.seats[0]
	var tiles: Array[Tile] = [
		Tile.new(TileId.W5, false, 0, 10),
		Tile.new(TileId.W5, true, 0, 11),  # 刚摸赤
	]
	for tid in [TileId.W1, TileId.W2, TileId.W3, TileId.T1, TileId.T2, TileId.T3,
			TileId.S1, TileId.S2, TileId.S3, TileId.E, TileId.S_WIND, TileId.N]:
		tiles.append(Tile.new(tid, false, 0, 100 + tid))
	assert_true(seat.hand.restore_tiles(tiles))
	seat.riichi.declared = true
	seat.last_drawn_instance_id = 11

	assert_true(PlayableBattleController.should_auto_tsumogiri(seat))
	var picked: Tile = await bc._get_discard_decision(seat, 0)
	assert_not_null(picked)
	assert_eq(picked.instance_id, 11, "摸切精确实体 11（赤 5）")
	assert_true(picked.is_red_dora)
	assert_ne(picked.instance_id, 10, "禁止按 tile_id 自动拿第一张黑 5")
