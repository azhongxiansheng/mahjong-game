extends GutTest

func _hand(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

func _seat_with_hand(ids: Array, seat_id: int = 1) -> Seat:
	var s := Seat.new(seat_id, TileId.E)
	s.hand = _hand(ids)
	return s

# ---- decide_claim_for_seat ----

func test_ai_pons_when_has_pair():
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E,
	])
	var result: Dictionary = ai.decide_claim_for_seat(seat, TileId.W5, 0)
	assert_eq(result.get("kind", ""), "pon", "should pon with pair")

func test_ai_skips_when_no_pair():
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E, TileId.S5,
	])
	var result: Dictionary = ai.decide_claim_for_seat(seat, TileId.W5, 0)
	assert_true(result.is_empty(), "should skip (empty dict)")

func test_ai_skips_self_discard():
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E,
	], 0)
	var result: Dictionary = ai.decide_claim_for_seat(seat, TileId.W5, 0)
	assert_true(result.is_empty(), "cannot claim own discard")

func test_ai_minkan_when_has_triplet():
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W5, TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E,
	])
	var result: Dictionary = ai.decide_claim_for_seat(seat, TileId.W5, 0)
	assert_eq(result.get("kind", ""), "minkan", "should minkan with triplet")

# ---- decide_self_kan ----

func test_ai_ankan_when_has_four():
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W5, TileId.W5, TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E,
	])
	var result: Dictionary = ai.decide_self_kan(seat)
	assert_eq(result.get("kind", ""), "ankan")
	assert_eq(result.get("tile_id", -1), TileId.W5)

func test_ai_added_kan_when_has_pon_plus_4th():
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E, TileId.E,
	])
	var pon := Meld.make_pon(
		[Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)], 0)
	assert_true(seat.melds.add_existing(pon))
	var result: Dictionary = ai.decide_self_kan(seat)
	assert_eq(result.get("kind", ""), "added_kan")
	assert_eq(result.get("tile_id", -1), TileId.W5)

func test_ai_no_self_kan_when_nothing():
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W5, TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E,
	])
	var result: Dictionary = ai.decide_self_kan(seat)
	assert_true(result.is_empty(), "no self-kan possible")

func test_ai_skips_ankan_when_riichi():
	var ai := HeuristicAi.new(42)
	var seat := _seat_with_hand([
		TileId.W5, TileId.W5, TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E,
	])
	seat.riichi = RiichiState.new()
	seat.riichi.declared = true
	var result: Dictionary = ai.decide_self_kan(seat)
	assert_true(result.is_empty(), "riichi blocks self-kan")
