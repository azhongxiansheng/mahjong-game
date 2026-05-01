extends GutTest

func test_default_initialization():
	var s := BattleState.new()
	assert_eq(s.event_chain_depth, 0)
	assert_eq(s.scores.size(), 4)
	for i in range(4):
		assert_eq(s.scores[i], 25000, "起家 25000")
		assert_false(s.furiten_flags[i])
		assert_false(s.ron_cancelled[i])
	assert_eq(s.revealed_tiles.size(), 0)
	assert_eq(s.haitei_forced_seat, -1)

func test_max_event_chain_depth_constant():
	assert_eq(BattleState.MAX_EVENT_CHAIN_DEPTH, 16)

func test_mutating_scores_does_not_affect_others():
	var s := BattleState.new()
	s.scores[0] = 30000
	assert_eq(s.scores[0], 30000)
	assert_eq(s.scores[1], 25000)
