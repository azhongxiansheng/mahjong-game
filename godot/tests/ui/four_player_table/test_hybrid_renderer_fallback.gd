extends GutTest


const PLAYABLE_TABLE := preload("res://ui/four_player_table/playable_table.tscn")


class FailedHybridRenderer extends MahjongTable3D:
	func _ready() -> void:
		# 模拟节点成功挂载，但 3D viewport/world 初始化提前失败。
		pass

	func is_renderer_ready() -> bool:
		return false


func _make_table() -> PlayableTable:
	var table := PLAYABLE_TABLE.instantiate() as PlayableTable
	add_child_autofree(table)
	await get_tree().process_frame
	return table


func _assert_only_2d_tiles_visible(table: PlayableTable,
		renderer: MahjongTable3D) -> void:
	var flat := table._table as FourPlayerTable
	assert_false(renderer.visible, "不可用 renderer 必须保持隐藏")
	for panel in flat.seat_panels:
		assert_true(panel._hand_tile_row.visible,
			"回退后四席 2D 手牌必须恢复")
	for river in flat.discard_rivers:
		assert_true((river as CanvasItem).visible,
			"回退后 2D 牌河必须恢复")
	for meld_area in flat.meld_areas:
		assert_true((meld_area as CanvasItem).visible,
			"回退后 2D 副露必须恢复")
	assert_same(table._seat_panel_player, flat.seat_panels[0],
		"输入 owner 必须同步回退到可见 2D 手牌")


func _count_2d_win_markers(panel: SeatPanel) -> int:
	var count := 0
	for slot in panel._hand_slots:
		var tile := slot.get_node_or_null("Tile") as CardTileBack
		if tile != null and bool(tile.get("_is_win_tile")):
			count += 1
	for child in panel._hand_tile_row.get_children():
		if child is CardTileBack and bool(child.get("_is_win_tile")):
			count += 1
	return count


func _count_3d_win_markers(renderer: MahjongTable3D, seat_id: int) -> int:
	var count := 0
	var tiles: Array = renderer._hand_tiles if seat_id == 0 \
		else renderer._opp_tiles[seat_id]
	for tile in tiles:
		if bool((tile as Tile3D).visual_state().get("win_tile", false)):
			count += 1
	return count


func test_existing_but_not_mounted_renderer_falls_back_to_one_2d_layer() -> void:
	var table := await _make_table()
	var not_mounted := MahjongTable3D.new()
	not_mounted.configure_tile_overlay()
	table._hybrid_table_3d = not_mounted

	assert_true(not_mounted.has_method("is_renderer_ready"),
		"renderer 必须公开可靠的 ready 查询")
	table.set_hybrid_enabled(true)
	_assert_only_2d_tiles_visible(table, not_mounted)
	assert_null(not_mounted.get_parent(), "尚未挂载的节点不得被误判为活跃牌层")

	table._hybrid_table_3d = null
	not_mounted.free()


func test_mounted_but_failed_renderer_falls_back_to_one_2d_layer() -> void:
	var table := await _make_table()
	var flat := table._table as FourPlayerTable
	var failed := FailedHybridRenderer.new()
	failed.configure_tile_overlay()
	assert_true(flat.mount_tile_entity_renderer(failed))
	table._hybrid_table_3d = failed

	table.set_hybrid_enabled(true)
	_assert_only_2d_tiles_visible(table, failed)
	assert_true(flat.is_ancestor_of(failed),
		"初始化失败节点即使仍在树中，也不得顶掉 2D 牌实体")


func test_freed_active_renderer_falls_back_without_stale_input_owner() -> void:
	var table := await _make_table()
	table.set_hybrid_enabled(true)
	var renderer := table._hybrid_table_3d as MahjongTable3D
	assert_not_null(renderer, "hybrid 启用后应持有活跃 renderer")
	assert_same(table._seat_panel_player, renderer,
		"释放前 renderer 应是当前输入 owner")
	renderer.free()
	assert_false(is_instance_valid(renderer), "fixture 必须释放活跃 renderer")

	table.set_hybrid_enabled(false)

	var flat := table._table as FourPlayerTable
	assert_same(table._seat_panel_player, flat.seat_panels[0],
		"renderer 释放后必须把输入 owner 回退到 seat0")
	for panel in flat.seat_panels:
		assert_true(panel._hand_tile_row.visible,
			"renderer 释放后四席 2D 手牌必须恢复")
	for river in flat.discard_rivers:
		assert_true((river as CanvasItem).visible,
			"renderer 释放后 2D 牌河必须恢复")
	for meld_area in flat.meld_areas:
		assert_true((meld_area as CanvasItem).visible,
			"renderer 释放后 2D 副露必须恢复")


func test_public_rewire_falls_back_when_active_renderer_was_freed() -> void:
	var table := await _make_table()
	table.set_hybrid_enabled(true)
	var renderer := table._hybrid_table_3d as MahjongTable3D
	assert_not_null(renderer, "hybrid 启用后应持有活跃 renderer")
	renderer.free()
	assert_false(is_instance_valid(renderer), "fixture 必须释放活跃 renderer")

	table._wire_public_bottom_hand_clicks()

	var flat := table._table as FourPlayerTable
	assert_same(table._seat_panel_player, flat.seat_panels[0],
		"公共快照重接线遇到失效 renderer 时应回退 2D input owner")
	for panel in flat.seat_panels:
		assert_true(panel._hand_tile_row.visible,
			"公共重接回退后四席 2D 手牌必须恢复")
	for river in flat.discard_rivers:
		assert_true((river as CanvasItem).visible,
			"公共重接回退后 2D 牌河必须恢复")
	for meld_area in flat.meld_areas:
		assert_true((meld_area as CanvasItem).visible,
			"公共重接回退后 2D 副露必须恢复")


func test_hidden_hands_stay_hidden_when_switching_from_hybrid_to_fallback() -> void:
	var table := await _make_table()
	table.set_hybrid_enabled(true)
	var state := BattleState.for_east_round(99101, 0, 1, 0, 0)
	table.bind_table_state(state, 0, 4)
	table._set_hand_rows_visible(false)

	table.set_hybrid_enabled(false)

	var flat := table._table as FourPlayerTable
	for panel in flat.seat_panels:
		assert_false((panel as SeatPanel)._hand_tile_row.visible,
			"发牌隐藏期间回退不得提前显示 2D 手牌")


func test_hidden_hands_stay_hidden_when_switching_from_fallback_to_hybrid() -> void:
	var table := await _make_table()
	var state := BattleState.for_east_round(99102, 0, 1, 0, 0)
	table.bind_table_state(state, 0, 4)
	table._set_hand_rows_visible(false)

	table.set_hybrid_enabled(true)

	var renderer := table._hybrid_table_3d as MahjongTable3D
	for tile in renderer._hand_tiles:
		assert_false((tile as Tile3D).visible,
			"发牌隐藏期间启用 hybrid 不得提前显示 3D 手牌")
	for seat_id in range(1, 4):
		for tile in renderer._opp_tiles[seat_id]:
			assert_false((tile as Tile3D).visible,
				"发牌隐藏期间启用 hybrid 不得提前显示对手 3D 手牌")


func test_winner_reveal_survives_hybrid_to_fallback_switch() -> void:
	var table := await _make_table()
	table.set_hybrid_enabled(true)
	var state := BattleState.for_east_round(99201, 0, 1, 0, 0)
	table.bind_table_state(state, 0, 4)
	var flat := table._table as FourPlayerTable
	flat.reveal_seat_hand_face_up(1, state.seats[1].hand, false)
	var win_id := (state.seats[1].hand.first() as Tile).id
	flat.mark_win_tile(win_id, 1)
	var renderer := table._hybrid_table_3d as MahjongTable3D
	assert_true(renderer._revealed_seats.has(1))
	assert_eq(_count_3d_win_markers(renderer, 1), 1)

	table.set_hybrid_enabled(false)

	var panel := flat.seat_panels[1] as SeatPanel
	assert_true(bool(panel.get("_force_reveal_hand")),
		"hybrid 回退后胜者亮牌状态必须迁移到 2D renderer")
	assert_eq(_count_2d_win_markers(panel), 1,
		"hybrid 回退后和牌张标记必须迁移到 2D renderer")


func test_winner_reveal_survives_fallback_to_hybrid_switch() -> void:
	var table := await _make_table()
	var state := BattleState.for_east_round(99202, 0, 1, 0, 0)
	table.bind_table_state(state, 0, 4)
	var flat := table._table as FourPlayerTable
	flat.reveal_seat_hand_face_up(1, state.seats[1].hand, false)
	var win_id := (state.seats[1].hand.first() as Tile).id
	flat.mark_win_tile(win_id, 1)
	assert_true(bool((flat.seat_panels[1] as SeatPanel).get(
		"_force_reveal_hand")))
	assert_eq(_count_2d_win_markers(flat.seat_panels[1]), 1)

	table.set_hybrid_enabled(true)

	var renderer := table._hybrid_table_3d as MahjongTable3D
	assert_true(renderer._revealed_seats.has(1),
		"启用 hybrid 后胜者亮牌状态必须迁移到 3D renderer")
	assert_eq(_count_3d_win_markers(renderer, 1), 1,
		"启用 hybrid 后和牌张标记必须迁移到 3D renderer")


func test_failed_renderer_fallback_restores_renderer_neutral_interaction_state() -> void:
	var table := await _make_table()
	table.set_hybrid_enabled(true)
	var state := BattleState.for_east_round(99301, 0, 1, 0, 0)
	table.bind_table_state(state, 0, 4)
	var renderer := table._hybrid_table_3d as MahjongTable3D
	var allowed := (renderer._hand_tiles[0] as Tile3D).tile_instance_id
	renderer.set_hand_clickable(true)
	renderer.dim_hand_except([allowed])
	renderer.set_selected_instances([allowed])
	renderer.free()

	table.set_hybrid_enabled(false)

	var fallback := (table._table as FourPlayerTable).seat_panels[0] as SeatPanel
	var interaction := fallback.get_hand_interaction_state()
	assert_true(bool(interaction.get("clickable", false)),
		"renderer 故障回退后本轮出牌仍应可点击")
	assert_true(bool(interaction.get("dim_active", false)),
		"renderer 故障回退后候选压暗应保留")
	assert_eq(interaction.get("dim_allowed_instances", []), [allowed])
	assert_eq(interaction.get("selected_instances", []), [allowed])


func test_real_public_refresh_order_restores_visuals_after_renderer_failure() -> void:
	var table := await _make_table()
	table.set_hybrid_enabled(true)
	var renderer := table._hybrid_table_3d as MahjongTable3D
	renderer.free()
	assert_false(is_instance_valid(renderer))
	var nbc := NetworkedBattleController.new("room-hybrid-fallback", 0)
	# sync_public_table_projection 的真实尾部顺序：先决策，再重接手牌输入。
	table._apply_public_decision_from_journal(nbc)
	table._wire_public_bottom_hand_clicks()

	var flat := table._table as FourPlayerTable
	assert_same(table._seat_panel_player, flat.seat_panels[0])
	for panel in flat.seat_panels:
		assert_true((panel as SeatPanel)._hand_tile_row.visible,
			"真实公共刷新顺序必须恢复 2D 手牌")
	for river in flat.discard_rivers:
		assert_true((river as CanvasItem).visible,
			"真实公共刷新顺序必须恢复 2D 牌河")
	for meld_area in flat.meld_areas:
		assert_true((meld_area as CanvasItem).visible,
			"真实公共刷新顺序必须恢复 2D 副露")


func test_reveal_cleared_on_2d_does_not_revive_when_hybrid_returns() -> void:
	var table := await _make_table()
	table.set_hybrid_enabled(true)
	var state := BattleState.for_east_round(99401, 0, 1, 0, 0)
	table.bind_table_state(state, 0, 4)
	var flat := table._table as FourPlayerTable
	var renderer := table._hybrid_table_3d as MahjongTable3D
	flat.reveal_seat_hand_face_up(1, state.seats[1].hand, false)
	flat.mark_win_tile((state.seats[1].hand.first() as Tile).id, 1)
	assert_true(renderer._revealed_seats.has(1))
	assert_eq(_count_3d_win_markers(renderer, 1), 1)
	table.set_hybrid_enabled(false)

	flat.clear_hand_reveals()
	table.set_hybrid_enabled(true)

	assert_false(renderer._revealed_seats.has(1),
		"2D owner 已清除的上局亮牌不得在重启 hybrid 时复活")
	assert_eq(_count_3d_win_markers(renderer, 1), 0,
		"2D owner 已清除的和牌张不得在重启 hybrid 时复活")
	for tile in renderer._opp_tiles[1]:
		assert_eq((tile as Tile3D).tile_id, -1,
			"2D owner 已清除的上局牌面不得在重启 hybrid 时再次泄漏")
