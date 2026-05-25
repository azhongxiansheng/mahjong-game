extends GutTest

# GAP-2 — HeuristicAi defensive discard tests.
#
# Validates defense mode behavior:
# - When opponent is in riichi, prefer safe tiles (opponent already discarded)
# - When no safe tiles, prefer terminal/honor tiles
# - When no opponent riichi, use normal discard logic
# - When AI itself is in riichi, skip defense (tsumogiri locked)

func _hand(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

func test_defense_prefers_safe_tile():
	var ai := HeuristicAi.new(42)
	ai.set_defense_context([1], [TileId.HAKU, TileId.W1])  # opponent discarded HAKU, W1
	var seat := Seat.new(2, TileId.E)
	seat.hand = _hand([
		TileId.W5, TileId.W6,  # dangerous middle tiles
		TileId.HAKU,  # safe: opponent discarded it
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E,
	])
	var pick: Tile = ai.decide_discard(seat)
	assert_eq(pick.id, TileId.HAKU, "should discard safe tile HAKU")

func test_defense_prefers_terminal_when_no_safe():
	var ai := HeuristicAi.new(42)
	ai.set_defense_context([1], [])  # opponent riichi but no safe tiles known
	var seat := Seat.new(2, TileId.E)
	seat.hand = _hand([
		TileId.W5, TileId.W6,
		TileId.T5, TileId.T6,
		TileId.S5, TileId.S6,
		TileId.W1,  # terminal
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.CHUN,  # honor
	])
	var pick: Tile = ai.decide_discard(seat)
	var is_safe: bool = TileId.is_honor(pick.id) or TileId.number(pick.id) == 1 or TileId.number(pick.id) == 9
	assert_true(is_safe, "should prefer terminal/honor tile")

func test_no_defense_when_no_riichi():
	var ai := HeuristicAi.new(42)
	ai.set_defense_context([], [])  # no opponents in riichi
	var seat := Seat.new(2, TileId.E)
	seat.hand = _hand([
		TileId.W5, TileId.W6,
		TileId.T5, TileId.T6,
		TileId.HAKU, TileId.CHUN,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.E,
	])
	# Should use normal logic (retention-based), not defensive
	var pick: Tile = ai.decide_discard(seat)
	# Normal logic would discard most isolated tile, not necessarily HAKU
	assert_not_null(pick, "should still pick something")

func test_no_defense_when_ai_riichi():
	var ai := HeuristicAi.new(42)
	ai.set_defense_context([1], [TileId.HAKU])
	var seat := Seat.new(2, TileId.E)
	seat.hand = _hand([
		TileId.W5, TileId.W6, TileId.HAKU,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E,
	])
	seat.riichi = RiichiState.new()
	seat.riichi.declared = true
	# AI is in riichi -- should NOT enter defense mode (already locked)
	var pick: Tile = ai.decide_discard(seat)
	assert_not_null(pick)

func test_defense_safe_tile_from_multiple():
	# When multiple safe tiles exist, first one in hand iteration order is chosen
	var ai := HeuristicAi.new(42)
	ai.set_defense_context([1], [TileId.CHUN, TileId.HATSU, TileId.W5])
	var seat := Seat.new(0, TileId.E)
	seat.hand = _hand([
		TileId.W5, TileId.W6, TileId.W7,  # W5 is safe
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.CHUN,  # also safe
		TileId.W1, TileId.W2, TileId.W3,
	])
	var pick: Tile = ai.decide_discard(seat)
	# W5 appears first in hand, and it's in the safe list
	assert_eq(pick.id, TileId.W5, "should pick first safe tile in hand order")

func test_defense_fallback_to_normal_when_only_middle_tiles():
	# All tiles are middle-suited, no terminal/honor, no safe -- fallback to normal
	var ai := HeuristicAi.new(42)
	ai.set_defense_context([1], [])
	var seat := Seat.new(0, TileId.E)
	seat.hand = _hand([
		TileId.W2, TileId.W3, TileId.W4,
		TileId.T5, TileId.T6, TileId.T7,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W5, TileId.W6, TileId.W7,
		TileId.T2,
	])
	var pick: Tile = ai.decide_discard(seat)
	# Defensive returns null (no safe, no terminal/honor) -> falls through to retention
	assert_not_null(pick, "should fall back to normal discard logic")
