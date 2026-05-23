extends GutTest

# 日麻 §5 立直锁牌:AI 立直后必须 tsumogiri(切刚摸的牌),不能选别的。
# 修复前 dead code:HeuristicAi/SimpleAi.decide_discard 不知 riichi 状态,
# 立直 AI 会随便切牌 → 违反立直锁牌规则。
# 修:BC._get_discard_decision + PBC AI 分支前置 riichi check 强制 tsumogiri。


# BC sync 路径:立直 + last_drawn_tile_id 设 → _get_discard_decision 返刚摸的牌
func test_bc_get_discard_forces_tsumogiri_when_riichi() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	var seat: Seat = bc.state.seats[0]
	# 模拟 seat 0 已立直 + 刚摸到 W5
	seat.riichi.declare(0, false)
	seat.hand._tiles.append(Tile.new(TileId.W5))
	seat.last_drawn_tile_id = TileId.W5
	var tile: Tile = bc._get_discard_decision(seat, 0)
	assert_not_null(tile)
	assert_eq(int(tile.id), int(TileId.W5),
		"立直 AI 应强制切刚摸的 W5,而不是 AI decide_discard 返回的别的牌")


# 未立直 → 正常调 AI decide_discard,不强制 tsumogiri
func test_bc_get_discard_normal_when_not_riichi() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	var seat: Seat = bc.state.seats[0]
	# seat 不立直,但 last_drawn 设值
	seat.last_drawn_tile_id = TileId.W5
	seat.hand._tiles.append(Tile.new(TileId.W5))
	# AI 路径下应返回 ai.decide_discard 的结果(SimpleAi 随机选,但至少非 null)
	var tile: Tile = bc._get_discard_decision(seat, 0)
	assert_not_null(tile, "未立直应走正常 AI 路径")


# 立直但 last_drawn=-1(无刚摸的牌,比如刚被 chi/pon 进来,正常不应到达)→ 走 AI
func test_bc_get_discard_no_last_drawn_falls_back_to_ai() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	var seat: Seat = bc.state.seats[0]
	seat.riichi.declare(0, false)
	seat.last_drawn_tile_id = -1
	# 注入至少一张牌让 AI 不返 null
	seat.hand._tiles.clear()
	seat.hand._tiles.append(Tile.new(TileId.W5))
	var tile: Tile = bc._get_discard_decision(seat, 0)
	assert_not_null(tile, "异常无 last_drawn 时应仍能正常走 AI")
