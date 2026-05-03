extends GutTest

# 麻将王 — M7 平衡：HeuristicAi.decide_riichi 单测 + BC 集成。

func _make_seat_with_hand(ids: Array, points: int = 25000) -> Seat:
	var s := Seat.new(0, TileId.E, points)
	s.hand._tiles.clear()
	for tid in ids:
		s.hand.add(Tile.new(tid))
	return s

# 七対子听 W9 单骑（13 tiles）
func _chiitoi_tenpai_hand() -> Array:
	return [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9,
	]

# ---- decide_riichi 行为 ----

func test_riichi_yes_when_tenpai_and_concealed():
	var ai := HeuristicAi.new(0)
	var seat := _make_seat_with_hand(_chiitoi_tenpai_hand())
	assert_true(ai.decide_riichi(seat, 20), "听牌门清 + wall 充足 → 立直")

func test_riichi_no_when_already_declared():
	var ai := HeuristicAi.new(0)
	var seat := _make_seat_with_hand(_chiitoi_tenpai_hand())
	seat.riichi.declared = true
	assert_false(ai.decide_riichi(seat, 20))

func test_riichi_no_when_wall_too_small():
	var ai := HeuristicAi.new(0)
	var seat := _make_seat_with_hand(_chiitoi_tenpai_hand())
	# 立直 spec：剩余 ≥ 4 张才可立直
	assert_false(ai.decide_riichi(seat, 3))

func test_riichi_no_when_below_min_points():
	var ai := HeuristicAi.new(0)
	var seat := _make_seat_with_hand(_chiitoi_tenpai_hand(), 500)
	assert_false(ai.decide_riichi(seat, 20), "< 1000 点不能立直")

func test_riichi_no_when_not_tenpai():
	var ai := HeuristicAi.new(0)
	# 13 张完全无序
	var seat := _make_seat_with_hand([
		TileId.W1, TileId.W2, TileId.W3, TileId.T1, TileId.T2,
		TileId.T3, TileId.S1, TileId.S2, TileId.S3, TileId.E,
		TileId.S_WIND, TileId.W_WIND, TileId.N,
	])
	assert_false(ai.decide_riichi(seat, 20))

# ---- BattleController 集成：AI 立直 + RIICHI_DECLARED emit + state.scores 扣 1000 ----

class _ForceTenpaiAi extends HeuristicAi:
	# 让 seat 0 弃完 W9 后保持 tenpai
	func decide_discard(seat: Seat) -> Tile:
		# 优先弃手牌中第 1 张非"七对子骨架"牌（非 W9）
		# 实际 fixture 里 hand 已设为 14 张听牌 + drawn 一张多余的，弃多余即可
		for t in seat.hand._tiles:
			if t.id == TileId.E or t.id == TileId.S_WIND:
				return t
		# fallback：弃最后一张
		return seat.hand._tiles[seat.hand._tiles.size() - 1]

func test_battle_controller_emits_riichi_declared_when_tenpai_and_heuristic():
	var bc := BattleController.new(42, 0, true)  # use_heuristic_ai
	bc.ai = _ForceTenpaiAi.new(0)
	# seat 0 hand：13 张七対子 + 1 张 E（多余可弃）
	var seat0: Seat = bc.state.seats[0]
	seat0.hand._tiles.clear()
	for tid in [
		TileId.W1, TileId.W1, TileId.W2, TileId.W2, TileId.W3, TileId.W3,
		TileId.W5, TileId.W5, TileId.W6, TileId.W6, TileId.W7, TileId.W7,
		TileId.W9, TileId.E,  # E 是多余，会被 _ForceTenpaiAi 弃
	]:
		seat0.hand.add(Tile.new(tid))
	# 把 wall 顶设为不胡牌（避免 seat 0 自摸跳过 discard）
	bc.state.wall._tiles[bc.state.wall._draw_index] = Tile.new(TileId.S5)
	# 跳 _step_draw 直接走 discard：把 phase 设到 DISCARD
	bc.state.phase = BattlePhase.Kind.DISCARD

	bc._step_discard()

	# 应当 emit RIICHI_DECLARED
	var has_riichi := false
	for ev in bc.events:
		if ev.type == &"RIICHI_DECLARED":
			has_riichi = true
			assert_eq(ev.actor_seat, 0)
	assert_true(has_riichi, "立直应 emit RIICHI_DECLARED")
	# state.scores 应扣 1000
	assert_eq(bc.state.scores[0], 25000 - 1000, "立直扣 1000 点同步到 state.scores")
	assert_eq(bc.state.riichi_sticks, 1, "立直棒 +1")
	assert_true(seat0.riichi.declared)
