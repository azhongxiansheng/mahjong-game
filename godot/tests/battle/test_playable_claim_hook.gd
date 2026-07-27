extends GutTest

# 验证 CLAIM 规则层 + companion instance_id（无旧吃牌专用选择器 / tile_id fallback）

func test_can_pon_with_pair_in_hand() -> void:
	var hand := Hand.new()
	hand.add(Tile.new(TileId.W5))
	hand.add(Tile.new(TileId.W5))
	hand.add(Tile.new(TileId.T3))
	assert_true(ClaimValidator.can_pon(0, 1, hand, TileId.W5))


func test_can_pon_without_pair() -> void:
	var hand := Hand.new()
	hand.add(Tile.new(TileId.W5))
	hand.add(Tile.new(TileId.T3))
	assert_false(ClaimValidator.can_pon(0, 1, hand, TileId.W5))


func test_can_pon_self_discard_blocked() -> void:
	var hand := Hand.new()
	hand.add(Tile.new(TileId.W5))
	hand.add(Tile.new(TileId.W5))
	assert_false(ClaimValidator.can_pon(0, 0, hand, TileId.W5))


func test_can_minkan_with_triplet() -> void:
	var hand := Hand.new()
	hand.add(Tile.new(TileId.HAKU))
	hand.add(Tile.new(TileId.HAKU))
	hand.add(Tile.new(TileId.HAKU))
	assert_true(ClaimValidator.can_minkan(0, 1, hand, TileId.HAKU))


func test_can_chi_only_from_kamicha() -> void:
	var hand := Hand.new()
	hand.add(Tile.new(TileId.W4))
	hand.add(Tile.new(TileId.W6))
	assert_true(ClaimValidator.can_chi(0, 3, hand, TileId.W5))
	assert_false(ClaimValidator.can_chi(0, 1, hand, TileId.W5))
	assert_false(ClaimValidator.can_chi(0, 2, hand, TileId.W5))


func test_chi_companion_offers_use_instance_ids() -> void:
	var bc := BattleController.new(1, 0, false, TileId.E, 0)
	bc.state.seats[0].hand = Hand.new()
	bc.state.seats[0].hand.add(Tile.new(TileId.W4, false, 0, 40))
	bc.state.seats[0].hand.add(Tile.new(TileId.W6, false, 0, 60))
	for tid in [
		TileId.T1, TileId.T2, TileId.T3, TileId.S1, TileId.S2, TileId.S3,
		TileId.E, TileId.E, TileId.S_WIND, TileId.W_WIND, TileId.N,
	]:
		bc.state.seats[0].hand.add(Tile.new(tid, false, 0, 70 + bc.state.seats[0].hand.size()))
	bc.state.current_seat = 3
	bc.state.phase = BattlePhase.Kind.CLAIM
	var discarded := Tile.new(TileId.W5, false, 0, 50)
	bc._last_discarded_tile = discarded
	bc._last_discarder_seat = 3
	bc.state.seats[3].river.restore([discarded])
	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	assert_true(ctx.has_kind("CHI"), "下家可 CHI")
	var found_iids := false
	for offer in ctx.allowed_actions:
		if str(offer.get("kind", "")) != "CHI":
			continue
		for opt in offer.get("payload_options", []):
			var comps: Array = opt.get("companion_tile_instance_ids", [])
			var sorted := comps.duplicate()
			sorted.sort()
			if sorted == [40, 60]:
				found_iids = true
	assert_true(found_iids, "CHI offer 必须 companion instance_id [40,60]，禁止 tile_id")
