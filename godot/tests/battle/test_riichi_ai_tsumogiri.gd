extends GutTest

# 日麻 §5 立直锁牌: AI 立直后必须 tsumogiri（切刚摸实体），不能选别的。
# E2-02 / #232：只认 seat.last_drawn_instance_id；用 TrackingAi 证明是否走 AI。


class TrackingAi extends SimpleAi:
	var decide_discard_calls: int = 0
	var return_instance_id: int = 10

	func _init(p_seed: int = 0, p_return_iid: int = 10) -> void:
		super._init(p_seed)
		return_instance_id = p_return_iid

	func decide_discard(seat: Seat) -> Tile:
		decide_discard_calls += 1
		return seat.hand.find_by_instance_id(return_instance_id)


func _seed_w5_pair(seat: Seat) -> void:
	seat.hand._tiles.clear()
	seat.hand.add(Tile.new(TileId.W5, false, 0, 10))  # 黑 5 iid10
	seat.hand.add(Tile.new(TileId.W5, true, 0, 11))   # 赤 5 iid11


# a) 已立直 + last_drawn_instance_id=11 → 强制摸切实体 11，不调 AI
func test_bc_get_discard_forces_tsumogiri_when_riichi() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	var tracker := TrackingAi.new(42, 10)
	bc.ai = tracker
	var seat: Seat = bc.state.seats[0]
	seat.riichi.declare(0, false)
	_seed_w5_pair(seat)
	seat.last_drawn_instance_id = 11
	var tile: Tile = bc._get_discard_decision(seat, 0)
	assert_not_null(tile)
	assert_eq(tile.instance_id, 11, "立直强制摸切精确实体 11")
	assert_true(tile.is_red_dora, "须为赤 5")
	assert_ne(tile.instance_id, 10, "不得选同值黑 5 iid10")
	assert_eq(tracker.decide_discard_calls, 0, "强制 tsumogiri 不得调 AI")


# b) 未立直但 last_drawn_instance_id=11 → 仍走 AI（配置返回 iid10）
func test_bc_get_discard_normal_when_not_riichi() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	var tracker := TrackingAi.new(42, 10)
	bc.ai = tracker
	var seat: Seat = bc.state.seats[0]
	_seed_w5_pair(seat)
	seat.last_drawn_instance_id = 11
	var tile: Tile = bc._get_discard_decision(seat, 0)
	assert_not_null(tile, "未立直应走正常 AI 路径")
	assert_eq(tracker.decide_discard_calls, 1, "未立直必须调 AI")
	assert_eq(tile.instance_id, 10, "AI 配置返回 iid10，证明未强制摸切 11")


# c) 已立直但 last_drawn_instance_id=INVALID → fallback AI 返回 iid10
func test_bc_get_discard_no_last_drawn_falls_back_to_ai() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	var tracker := TrackingAi.new(42, 10)
	bc.ai = tracker
	var seat: Seat = bc.state.seats[0]
	seat.riichi.declare(0, false)
	_seed_w5_pair(seat)
	seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
	var tile: Tile = bc._get_discard_decision(seat, 0)
	assert_not_null(tile, "无 last_drawn 时应 fallback AI")
	assert_eq(tracker.decide_discard_calls, 1, "INVALID 时须调 AI")
	assert_eq(tile.instance_id, 10, "fallback AI 返回配置的 iid10")


# d) 权威 TURN offer 也必须锁牌；不能只依赖本地 UI/AI 自动摸切。
func test_riichi_turn_window_only_offers_last_drawn_instance() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	var seat: Seat = bc.state.seats[0]
	_seed_w5_pair(seat)
	seat.riichi.declare(0, false)
	seat.last_drawn_instance_id = 11
	bc.state.current_seat = 0
	bc.state.phase = BattlePhase.Kind.DISCARD

	var ctx: DecisionContext = bc.decision_context_for_seat(0)
	assert_not_null(ctx)
	var discard_options: Array = []
	for offer in ctx.allowed_actions:
		if str(offer.get("kind", "")) == "DISCARD":
			discard_options = offer.get("payload_options", [])
			break
	assert_eq(discard_options, [{"tile_instance_id": 11}],
		"立直后权威窗口只能 offer 刚摸实体")

	var forged: Action = Action.discard(
		0, 10, "local", "550e8400-e29b-41d4-a716-446655440010",
		ctx.decision_id, bc.state.hand_seq, 1)
	var result: ActionResolution = bc.apply_action(forged, ActionSource.HUMAN)
	assert_false(result.accepted, "立直后换切手内旧牌必须由权威拒绝")
	assert_eq(result.error_code, ActionResolution.NOT_OFFERED)
	assert_not_null(seat.hand.find_by_instance_id(10), "拒绝路径不得修改手牌")
