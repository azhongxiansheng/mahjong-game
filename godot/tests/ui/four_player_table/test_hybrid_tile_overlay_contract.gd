extends GutTest

const PLAYABLE_TABLE := preload("res://ui/four_player_table/playable_table.tscn")
const LOBBY_SCENE := preload("res://ui/lobby/lobby_shell.tscn")


func _make_hybrid() -> PlayableTable:
	var table := PLAYABLE_TABLE.instantiate() as PlayableTable
	add_child_autofree(table)
	table.set_hybrid_enabled(true)
	await get_tree().process_frame
	return table


func test_hybrid_is_transparent_tile_only_layer_between_board_and_hud() -> void:
	var table := await _make_hybrid()
	var flat := table._table as FourPlayerTable
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	assert_not_null(hybrid)
	if hybrid == null:
		return
	assert_true(hybrid.has_method("is_tile_overlay"),
		"hybrid renderer 必须显式声明 TILE_OVERLAY profile")
	if not hybrid.has_method("is_tile_overlay"):
		return
	assert_true(bool(hybrid.call("is_tile_overlay")))
	assert_true(hybrid._vp.transparent_bg, "牌层 viewport 背景必须透明")

	var table_node := flat.get_node("Table")
	var frame := flat.get_node("Table/BoardFrame")
	assert_same(hybrid.get_parent(), table_node,
		"透明牌层必须挂在 FourPlayerTable 的 2.5D 桌内")
	assert_eq(hybrid.get_index(), frame.get_index() + 1,
		"牌层必须位于 BoardFrame 之后、SeatPanel/CenterInfo 之前")
	assert_true((flat.get_node("TableStage") as CanvasItem).visible)
	assert_true((frame as CanvasItem).visible)
	assert_true(flat.center_info.visible, "中央盘继续由 2D HUD 显示")
	assert_almost_eq(table._action_panel.position.y, TableLayout.ACTION_BAR_RECT.position.y,
		0.01, "透明牌层不得沿用完整 3D 桌的 610px 操作带")

	assert_null(hybrid._world_root.get_node_or_null("Felt"))
	assert_null(hybrid._world_root.get_node_or_null("FrameRing"))
	assert_null(hybrid._world_root.get_node_or_null("CenterPlate"))
	for panel in flat.seat_panels:
		assert_false(panel._hand_tile_row.visible,
			"hybrid 开启时旧 2D 手牌必须隐藏")
	for river in flat.discard_rivers:
		assert_false((river as CanvasItem).visible)
	for meld_area in flat.meld_areas:
		assert_false((meld_area as CanvasItem).visible)


func test_overlay_binds_tiles_without_wall_dora_or_3d_riichi_sticks() -> void:
	var table := await _make_hybrid()
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(41101, 0, 1, 2, 1)
	state.seats[0].river.append_discard(Tile.new(TileId.W1, false, 0, 411010))
	table.bind_table_state(state, 0, 4)
	assert_gt(hybrid._hand_tiles.size(), 0)
	assert_eq(hybrid._river_tiles[0].size(), 1)
	assert_eq(hybrid._wall_tiles.size(), 0, "余牌只留中央盘数字")
	assert_eq(hybrid._dead_wall_tiles.size(), 0)
	assert_eq(hybrid._dora_tiles.size(), 0, "宝牌继续由 2D DoraWidget 显示")
	assert_eq(hybrid._riichi_stick_meshes.size(), 0,
		"立直信息继续由 2D HUD/河牌横置表达")


func test_overlay_reuses_entity_node_and_exposes_renderer_neutral_hand_query() -> void:
	var table := await _make_hybrid()
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(41102, 0, 1, 0, 0)
	table.bind_table_state(state, 0, 4)
	var first := hybrid._hand_tiles[0] as Tile3D
	var iid := first.tile_instance_id
	table.bind_table_state(state, 0, 4)
	var rebound: Tile3D = null
	for tile in hybrid._hand_tiles:
		if (tile as Tile3D).tile_instance_id == iid:
			rebound = tile as Tile3D
			break
	assert_same(rebound, first,
		"同一 tile_instance_id 重绑不得 queue_free 后整桌重建")
	assert_true(hybrid.has_method("get_hand_tile_render_info"),
		"renderer 必须统一返回牌面、赤宝与屏幕中心")
	if not hybrid.has_method("get_hand_tile_render_info"):
		return
	var info := hybrid.call("get_hand_tile_render_info", iid) as Dictionary
	assert_eq(int(info.get("tile_id", -1)), first.tile_id)
	assert_eq(bool(info.get("is_red_dora", false)), first.is_red_dora)
	assert_ne(info.get("screen_center", Vector2.ZERO), Vector2.ZERO)

	# 走真实 PlayableTable 点击入口，禁止再读取 renderer 私有 `_hand_slots`。
	table._on_player_tile_clicked(iid)
	assert_eq(int(table._pending_discard_fly.get("tile_id", -1)), first.tile_id)


func test_public_multi_pick_keeps_selected_tile_lifted_and_clears_on_cancel() -> void:
	var table := await _make_hybrid()
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(41103, 0, 1, 0, 0)
	table.bind_table_state(state, 0, 4)
	var tile := hybrid._hand_tiles[0] as Tile3D
	table._public_pick_kind = "PON"
	table._public_pick_selected.clear()
	table._on_public_pick_tile(tile.tile_instance_id)
	assert_true(bool(tile.visual_state().get("selected", false)),
		"公共多选已选实体必须保持抬起")
	table._cancel_public_pick()
	assert_false(bool(tile.visual_state().get("selected", false)),
		"取消公共多选必须清除 renderer 选中态")


func test_selected_tile_stays_physically_lifted_across_state_rebind() -> void:
	var table := await _make_hybrid()
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(411030, 0, 1, 0, 0)
	table.bind_table_state(state, 0, 4)
	var tile := hybrid._hand_tiles[0] as Tile3D
	hybrid.set_selected_instances([tile.tile_instance_id])
	await get_tree().create_timer(0.12).timeout
	assert_almost_eq(tile.position.y, tile._base_y + 0.018, 0.002)

	table.bind_table_state(state, 0, 4)

	assert_true(bool(tile.visual_state().get("selected", false)))
	assert_almost_eq(tile.position.y, tile._base_y + 0.018, 0.002,
		"状态刷新复用节点时，selected 牌必须继续保持物理抬起")


func test_public_multi_kan_first_pick_reaches_renderer_selection() -> void:
	var table := await _make_hybrid()
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(411031, 0, 1, 0, 0)
	table.bind_table_state(state, 0, 4)
	for kan_kind in ["MINKAN", "ANKAN"]:
		var tile := hybrid._hand_tiles[0] as Tile3D
		table._public_pick_kind = "KAN:%s" % kan_kind
		table._public_pick_selected.clear()
		table._on_public_pick_tile(tile.tile_instance_id)
		assert_eq(table._public_pick_selected, [tile.tile_instance_id],
			"%s 首张实体必须进入多选集合" % kan_kind)
		assert_true(bool(tile.visual_state().get("selected", false)),
			"%s 首张实体必须立即保持抬起" % kan_kind)
		table._cancel_public_pick()


func test_public_selection_cleared_while_on_2d_does_not_revive_in_3d() -> void:
	var table := await _make_hybrid()
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(411032, 0, 1, 0, 0)
	table.bind_table_state(state, 0, 4)
	var selected := hybrid._hand_tiles[0] as Tile3D
	table._public_pick_kind = "PON"
	table._on_public_pick_tile(selected.tile_instance_id)
	hybrid.set_hand_clickable(true)
	hybrid.dim_hand_except([selected.tile_instance_id])
	assert_true(bool(selected.visual_state().get("selected", false)))
	assert_true((hybrid._hand_tiles[1] as Tile3D).is_dim())

	table.set_hybrid_enabled(false)
	var fallback := (table._table as FourPlayerTable).seat_panels[0] as SeatPanel
	assert_true(bool(fallback.get("_hand_clickable")),
		"运行中回退必须把可点击状态迁移到可见 2D 手牌")
	var fallback_dimmed := 0
	for slot in fallback._hand_slots:
		var tile := slot.get_node_or_null("Tile") as CardTileBack
		var iid := int(slot.get_meta("hand_instance_id", -1))
		if bool(tile.get("_is_dim")):
			fallback_dimmed += 1
		assert_eq(bool(tile.get("_is_lifted")), iid == selected.tile_instance_id,
			"运行中回退必须迁移 exact selected instance")
	assert_gt(fallback_dimmed, 0,
		"运行中回退必须迁移当前候选压暗集合")
	table._cancel_public_pick()
	table.set_hybrid_enabled(true)
	var rebound := hybrid._tile_registry.get(
		"entity:%d" % selected.tile_instance_id) as Tile3D
	assert_not_null(rebound)
	if rebound != null:
		assert_false(bool(rebound.visual_state().get("selected", false)),
			"2D owner 清理后的选中态不得在重启 3D 时复活")
	for tile in hybrid._hand_tiles:
		assert_false((tile as Tile3D).is_dim(),
			"2D owner 清理后的候选压暗不得在重启 3D 时复活")


func test_switching_overlay_off_restores_only_2d_tile_entities() -> void:
	var table := await _make_hybrid()
	var flat := table._table as FourPlayerTable
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	table.set_hybrid_enabled(false)
	assert_false(hybrid.visible)
	assert_true((flat.get_node("TableStage") as CanvasItem).visible)
	assert_true((flat.get_node("Table/BoardFrame") as CanvasItem).visible)
	assert_true(flat.center_info.visible)
	for panel in flat.seat_panels:
		assert_true(panel._hand_tile_row.visible)
	for river in flat.discard_rivers:
		assert_true((river as CanvasItem).visible)
	for meld_area in flat.meld_areas:
		assert_true((meld_area as CanvasItem).visible)


func test_practice_coordinator_mounts_hybrid_by_default() -> void:
	var lobby := LOBBY_SCENE.instantiate() as LobbyShell
	add_child_autofree(lobby)
	await get_tree().process_frame
	var practice := lobby.get_node("PracticeMatchCoordinator") as PracticeMatchCoordinator
	var practice_table := practice.mount_playable_table()
	var practice_hybrid := practice_table.get("_hybrid_table_3d") as MahjongTable3D
	assert_not_null(practice_hybrid,
		"练习场生产入口默认启用透明 3D 牌层")
	if practice_hybrid != null:
		assert_true(practice_hybrid.visible)


func test_public_coordinator_mounts_hybrid_by_default() -> void:
	var lobby := LOBBY_SCENE.instantiate() as LobbyShell
	add_child_autofree(lobby)
	await get_tree().process_frame
	var public_coordinator := lobby.get_node("PublicMatchCoordinator") as PublicMatchCoordinator
	public_coordinator._mount_table()
	var public_table := public_coordinator.get_active_table() as PlayableTable
	assert_not_null(public_table)
	if public_table == null:
		return
	var public_hybrid := public_table.get("_hybrid_table_3d") as MahjongTable3D
	assert_not_null(public_hybrid,
		"公共桌生产入口默认启用透明 3D 牌层")
	if public_hybrid != null:
		assert_true(public_hybrid.visible)
