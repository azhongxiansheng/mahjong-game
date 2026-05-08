extends GutTest

# 麻将王 — 立直后强制 tsumogiri predicate 测试（spec 2026-05-08 bug 1 fix）
#
# 测 PlayableBattleController.should_auto_tsumogiri 静态 predicate；不依赖 UI
# / async / SceneTree，纯逻辑覆盖。

func _make_seat() -> Seat:
	return Seat.new(0, TileId.E)

# ---- 真表 ----

func test_riichi_declared_with_drawn_returns_true():
	var s := _make_seat()
	s.riichi.declared = true
	s.last_drawn_tile_id = TileId.W5
	assert_true(PlayableBattleController.should_auto_tsumogiri(s),
		"立直 + 有刚摸的牌 → 强制 tsumogiri")

# ---- 假表 ----

func test_no_riichi_returns_false():
	var s := _make_seat()
	s.riichi.declared = false
	s.last_drawn_tile_id = TileId.W5
	assert_false(PlayableBattleController.should_auto_tsumogiri(s),
		"未立直 → 不强制（玩家自由选）")

func test_riichi_but_no_drawn_returns_false():
	# 立直状态但 last_drawn = -1（如刚 chi/pon 后状态，但立直后不会 chi/pon）
	# 防御性：即使到达此状态也不应触发 auto-tsumogiri
	var s := _make_seat()
	s.riichi.declared = true
	s.last_drawn_tile_id = -1
	assert_false(PlayableBattleController.should_auto_tsumogiri(s),
		"立直但无刚摸的牌 → 不触发 auto（防御性）")

func test_neither_riichi_nor_drawn_returns_false():
	var s := _make_seat()
	# 默认 riichi.declared=false, last_drawn=-1
	assert_false(PlayableBattleController.should_auto_tsumogiri(s))
