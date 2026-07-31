extends GutTest


func _entity(tile_id: int, instance_id: int) -> Tile3D:
	var tile := Tile3D.new()
	add_child_autofree(tile)
	tile.setup_entity(tile_id, true, false, instance_id)
	return tile


func _click(table: MahjongTable3D, instance_id: int) -> void:
	table.call("_on_tile_clicked", instance_id)


func test_confirm_discard_first_click_selects_and_second_click_submits() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var tile := _entity(TileId.W1, 501)
	table._hand_tiles = [tile]
	table.set_hand_clickable(true)

	assert_true(table.has_method("set_hand_activation_mode"),
		"3D 手牌须支持两段式切牌激活模式")
	if not table.has_method("set_hand_activation_mode"):
		return
	table.call("set_hand_activation_mode", &"confirm_discard")
	watch_signals(table)

	_click(table, 501)
	assert_signal_emit_count(table, "player_card_clicked", 0,
		"第一次点击只能选中，不能直接切牌")
	assert_eq(table.get_hand_interaction_state().get("selected_instances", []),
		[501])
	assert_true(bool(tile.visual_state().get("selected", false)))

	_click(table, 501)
	assert_signal_emit_count(table, "player_card_clicked", 1,
		"再次点击同一张牌才提交切牌")
	assert_signal_emitted_with_parameters(table, "player_card_clicked", [501])


func test_confirm_discard_clicking_another_tile_switches_selection() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var first := _entity(TileId.W1, 601)
	var second := _entity(TileId.W2, 602)
	table._hand_tiles = [first, second]
	table.set_hand_clickable(true)
	if not table.has_method("set_hand_activation_mode"):
		fail_test("缺少 set_hand_activation_mode")
		return
	table.call("set_hand_activation_mode", &"confirm_discard")
	watch_signals(table)

	_click(table, 601)
	_click(table, 602)
	assert_signal_emit_count(table, "player_card_clicked", 0)
	assert_eq(table.get_hand_interaction_state().get("selected_instances", []),
		[602])
	assert_false(bool(first.visual_state().get("selected", false)))
	assert_true(bool(second.visual_state().get("selected", false)))


func test_claim_pick_immediate_mode_keeps_single_click_submission() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var tile := _entity(TileId.T3, 701)
	table._hand_tiles = [tile]
	table.set_hand_clickable(true)
	if not table.has_method("set_hand_activation_mode"):
		fail_test("缺少 set_hand_activation_mode")
		return
	table.call("set_hand_activation_mode", &"immediate")
	watch_signals(table)

	_click(table, 701)
	assert_signal_emitted_with_parameters(table, "player_card_clicked", [701])


func test_dimmed_illegal_tile_never_submits() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var allowed := _entity(TileId.T3, 711)
	var blocked := _entity(TileId.T4, 712)
	table._hand_tiles = [allowed, blocked]
	table.set_hand_clickable(true)
	table.dim_hand_except([711])
	table.set_hand_activation_mode(&"immediate")
	watch_signals(table)

	_click(table, 712)
	assert_signal_emit_count(table, "player_card_clicked", 0,
		"权威候选之外的压暗牌不得产生动作")
	_click(table, 711)
	assert_signal_emitted_with_parameters(table, "player_card_clicked", [711])


func test_upward_flick_submits_without_second_click() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var tile := _entity(TileId.S5, 801)
	table._hand_tiles = [tile]
	table.set_hand_clickable(true)
	if not table.has_method("set_hand_activation_mode"):
		fail_test("缺少 set_hand_activation_mode")
		return
	table.call("set_hand_activation_mode", &"confirm_discard")
	assert_true(table.has_method("_on_tile_flicked"), "牌桌须消费上推切牌事件")
	if not table.has_method("_on_tile_flicked"):
		return
	watch_signals(table)

	table.call("_on_tile_flicked", 801)
	assert_signal_emitted_with_parameters(table, "player_card_clicked", [801])


func test_tile3d_emits_flick_after_upward_drag_threshold() -> void:
	var tile := _entity(TileId.HAKU, 901)
	tile.set_clickable(true)
	assert_true(tile.has_signal("tile_flicked"), "Tile3D 须暴露上推手势信号")
	if not tile.has_signal("tile_flicked"):
		return
	watch_signals(tile)

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(120, 160)
	tile._input_event(null, press, Vector3.ZERO, Vector3.UP, 0)
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(120, 110)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	tile._input_event(null, drag, Vector3.ZERO, Vector3.UP, 0)

	assert_signal_emitted_with_parameters(tile, "tile_flicked", [901])
