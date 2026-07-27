extends GutTest

# 麻将王 — M10 Path A：HeuristicAi shanten-aware 弃牌单测
#
# 验证 use_shanten_aware_discard = true 时：
# - 14 张 hand（post-draw）走 shanten 选弃牌
# - 不饱满 hand 仍走 retention fallback
# - 选弃使 shanten 不上升的；同 shanten 时 tie-break 走 retention（孤立优先）

func _make_seat_with_hand(ids: Array, melds: Array = []) -> Seat:
	var s := Seat.new(0, TileId.E)
	s.hand = Hand.new()
	for tid in ids:
		s.hand.add(Tile.new(tid))
	for meld in melds:
		assert_true(s.melds.add_existing(meld))
	return s

# ---- 默认关闭：行为同 M7 ----

func test_default_off_uses_retention():
	# 默认 use_shanten_aware_discard = false，行为同 M7 retention
	var ai := HeuristicAi.new(0)
	assert_false(ai.use_shanten_aware_discard, "默认关闭")
	# W2 W2 + 字牌 E（孤立）→ 弃 E
	var seat := _make_seat_with_hand([TileId.W2, TileId.W2, TileId.E])
	assert_eq(ai.decide_discard(seat).id, TileId.E, "默认 retention 弃孤立字牌")

# ---- 开启 shanten ----

func test_shanten_picks_discard_minimizing_shanten():
	# 14 张：234m 234p 234s 234s + 5m + 中 → 候选弃牌：
	# - 弃 5m → 13 张 234m 234p 234s 234s 中（4 mentsu + 单中）= tenpai 0-shanten
	# - 弃中 → 13 张 234m 234p 234s 234s 5m（4 mentsu + 单 5m）= tenpai 0-shanten
	# 两选都 0-shanten；tie-break 走 retention（5m 邻居多 / 中 字牌孤立 → 弃 中）
	var ai := HeuristicAi.new(0)
	ai.use_shanten_aware_discard = true
	var seat := _make_seat_with_hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7, TileId.S8,
		TileId.W5, TileId.CHUN,
	])
	var pick := ai.decide_discard(seat)
	assert_eq(pick.id, TileId.CHUN, "0-shanten tie-break：弃孤立字牌中")

func test_shanten_avoids_breaking_tenpai():
	# 14 张：234m 234p 234s 67s + 5w 5w + 中
	# 弃 中 → 13 张：234m 234p 234s 67s 5w 5w = tenpai 0-shanten 听 5s/8s
	# 弃 5w → 13 张：234m 234p 234s 67s 5w 中 = 1-shanten（雀头丢失）
	# 弃 67s 之一 → 1-shanten
	# 应弃 中（保 tenpai）
	var ai := HeuristicAi.new(0)
	ai.use_shanten_aware_discard = true
	var seat := _make_seat_with_hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7,
		TileId.W5, TileId.W5,
		TileId.CHUN,
	])
	var pick := ai.decide_discard(seat)
	assert_eq(pick.id, TileId.CHUN, "shanten 优先：弃中保 tenpai")

func test_shanten_falls_back_to_retention_on_partial_hand():
	# 不饱满 hand（< 14 张）走 retention，与 M7 同
	var ai := HeuristicAi.new(0)
	ai.use_shanten_aware_discard = true
	var seat := _make_seat_with_hand([TileId.W5, TileId.W5, TileId.E])  # 3 张
	var pick := ai.decide_discard(seat)
	# retention：W5 对子高分；E 字牌孤立低分 → 弃 E
	assert_eq(pick.id, TileId.E, "不饱满 hand 走 retention fallback")

func test_shanten_ai_respects_called_meld_size():
	# 已副露 1 chi → 暗 11 张为饱满（11 = 14 - 3）。
	# 11 张 hand：234p 234s 67s 5w 5w 中 = 副露后正在等弃 1 张
	# 弃中 → 暗 10 张 = 听 5s/8s（standard tenpai with 1 副露）= 0-shanten
	# 弃 5w 之一 → 1-shanten
	# 应弃 中
	var ai := HeuristicAi.new(0)
	ai.use_shanten_aware_discard = true
	var chi: Meld = Meld.make_chi(
		[Tile.new(TileId.W2), Tile.new(TileId.W3), Tile.new(TileId.W4)], 3)
	var seat := _make_seat_with_hand([
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.S6, TileId.S7,
		TileId.W5, TileId.W5,
		TileId.CHUN,
	], [chi])
	var pick := ai.decide_discard(seat)
	assert_eq(pick.id, TileId.CHUN, "副露 1 chi 后 11 张 = 饱满，shanten 选弃")

# ---- 性能 sanity ----

func test_shanten_decision_completes_quickly():
	# 14 张 hand 单次 shanten 决策 < 100 ms（GUT 性能 sanity）
	var ai := HeuristicAi.new(0)
	ai.use_shanten_aware_discard = true
	var seat := _make_seat_with_hand([
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T4, TileId.T5, TileId.T6,
		TileId.S7, TileId.S8, TileId.S9,
		TileId.E, TileId.E,
		TileId.HAKU, TileId.HATSU, TileId.CHUN,
	])
	var t0: int = Time.get_ticks_msec()
	ai.decide_discard(seat)
	var elapsed: int = Time.get_ticks_msec() - t0
	assert_true(elapsed < 100, "shanten 决策 < 100ms（实测 %d ms）" % elapsed)
