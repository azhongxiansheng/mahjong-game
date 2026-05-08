extends GutTest

# 验证 PlayableBattleController._try_player_claim_async 在玩家手里有对子且 AI
# 切到那张时，can_pon 应该被算成 true。本测试不走 UI；只调 ClaimValidator
# 静态函数验证规则层。

func test_can_pon_with_pair_in_hand() -> void:
	var hand := Hand.new()
	hand.add(Tile.new(TileId.W5))
	hand.add(Tile.new(TileId.W5))
	hand.add(Tile.new(TileId.T3))
	# AI seat 1 切 W5；玩家 seat 0 应该可碰
	assert_true(ClaimValidator.can_pon(0, 1, hand, TileId.W5))

func test_can_pon_without_pair() -> void:
	var hand := Hand.new()
	hand.add(Tile.new(TileId.W5))
	hand.add(Tile.new(TileId.T3))
	# 只 1 张 W5，不可碰
	assert_false(ClaimValidator.can_pon(0, 1, hand, TileId.W5))

func test_can_pon_self_discard_blocked() -> void:
	var hand := Hand.new()
	hand.add(Tile.new(TileId.W5))
	hand.add(Tile.new(TileId.W5))
	# claimant == discarder：不能碰自己
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
	# 玩家 seat 0 的上家是 seat 3；只有 seat 3 切牌玩家可吃
	assert_true(ClaimValidator.can_chi(0, 3, hand, TileId.W5))
	assert_false(ClaimValidator.can_chi(0, 1, hand, TileId.W5))
	assert_false(ClaimValidator.can_chi(0, 2, hand, TileId.W5))

func test_chi_companion_pick() -> void:
	var hand := Hand.new()
	hand.add(Tile.new(TileId.W4))
	hand.add(Tile.new(TileId.W6))
	# 玩家有 W4 W6，AI 切 W5 → 顺子 W4 W5 W6 → companion 应该是 [W4, W6]
	var companions := PlayableBattleController._pick_chi_companions(hand, TileId.W5)
	assert_eq(companions.size(), 2)
	assert_true(TileId.W4 in companions)
	assert_true(TileId.W6 in companions)
