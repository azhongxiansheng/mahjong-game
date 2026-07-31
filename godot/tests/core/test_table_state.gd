extends GutTest

# ARCH-CORE #399：core/ 拥有纯对局状态 TableState；BattleState 只在 battle/ 扩展
# 技能运行时字段。本文件证明 core 引擎链（TurnEngine / DrawDetector /
# NagashiMangan）可在不构造 BattleState 的前提下运行。


func _pure_table_state() -> TableState:
	var s := TableState.new()
	for i in range(4):
		s.seats.append(Seat.new(i, TileId.E))
	s.wall = Wall.new_full_set(0)
	s.wall.shuffle(42)
	s.wall.reserve_dead_wall(14)
	s.dora_indicators = DoraIndicators.new()
	for _i in range(13):
		for seat_id in range(4):
			s.seats[seat_id].add_to_hand(s.wall.draw())
	return s


func test_battle_state_extends_core_table_state() -> void:
	var battle_state := BattleState.for_east_round(1, 0, 1, 0, 0)
	assert_not_null(battle_state)
	assert_true(battle_state is TableState, "BattleState 必须继承 core TableState")


func test_turn_engine_draw_discard_on_pure_table_state() -> void:
	var s := _pure_table_state()
	var engine := TurnEngine.new(s)
	var drawn: Tile = engine.draw_for_current()
	assert_not_null(drawn, "纯 TableState 下应能摸牌")
	assert_eq(s.phase, BattlePhase.Kind.DISCARD)
	assert_true(engine.discard(drawn.instance_id), "纯 TableState 下应能弃牌")
	assert_eq(s.phase, BattlePhase.Kind.CLAIM)


func test_draw_detector_on_pure_table_state() -> void:
	var s := _pure_table_state()
	assert_false(DrawDetector.should_exhaustive_draw(s))
	assert_false(DrawDetector.is_suufon_renda(s))
	assert_false(DrawDetector.is_suucha_riichi(s))
	assert_false(DrawDetector.is_suukantsu_sanra(s))


func test_nagashi_mangan_on_pure_table_state() -> void:
	var s := _pure_table_state()
	assert_eq(NagashiMangan.detect_winner_seat(s), -1)
