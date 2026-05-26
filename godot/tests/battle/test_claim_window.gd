extends GutTest

# Unified tests for claim window Tasks 3, 4, 5:
#   Task 3: AI self-kan (ankan / added_kan) after draw
#   Task 4: Claim resolution (AI pon/minkan during CLAIM phase)
#   Task 5: Chankan (robbing a kan)

func _hand(ids: Array) -> Hand:
	var h := Hand.new()
	for tid in ids:
		h.add(Tile.new(tid))
	return h

# Force the next draw to be a specific tile by replacing the tile at _draw_index.
func _force_next_draw(wall: Wall, tile: Tile) -> void:
	wall._tiles[wall._draw_index] = tile

# ---- Task 3: Self-Kan ----

func test_ai_ankan_after_draw():
	var bc := BattleController.new(100, 0, true)
	var seat1: Seat = bc.state.seats[1]
	seat1.hand = _hand([
		TileId.E, TileId.E, TileId.E,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3, TileId.S5,
	])
	# Force next draw to be E (giving seat1 four copies)
	_force_next_draw(bc.state.wall, Tile.new(TileId.E))
	bc.state.current_seat = 1
	bc.state.phase = BattlePhase.Kind.DRAW
	bc._step_draw()
	var has_ankan := false
	for m in seat1.melds:
		if m.kind == Meld.Kind.ANKAN and m.tiles[0].id == TileId.E:
			has_ankan = true
	assert_true(has_ankan, "AI should declare ankan with 4 copies of E")

func test_no_ankan_during_riichi():
	var bc := BattleController.new(100, 0, true)
	var seat1: Seat = bc.state.seats[1]
	seat1.hand = _hand([
		TileId.E, TileId.E, TileId.E,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3, TileId.S5,
	])
	seat1.riichi.declare(0, false)
	_force_next_draw(bc.state.wall, Tile.new(TileId.E))
	bc.state.current_seat = 1
	bc.state.phase = BattlePhase.Kind.DRAW
	bc._step_draw()
	var has_ankan := false
	for m in seat1.melds:
		if m.kind == Meld.Kind.ANKAN:
			has_ankan = true
	assert_false(has_ankan, "riichi blocks ankan")

# ---- Task 4: Claim Resolution ----

func test_ai_pon_during_claim_phase():
	var bc := BattleController.new(100, 0, true)
	var seat2: Seat = bc.state.seats[2]
	seat2.hand = _hand([
		TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E,
	])
	# Simulate a discard event for _get_last_discarded
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	var ti := TileInstance.make(Tile.new(TileId.W5), 0, null)
	bc.events.append(BattleEvent.make(&"TILE_DISCARDED", 0, ti, {}))
	bc._resolve_claims(Tile.new(TileId.W5), 0)
	var has_pon := false
	for m in seat2.melds:
		if m.kind == Meld.Kind.PON and m.tiles[0].id == TileId.W5:
			has_pon = true
	assert_true(has_pon, "seat 2 should pon W5")
	assert_eq(bc.state.current_seat, 2, "current_seat = claimant")
	assert_eq(bc.state.phase, BattlePhase.Kind.DISCARD, "phase = DISCARD after pon")

func test_no_claims_advances():
	var bc := BattleController.new(100, 0, true)
	# Clear all AI hands of HAKU so nobody can claim it
	for i in range(1, 4):
		while bc.state.seats[i].hand.count_of(TileId.HAKU) > 0:
			bc.state.seats[i].hand.remove_by_id(TileId.HAKU)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc.events.append(BattleEvent.make(&"TILE_DISCARDED", 0,
		TileInstance.make(Tile.new(TileId.HAKU), 0, null), {}))
	bc._resolve_claims(Tile.new(TileId.HAKU), 0)
	assert_eq(bc.state.current_seat, 1, "should advance to next seat")
	assert_eq(bc.state.phase, BattlePhase.Kind.DRAW)

func test_tile_claimed_event_emitted():
	var bc := BattleController.new(100, 0, true)
	var seat2: Seat = bc.state.seats[2]
	seat2.hand = _hand([
		TileId.W5, TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E,
	])
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc.events.append(BattleEvent.make(&"TILE_DISCARDED", 0,
		TileInstance.make(Tile.new(TileId.W5), 0, null), {}))
	bc._resolve_claims(Tile.new(TileId.W5), 0)
	var found_claim := false
	for ev in bc.events:
		if ev.type == &"TILE_CLAIMED":
			found_claim = true
	assert_true(found_claim, "TILE_CLAIMED event should be emitted")

# ---- Task 5: Chankan ----

func test_chankan_ron_on_added_kan():
	var bc := BattleController.new(100, 0, true)
	# Seat 2: tenpai waiting W5 (W4+W6 = kanchan wait on W5)
	bc.state.seats[2].hand = _hand([
		TileId.W4, TileId.W6,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E,
	])
	bc.state.seats[2].furiten = FuritenState.new()
	# Seat 1: has W5 in hand + PON of W5 (for added_kan)
	bc.state.seats[1].hand = _hand([
		TileId.W5,
		TileId.T1, TileId.T2, TileId.T3,
		TileId.S1, TileId.S2, TileId.S3,
		TileId.W7, TileId.W8, TileId.W9,
		TileId.S5, TileId.S5, TileId.S5,
	])
	var pon := Meld.make_pon(
		[Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)], 0)
	bc.state.seats[1].melds = [pon]
	var ronned: bool = bc._try_chankan_ron(TileId.W5, 1)
	assert_true(ronned, "seat 2 should ron via chankan")

func test_chankan_blocked_by_furiten():
	var bc := BattleController.new(100, 0, true)
	bc.state.seats[2].hand = _hand([
		TileId.W4, TileId.W6,
		TileId.T2, TileId.T3, TileId.T4,
		TileId.S2, TileId.S3, TileId.S4,
		TileId.W1, TileId.W2, TileId.W3,
		TileId.E, TileId.E,
	])
	bc.state.seats[2].furiten = FuritenState.new()
	bc.state.seats[2].furiten.permanent = true
	bc.state.seats[1].hand = _hand([TileId.W5])
	var pon := Meld.make_pon(
		[Tile.new(TileId.W5), Tile.new(TileId.W5), Tile.new(TileId.W5)], 0)
	bc.state.seats[1].melds = [pon]
	var ronned: bool = bc._try_chankan_ron(TileId.W5, 1)
	assert_false(ronned, "furiten blocks chankan ron")
