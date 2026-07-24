extends GutTest

# E2-02 第二轮：消耗品公开 API 已移除；ITEM_USE 仅 NOT_ENABLED 且零修改。


func test_playable_has_no_consumable_public_api() -> void:
	var bc := PlayableBattleController.new(42, 0, false)
	assert_false(bc.has_method("set_consumables"), "不得保留 set_consumables")
	assert_false(bc.has_method("use_consumable"), "不得保留 use_consumable")
	assert_false(bc.has_method("has_usable_consumable"), "不得保留 has_usable_consumable")
	assert_false(bc.has_method("get_usable_consumables"), "不得保留 get_usable_consumables")


func test_item_use_action_not_enabled_zero_domain_change() -> void:
	var bc := BattleController.new(42, 0, false, TileId.E)
	assert_eq(bc.state.phase, BattlePhase.Kind.DRAW)
	var drawn: Tile = bc.engine.draw_for_current()
	assert_not_null(drawn)
	var seat: Seat = bc.state.seats[bc.state.current_seat]
	var hand_before: int = seat.hand.size()
	var points_before: int = seat.points
	var events_before: int = bc.events.size()
	var journal_before: int = bc.action_journal().size()
	var ctx: DecisionContext = bc.decision_context_for_seat(bc.state.current_seat)
	assert_not_null(ctx)
	var act: Action = Action.item_use(
		bc.state.current_seat, "hp_potion_v1", "local",
		"550e8400-e29b-41d4-a716-000000000001",
		ctx.decision_id, bc.state.hand_seq, 1
	)
	assert_not_null(act)
	var resp: ActionResolution = bc.apply_action(act, ActionSource.HUMAN)
	assert_not_null(resp)
	assert_false(resp.accepted)
	assert_eq(resp.error_code, ActionResolution.NOT_ENABLED)
	assert_eq(seat.hand.size(), hand_before, "ITEM_USE 零修改 hand")
	assert_eq(seat.points, points_before, "ITEM_USE 零修改 points")
	assert_eq(bc.events.size(), events_before, "ITEM_USE 不产生事件")
	assert_eq(bc.action_journal().size(), journal_before, "ITEM_USE 不进 journal")
	assert_false(ctx.has_kind("ITEM_USE"), "TURN 不得 offer ITEM_USE")


func test_player_action_panel_has_no_use_consumable_api() -> void:
	# UI 生产路径不得再暴露 use_consumable 公开方法
	var panel_script: GDScript = load("res://ui/four_player_table/player_action_panel.gd") as GDScript
	assert_not_null(panel_script)
	var names: Array = []
	for m in panel_script.get_script_method_list():
		names.append(str(m.get("name", "")))
	assert_false(names.has("use_consumable"), "PlayerActionPanel 不得有 use_consumable 方法")
	assert_false(names.has("set_consumables"), "PlayerActionPanel 不得有 set_consumables")
