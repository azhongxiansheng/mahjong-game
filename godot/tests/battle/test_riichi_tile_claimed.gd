extends GutTest

# 立直宣告牌被对家鸣后,riichi_discard_index 应清 -1,否则 DiscardRiver
# 渲染时会把"新位置末位"错旋转(因为索引固定但 Array 已 pop)。


# 构造:seat 0 立直,弃牌堆 [A, B, RIICHI_TILE],riichi_discard_index=2。
# seat 1 chi 走 RIICHI_TILE(末位)→ 索引应清 -1。
func test_chi_on_riichi_tile_clears_index() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	# seat 0 是 discarder,riichi 状态
	bc.state.current_seat = 0
	bc.state.seats[0].riichi.declared = true
	bc.state.seats[0].riichi.riichi_discard_index = 2
	# 注入弃牌堆
	bc.state.discards_per_seat[0] = [
		Tile.new(TileId.W1), Tile.new(TileId.W9), Tile.new(TileId.W2)]
	# seat 1 注入 chi companion(W1,W3)以吃 W2
	bc.state.seats[1].hand._tiles.append(Tile.new(TileId.W1))
	bc.state.seats[1].hand._tiles.append(Tile.new(TileId.W3))
	# 调 apply_chi
	var ok: bool = bc.engine.apply_chi(1, Tile.new(TileId.W2), [TileId.W1, TileId.W3])
	assert_true(ok, "chi 应成立")
	assert_eq(bc.state.seats[0].riichi.riichi_discard_index, -1,
		"立直牌被鸣 → riichi_discard_index 应清 -1")


# 反例:其他牌被 chi(如果 chi 不在最末位,实际不可能 chi)— 但若 riichi 不在
# 末位被弹,也不该清。我们这里直接验:non-riichi 末位被弹,index 不变。
func test_pon_non_riichi_tile_keeps_index() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	bc.state.current_seat = 0
	bc.state.seats[0].riichi.declared = true
	bc.state.seats[0].riichi.riichi_discard_index = 0  # riichi 牌是 index 0
	bc.state.discards_per_seat[0] = [
		Tile.new(TileId.W1), Tile.new(TileId.W9), Tile.new(TileId.T5)]  # 末位 T5 非 riichi 牌
	bc.state.seats[1].hand._tiles.append(Tile.new(TileId.T5))
	bc.state.seats[1].hand._tiles.append(Tile.new(TileId.T5))
	var ok: bool = bc.engine.apply_pon(1, Tile.new(TileId.T5))
	assert_true(ok)
	assert_eq(bc.state.seats[0].riichi.riichi_discard_index, 0,
		"非 riichi 牌被鸣 → riichi_discard_index 保持原值")


# minkan 同理
func test_minkan_on_riichi_tile_clears_index() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	bc.state.current_seat = 0
	bc.state.seats[0].riichi.declared = true
	bc.state.seats[0].riichi.riichi_discard_index = 1
	bc.state.discards_per_seat[0] = [
		Tile.new(TileId.W1), Tile.new(TileId.S5)]  # riichi=S5(index 1)
	# seat 1 需要 3 张 S5 来 minkan
	bc.state.seats[1].hand._tiles.append(Tile.new(TileId.S5))
	bc.state.seats[1].hand._tiles.append(Tile.new(TileId.S5))
	bc.state.seats[1].hand._tiles.append(Tile.new(TileId.S5))
	var ok: bool = bc.engine.apply_minkan(1, Tile.new(TileId.S5))
	assert_true(ok)
	assert_eq(bc.state.seats[0].riichi.riichi_discard_index, -1,
		"立直牌被明杠 → index 清 -1")


# 未立直的 seat 弃牌被鸣 → index 不动(本来就是 -1)
func test_non_riichi_seat_index_stays_minus_one() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	bc.state.current_seat = 0
	# seat 0 未立直,index 默认 -1
	bc.state.discards_per_seat[0] = [Tile.new(TileId.W2)]
	bc.state.seats[1].hand._tiles.append(Tile.new(TileId.W1))
	bc.state.seats[1].hand._tiles.append(Tile.new(TileId.W3))
	var ok: bool = bc.engine.apply_chi(1, Tile.new(TileId.W2), [TileId.W1, TileId.W3])
	assert_true(ok)
	assert_eq(bc.state.seats[0].riichi.riichi_discard_index, -1,
		"未立直 seat 始终 -1")
