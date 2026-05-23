extends GutTest

# 裏 dora 必须在每局开始时预置进 dora_indicators.hidden_uradora —
# 立直胡时 count_total_dora(include_uradora=true) 才能算上;之前列表
# 永空 → uradora 是 dead code → 立直收益被低估。

func test_initial_state_has_at_least_one_hidden_uradora() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	assert_gt(bc.state.dora_indicators.hidden_uradora.size(), 0,
		"局起手 hidden_uradora 应至少有 1 张(对应初始明 dora 的裏)")


func test_visible_and_hidden_count_match_after_kan() -> void:
	# kan 后明 dora +1 → 裏 dora 也应 +1。turn_engine._reveal_new_dora
	# 内部同步加 hidden_uradora。
	var bc := BattleController.new(7, 0, false, TileId.E)
	var v0: int = bc.state.dora_indicators.visible.size()
	var u0: int = bc.state.dora_indicators.hidden_uradora.size()
	assert_eq(v0, 1, "起手 1 张明 dora")
	assert_eq(u0, 1, "起手 1 张裏 dora")
	# 直接调内部方法翻新 dora
	bc.engine._reveal_new_dora()
	assert_eq(bc.state.dora_indicators.visible.size(), v0 + 1)
	assert_eq(bc.state.dora_indicators.hidden_uradora.size(), u0 + 1)
