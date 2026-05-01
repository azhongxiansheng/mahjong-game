extends GutTest

# BattlePhase: 一局 4 个子阶段（spec §5）。

func test_four_kinds_exist():
	assert_eq(BattlePhase.Kind.DRAW, 0)
	assert_eq(BattlePhase.Kind.DISCARD, 1)
	assert_eq(BattlePhase.Kind.CLAIM, 2)
	assert_eq(BattlePhase.Kind.SETTLE, 3)

func test_phase_name_returns_label():
	assert_eq(BattlePhase.phase_name(BattlePhase.Kind.DRAW), "DRAW")
	assert_eq(BattlePhase.phase_name(BattlePhase.Kind.DISCARD), "DISCARD")
	assert_eq(BattlePhase.phase_name(BattlePhase.Kind.CLAIM), "CLAIM")
	assert_eq(BattlePhase.phase_name(BattlePhase.Kind.SETTLE), "SETTLE")

func test_phase_name_unknown_returns_string():
	assert_eq(BattlePhase.phase_name(99), "UNKNOWN")
