extends GutTest

# 立直宣告牌被对家鸣后,riichi_discard_index 应清 -1,否则 DiscardRiver
# 渲染时会把"新位置末位"错旋转(因为索引固定但 Array 已 pop)。


func _tile(tid: int, iid: int) -> Tile:
	return Tile.new(tid, false, Tile.NO_OWNER, iid)


# 构造:seat 0 立直,弃牌堆 [A, B, RIICHI_TILE],riichi_discard_index=2。
# seat 1 chi 走 RIICHI_TILE(末位)→ 索引应清 -1。
func test_chi_on_riichi_tile_clears_index() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc.state.seats[0].riichi.declared = true
	bc.state.seats[0].riichi.riichi_discard_index = 2
	# 河：[W1, W9, W2(立直牌)]；seat1 companions W1/W3 吃 W2
	bc.state.discards_per_seat[0] = [
		_tile(TileId.W1, 100), _tile(TileId.W9, 101), _tile(TileId.W2, 102)]
	bc.state.seats[1].hand = Hand.new()
	bc.state.seats[1].hand.add(_tile(TileId.W1, 201))
	bc.state.seats[1].hand.add(_tile(TileId.W3, 202))
	var ok: bool = bc.engine.apply_chi(1, 102, [201, 202])
	assert_true(ok, "chi 应成立")
	assert_eq(bc.state.seats[0].riichi.riichi_discard_index, -1,
		"立直牌被鸣 → riichi_discard_index 应清 -1")


# 反例:其他牌被 chi(如果 chi 不在最末位,实际不可能 chi)— 但若 riichi 不在
# 末位被弹,也不该清。我们这里直接验:non-riichi 末位被弹,index 不变。
func test_pon_non_riichi_tile_keeps_index() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc.state.seats[0].riichi.declared = true
	bc.state.seats[0].riichi.riichi_discard_index = 0  # riichi 牌是 index 0
	bc.state.discards_per_seat[0] = [
		_tile(TileId.W1, 100), _tile(TileId.W9, 101), _tile(TileId.T5, 102)]
	bc.state.seats[1].hand = Hand.new()
	bc.state.seats[1].hand.add(_tile(TileId.T5, 201))
	bc.state.seats[1].hand.add(_tile(TileId.T5, 202))
	var ok: bool = bc.engine.apply_pon(1, 102, [201, 202])
	assert_true(ok)
	assert_eq(bc.state.seats[0].riichi.riichi_discard_index, 0,
		"非 riichi 牌被鸣 → riichi_discard_index 保持原值")


# minkan 同理
func test_minkan_on_riichi_tile_clears_index() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	bc.state.seats[0].riichi.declared = true
	bc.state.seats[0].riichi.riichi_discard_index = 1
	bc.state.discards_per_seat[0] = [
		_tile(TileId.W1, 100), _tile(TileId.S5, 101)]  # riichi=S5(index 1)
	bc.state.seats[1].hand = Hand.new()
	bc.state.seats[1].hand.add(_tile(TileId.S5, 201))
	bc.state.seats[1].hand.add(_tile(TileId.S5, 202))
	bc.state.seats[1].hand.add(_tile(TileId.S5, 203))
	var ok: bool = bc.engine.apply_minkan(1, 101, [201, 202, 203])
	assert_true(ok)
	assert_eq(bc.state.seats[0].riichi.riichi_discard_index, -1,
		"立直牌被明杠 → index 清 -1")


# 未立直的 seat 弃牌被鸣 → index 不动(本来就是 -1)
func test_non_riichi_seat_index_stays_minus_one() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.CLAIM
	# seat 0 未立直,index 默认 -1
	bc.state.discards_per_seat[0] = [_tile(TileId.W2, 100)]
	bc.state.seats[1].hand = Hand.new()
	bc.state.seats[1].hand.add(_tile(TileId.W1, 201))
	bc.state.seats[1].hand.add(_tile(TileId.W3, 202))
	var ok: bool = bc.engine.apply_chi(1, 100, [201, 202])
	assert_true(ok)
	assert_eq(bc.state.seats[0].riichi.riichi_discard_index, -1,
		"未立直 seat 始终 -1")
