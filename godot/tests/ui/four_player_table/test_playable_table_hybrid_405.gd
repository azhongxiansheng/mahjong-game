extends GutTest

const PLAYABLE_TABLE := preload("res://ui/four_player_table/playable_table.tscn")


func _mesh_screen_bounds(camera: Camera3D, instance: MeshInstance3D) -> Rect2:
	var bounds := instance.mesh.get_aabb()
	var first := camera.unproject_position(
		instance.global_transform * bounds.get_endpoint(0))
	var result := Rect2(first, Vector2.ZERO)
	for index in range(1, 8):
		result = result.expand(camera.unproject_position(
			instance.global_transform * bounds.get_endpoint(index)))
	return result


func _projected_edge_width(camera: Camera3D, z: float, half: float) -> float:
	var left := camera.unproject_position(Vector3(-half, 0.0, z))
	var right := camera.unproject_position(Vector3(half, 0.0, z))
	return absf(right.x - left.x)


func _tile_array_screen_bounds(camera: Camera3D, tiles: Array) -> Rect2:
	assert_false(tiles.is_empty())
	var first := tiles[0] as Tile3D
	var result := _mesh_screen_bounds(camera, first._mesh)
	for tile in tiles.slice(1):
		result = result.merge(_mesh_screen_bounds(camera, (tile as Tile3D)._mesh))
	return result


func _make_hybrid() -> PlayableTable:
	var table := PLAYABLE_TABLE.instantiate() as PlayableTable
	add_child_autofree(table)
	assert_true(table.has_method("set_hybrid_enabled"),
		"#405：PlayableTable 必须提供显式 hybrid opt-in/回退入口")
	if table.has_method("set_hybrid_enabled"):
		table.set_hybrid_enabled(true)
	await get_tree().process_frame
	return table


func test_hybrid_opt_in_keeps_one_2d_owner_and_one_visible_3d_entity_layer() -> void:
	var table := await _make_hybrid()
	if not table.has_method("set_hybrid_enabled"):
		return
	assert_true(table._table is FourPlayerTable,
		"hybrid 的状态→view owner 必须继续是生产 FourPlayerTable")
	var hybrid: Variant = table.get("_hybrid_table_3d")
	assert_true(hybrid is MahjongTable3D,
		"hybrid 必须挂载 production MahjongTable3D，不得依赖 examples")
	if not (hybrid is MahjongTable3D):
		return
	assert_true((hybrid as MahjongTable3D).visible)
	assert_false((table._table.get_node("TableStage") as CanvasItem).visible,
		"hybrid 时 2D 桌布实体必须隐藏，禁止双桌叠加")
	assert_true((table._table.get_node("Table") as CanvasItem).visible,
		"2D HUD owner 仍须留在真实生产树中")
	assert_eq(table._table.mouse_filter, Control.MOUSE_FILTER_PASS,
		"hybrid 根节点只允许空白区域穿透，不得禁用保留 HUD 子控件")
	assert_same(table.get_child(table.get_child_count() - 1), table._action_panel,
		"操作带必须继续位于 hybrid viewport 与 HUD 之上")


func test_real_battle_state_updates_four_hands_walls_rivers_and_melds() -> void:
	var table := await _make_hybrid()
	if not table.has_method("set_hybrid_enabled"):
		return
	var state := BattleState.for_east_round(405, 0, 1, 0, 0)
	var called := Tile.new(TileId.W3, false, 1, 40501)
	var chi_tiles: Array[Tile] = [
		called,
		Tile.new(TileId.W4, false, 0, 40502),
		Tile.new(TileId.W5, false, 0, 40503),
	]
	state.seats[0].melds.add_chi(chi_tiles, 1, called)
	state.seats[0].river.append_discard(Tile.new(TileId.T1, false, 0, 40520))
	state.seats[1].river.append_discard(Tile.new(TileId.S1, false, 1, 40521))
	assert_true(table.has_method("bind_table_state"),
		"#405：所有状态绑定必须经过一个 PlayableTable view owner")
	if not table.has_method("bind_table_state"):
		return
	table.bind_table_state(state, 0, 4)
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	assert_not_null(hybrid)
	if hybrid == null:
		return
	assert_eq(hybrid._hand_tiles.size(), state.seats[0].hand.size())
	for seat in range(1, 4):
		assert_eq(hybrid._opp_tiles[seat].size(), state.seats[seat].hand.size(),
			"四席暗手必须由同一真实 BattleState 驱动")
	assert_eq(hybrid._river_tiles[0].size(), 1)
	assert_eq(hybrid._river_tiles[1].size(), 1)
	assert_eq(hybrid._meld_tiles[0].size(), 3)
	assert_gt(hybrid._wall_tiles.size(), 0)
	var hand_instance_ids: Array = []
	for tile in hybrid._hand_tiles:
		hand_instance_ids.append((tile as Tile3D).tile_instance_id)
	for source in state.seats[0].hand.tiles():
		assert_has(hand_instance_ids, source.instance_id,
			"3D 可动作牌必须保持真实 tile_instance_id")
	assert_true((hybrid._opp_tiles[1][0] as Tile3D).tile_id < 0,
		"非 viewer 三席不得泄露牌面")


func test_hybrid_click_owner_and_2d_fallback_keep_business_chain() -> void:
	var table := await _make_hybrid()
	if not table.has_method("set_hybrid_enabled"):
		return
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	assert_not_null(hybrid)
	if hybrid == null:
		return
	assert_same(table.get("_seat_panel_player"), hybrid,
		"hybrid 的 3D 点击必须进入既有 TableDecisionAdapter seat port")
	watch_signals(hybrid)
	hybrid._hand_clickable = true
	hybrid._on_tile_clicked(Tile.INVALID_INSTANCE_ID)
	assert_signal_not_emitted(hybrid, "player_card_clicked",
		"非法实体必须在 3D 层 fail closed，不得绕过决策门控")
	var owner_before: Variant = table._table
	var adapter_before: Variant = table.get("_decision_adapter")
	table.set_hybrid_enabled(false)
	assert_same(table._table, owner_before,
		"切回 2D 不得重建权威 view owner 或业务状态")
	assert_same(table.get("_decision_adapter"), adapter_before,
		"切回 2D 不得替换现有命令链")
	assert_false(hybrid.visible)
	assert_true((table._table.get_node("TableStage") as CanvasItem).visible)


func test_hybrid_round_trip_disconnects_hidden_input_owner_and_public_reconnect_stays_current() -> void:
	var table := await _make_hybrid()
	var flat_owner := table._table.seat_panels[0] as SeatPanel
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	var click_callback := Callable(table, "_on_player_tile_clicked")
	var hover_callback := Callable(table, "_on_hand_tile_hover")
	var battle := PlayableBattleController.new(405, 0)
	table._bind_hand_decision_port(battle)
	assert_true(hybrid.player_card_clicked.is_connected(click_callback))
	assert_true(hybrid.hand_tile_hover.is_connected(hover_callback))
	assert_false(flat_owner.player_card_clicked.is_connected(click_callback),
		"隐藏 2D owner 不得残留点击连接")
	table.set_hybrid_enabled(false)
	assert_false(hybrid.player_card_clicked.is_connected(click_callback),
		"隐藏 3D owner 不得残留点击连接")
	assert_false(hybrid.hand_tile_hover.is_connected(hover_callback))
	assert_true(flat_owner.player_card_clicked.is_connected(click_callback))
	assert_same(table._decision_adapter._seat_panel, flat_owner)
	table.set_hybrid_enabled(true)
	table._wire_public_bottom_hand_clicks()
	assert_false(flat_owner.player_card_clicked.is_connected(click_callback),
		"公共重连/恢复不得重新激活隐藏 2D owner")
	assert_true(hybrid.player_card_clicked.is_connected(click_callback))
	assert_same(table._decision_adapter._seat_panel, hybrid,
		"公共重连后 adapter 必须继续指向当前可见 owner")


func test_hybrid_hides_only_table_entities_and_keeps_hud_interactive() -> void:
	var table := await _make_hybrid()
	var flat := table._table as FourPlayerTable
	var inventory := flat.get_node_or_null("InventoryButton") as Button
	assert_not_null(inventory)
	assert_true(inventory.visible, "库存/HUD 层不得随 2D 桌牌实体一起隐藏")
	assert_eq(inventory.mouse_filter, Control.MOUSE_FILTER_STOP,
		"保留 HUD 控件必须继续接收输入")
	assert_true(flat.caption_overlay.visible)
	assert_true(flat.reward_pool_hud.visible)
	assert_eq(flat.mouse_filter, Control.MOUSE_FILTER_PASS,
		"根节点只能让空白区域继续下传给 3D 拾取")


func test_hybrid_input_owner_survives_real_play_hand_start() -> void:
	var table := await _make_hybrid()
	if not table.has_method("set_hybrid_enabled"):
		return
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	var battle := PlayableBattleController.new(405, 0)
	# 直接验证 play_hand_async 调用的真实开局接线步骤，避免留下悬空整局协程。
	table._bind_hand_decision_port(battle)
	assert_same(table.get("_seat_panel_player"), hybrid,
		"开局不得把 hybrid 输入 owner 重置回已隐藏的 2D 手牌")
	var adapter: Variant = table.get("_decision_adapter")
	assert_not_null(adapter)
	if adapter != null:
		assert_same(adapter._seat_panel, hybrid,
			"真实 TableDecisionAdapter 必须绑定可见 3D 手牌")


func test_production_stage_has_coplanar_symmetric_zone_lines_and_camera_views() -> void:
	var table := await _make_hybrid()
	if not table.has_method("set_hybrid_enabled"):
		return
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	if hybrid == null:
		return
	var world := hybrid._world_root
	assert_null(world.get_node_or_null("BarrierField"),
		"生产 3D 桌不得出现 BoardFrame + BarrierField 双重边界")
	var lines := world.get_node_or_null("ZoneLines") as Node3D
	assert_not_null(lines, "中央盘到四席内沿必须有单层金属分区线")
	if lines == null:
		return
	assert_eq(lines.get_child_count(), 4, "四席分区线必须共用一套旋转对称几何")
	var south := lines.get_child(0) as MeshInstance3D
	var line_bounds := (south.mesh as ArrayMesh).get_aabb()
	assert_lte(line_bounds.size.z, 0.48,
		"分区线只允许中央附近短引导，不得闭合贯穿整席的大梯形")
	assert_lte(line_bounds.end.z, 0.72,
		"分区线不得延伸到桌面内沿形成调试边界")
	for seat in range(4):
		var line := lines.get_child(seat) as MeshInstance3D
		assert_true(line.mesh is ArrayMesh)
		assert_almost_eq(line.position.y, hybrid.TABLE_TOP_Y, 0.00001,
			"细线须与 felt 属于同一物理桌面")
		assert_true(line.transform.basis.is_equal_approx(
			Basis(Vector3.UP, deg_to_rad(-90.0 * seat)) * south.transform.basis),
			"四席分区线必须由同一几何逐席旋转 90°")
	assert_true(hybrid.has_method("set_camera_view"))
	if not hybrid.has_method("set_camera_view"):
		return
	var south_position: Vector3
	for view in [&"main", &"top", &"south", &"east", &"north", &"west"]:
		assert_true(hybrid.set_camera_view(view), "缺少诊断相机：%s" % view)
		if view == &"south":
			south_position = hybrid._camera.position
		elif view == &"north":
			assert_true(hybrid._camera.position.is_equal_approx(
				Vector3(-south_position.x, south_position.y, -south_position.z)),
				"南北诊断相机必须由同一几何中心旋转得到")


func test_main_camera_fills_safe_width_with_stable_near_far_perspective() -> void:
	var table := await _make_hybrid()
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(40506, 0, 1, 0, 0)
	table.bind_table_state(state, 0, 4)
	assert_true(hybrid.set_camera_view(&"main"))
	await get_tree().process_frame
	var frame := hybrid._world_root.get_node("FrameRing") as MeshInstance3D
	var bounds := _mesh_screen_bounds(hybrid._camera, frame)
	assert_between(bounds.size.x, 1700.0, 1760.0,
		"3D 外框应落入 2D 木轨宽度，而不是贴屏或消失，当前=%s" % bounds.size.x)
	assert_between(bounds.position.x, -80.0, -40.0)
	assert_between(bounds.end.x, 1640.0, 1680.0)
	var inner := hybrid.Table3DStage.FRAME_INNER_HALF
	var actual_corners := [
		hybrid._camera.unproject_position(Vector3(-inner, 0.0, -inner)),
		hybrid._camera.unproject_position(Vector3(inner, 0.0, -inner)),
		hybrid._camera.unproject_position(Vector3(-inner, 0.0, inner)),
		hybrid._camera.unproject_position(Vector3(inner, 0.0, inner)),
	]
	var plane := TableLayout.TABLE_PLANE_RECT
	var expected_corners := [
		TableLayout.project_table_point(plane.position),
		TableLayout.project_table_point(Vector2(plane.end.x, plane.position.y)),
		TableLayout.project_table_point(Vector2(plane.position.x, plane.end.y)),
		TableLayout.project_table_point(plane.end),
	]
	for index in range(4):
		assert_lte(actual_corners[index].distance_to(expected_corners[index]), 12.0,
			"3D 木框内沿角点必须与生产 2D 外框重合，corner=%d actual=%s expected=%s" \
			% [index, actual_corners[index], expected_corners[index]])
	var near_width := _projected_edge_width(hybrid._camera,
		hybrid.Table3DStage.FRAME_OUTER_HALF,
		hybrid.Table3DStage.FRAME_OUTER_HALF)
	var far_width := _projected_edge_width(hybrid._camera,
		-hybrid.Table3DStage.FRAME_OUTER_HALF,
		hybrid.Table3DStage.FRAME_OUTER_HALF)
	var near_far_ratio := near_width / far_width
	assert_between(near_far_ratio, 1.28, 1.30,
		"外沿近远比须与内沿 1.268 投影对应（外沿约 1.292），ratio=%s" \
		% near_far_ratio)
	var hand_bounds := _mesh_screen_bounds(hybrid._camera,
		(hybrid._hand_tiles[0] as Tile3D)._mesh)
	for tile in hybrid._hand_tiles.slice(1):
		hand_bounds = hand_bounds.merge(_mesh_screen_bounds(hybrid._camera,
			(tile as Tile3D)._mesh))
	var action_bottom := table._action_panel.position.y + table._action_panel.size.y
	assert_gte(hand_bounds.position.y, action_bottom + 5.0,
		"自家 3D 手牌必须完整落在现有操作带下方")
	assert_lte(hand_bounds.end.y, 865.0,
		"自家手牌不得与近端木框相撞或被裁切")


func test_production_frame_preserves_369_five_layer_continuous_profile() -> void:
	var table := await _make_hybrid()
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	var frame := hybrid._world_root.get_node("FrameRing") as MeshInstance3D
	assert_true(frame.mesh is ArrayMesh)
	var mesh := frame.mesh as ArrayMesh
	var expected := [
		"InnerSlope", "TopCrown", "OuterBevel", "SideWall", "LowerShell",
	]
	assert_eq(mesh.get_surface_count(), expected.size(),
		"production 木框必须完整复用 #369 的五层连续截面")
	for index in range(mini(mesh.get_surface_count(), expected.size())):
		assert_eq(mesh.surface_get_name(index), expected[index])
		assert_true(mesh.surface_get_material(index) is ShaderMaterial)
	var bounds := mesh.get_aabb()
	assert_gte(bounds.end.y, 0.034)
	assert_lte(bounds.position.y, -0.092)


func test_center_information_stays_compact_around_physical_plate() -> void:
	var table := await _make_hybrid()
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	for label in hybrid._center_side_labels:
		var radial := Vector2((label as Label3D).position.x,
			(label as Label3D).position.z).length()
		assert_lte(radial, 0.40,
			"四席点数必须与中央结构形成紧凑信息层级")
	assert_true(hybrid._center_label.text.contains("东"),
		"中央盘继续承载真实局风/回合语义")


func test_wall_uses_fixed_68_stack_topology_without_floating_dead_wall() -> void:
	var table := await _make_hybrid()
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(40507, 0, 1, 0, 0)
	table.bind_table_state(state, 0, 4)
	assert_eq(hybrid.WALL_STACK_COUNT, 68,
		"物理牌山拓扑容量必须固定为四边各 17 墩")
	var expected_wall_count := state.wall.live_wall_size() \
		+ state.wall.dead_wall_size() - state.wall.rinshan_taken()
	assert_eq(hybrid._wall_tiles.size(), expected_wall_count,
		"发牌后只显示权威 Wall 中尚未消费的真实牌，不得重复已发出的 52 张")
	assert_eq(hybrid._dead_wall_tiles.size(), 0,
		"王牌必须占外围固定槽位，不得在中央另建漂浮短墙")
	var expected_ids := {}
	var authority_tiles := state.wall.authority_tiles()
	for index in range(state.wall.draw_index(), authority_tiles.size() - state.wall.rinshan_taken()):
		expected_ids[(authority_tiles[index] as Tile).instance_id] = true
	var hand_ids := {}
	for seat in state.seats:
		for hand_tile in seat.hand.tiles():
			hand_ids[(hand_tile as Tile).instance_id] = true
	var actual_ids := {}
	var stable_positions := {}
	for tile in hybrid._wall_tiles:
		var wall_tile := tile as Tile3D
		var slot := int(wall_tile.get_meta("wall_slot", -1))
		var layer := int(wall_tile.get_meta("wall_layer", -1))
		assert_between(slot, 0, 67)
		assert_between(layer, 0, 1)
		assert_true(expected_ids.has(wall_tile.tile_instance_id),
			"牌山实体必须来自权威 Wall 的未消费 identity")
		assert_false(hand_ids.has(wall_tile.tile_instance_id),
			"已进入四席手牌的 tile_instance_id 不得同时出现在牌山")
		actual_ids[wall_tile.tile_instance_id] = true
		stable_positions[wall_tile.tile_instance_id] = wall_tile.position
	assert_eq(actual_ids.size(), expected_ids.size(),
		"牌山 identity 必须与真实剩余物理牌一一对应")
	for _draw in range(10):
		state.wall.draw()
	table.bind_table_state(state, 0, 4)
	assert_eq(hybrid._wall_tiles.size(), expected_wall_count - 10,
		"额外摸 10 张后只移除 draw order 对应的 10 张真实牌")
	for tile in hybrid._wall_tiles:
		var wall_tile := tile as Tile3D
		assert_true(stable_positions.has(wall_tile.tile_instance_id))
		assert_true(wall_tile.position.is_equal_approx(
			stable_positions[wall_tile.tile_instance_id]),
			"剩余牌山实体不得因张数变化重新居中或漂移")


func test_wall_identity_rebuilds_when_authoritative_wall_changes_at_same_cursor() -> void:
	var table := await _make_hybrid()
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	var first := BattleState.for_east_round(40508, 0, 1, 0, 0, TileId.E, 0)
	var restored := BattleState.for_east_round(40509, 0, 1, 0, 0, TileId.E, 1)
	assert_eq(first.wall.draw_index(), restored.wall.draw_index())
	table.bind_table_state(first, 0, 4)
	var first_ids := {}
	for tile in hybrid._wall_tiles:
		first_ids[(tile as Tile3D).tile_instance_id] = true
	table.bind_table_state(restored, 0, 4)
	for tile in hybrid._wall_tiles:
		var iid := (tile as Tile3D).tile_instance_id
		assert_false(first_ids.has(iid),
			"权威 Wall 已替换时不得沿用上一局牌山 identity")
		assert_gte(iid, Tile.TILES_PER_HAND,
			"hand_seq=1 的牌山必须进入新的 instance_id 命名空间")


func test_closeup_layout_keeps_hands_river_melds_and_hud_readable() -> void:
	var table := await _make_hybrid()
	var hybrid := table.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(40510, 0, 1, 0, 0)
	var next_iid := 500000
	for seat_id in range(4):
		for index in range(18):
			state.seats[seat_id].river.append_discard(Tile.new(
				TileId.ALL[(seat_id * 5 + index) % TileId.ALL.size()],
				false, seat_id, next_iid))
			next_iid += 1
	var pon: Array[Tile] = []
	for _index in range(3):
		pon.append(Tile.new(TileId.HAKU, false, 0, next_iid))
		next_iid += 1
	state.seats[0].melds.add_pon(pon, 2, pon[1])
	table.bind_table_state(state, 0, 4)
	await get_tree().process_frame
	var hand_bounds := _tile_array_screen_bounds(hybrid._camera, hybrid._hand_tiles)
	assert_gte(hand_bounds.size.x, 820.0,
		"自家牌须接近 2D 前景手牌宽度，当前=%s" % hand_bounds.size.x)
	assert_between(hand_bounds.position.y, 750.0, 805.0)
	assert_between(hand_bounds.end.y, 850.0, 880.0,
		"自家牌须贴近底部形成清晰前景，同时完整保留木框")
	var north_hand := _tile_array_screen_bounds(hybrid._camera, hybrid._opp_tiles[2])
	assert_gte(north_hand.position.y, 12.0, "对家暗手不得贴顶或裁切")
	var north_wall: Array = []
	for wall in hybrid._wall_tiles:
		if (wall as Tile3D).position.z < -0.6:
			north_wall.append(wall)
	var north_wall_bounds := _tile_array_screen_bounds(hybrid._camera, north_wall)
	assert_lte(north_hand.end.y + 6.0, north_wall_bounds.position.y,
		"对家手牌与内侧牌山须形成两条清晰空间带，不得视觉叠压")
	var east_hand := _tile_array_screen_bounds(hybrid._camera, hybrid._opp_tiles[1])
	var west_hand := _tile_array_screen_bounds(hybrid._camera, hybrid._opp_tiles[3])
	assert_lte(east_hand.end.x, 1435.0, "右家暗手须从桌边向内收")
	assert_gte(west_hand.position.x, 165.0, "左家暗手须从桌边向内收")
	var south_river := _tile_array_screen_bounds(hybrid._camera, hybrid._river_tiles[0])
	assert_lte(south_river.end.y, 625.0,
		"三排牌河不得侵入操作栏/副露带")
	var south_meld := _tile_array_screen_bounds(hybrid._camera, hybrid._meld_tiles[0])
	assert_between(south_meld.position.y, 650.0, 700.0,
		"南家副露须落在手牌上方的同席副露带")
	assert_lte(south_meld.end.y, hand_bounds.position.y - 8.0,
		"副露与自家手牌之间必须保留清晰间隔")
	for seat_id in range(4):
		var hand_rect := hand_bounds if seat_id == 0 else _tile_array_screen_bounds(
			hybrid._camera, hybrid._opp_tiles[seat_id])
		assert_false(hand_rect.intersects(TableLayout.SEAT_HUD_RECTS[seat_id]),
			"玩家头像/分数 HUD 不得遮挡对应席手牌，seat=%d" % seat_id)
