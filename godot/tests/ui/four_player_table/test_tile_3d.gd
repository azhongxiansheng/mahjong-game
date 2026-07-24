extends GutTest

# Tile3D / MahjongTable3D 基础结构


func test_tile_3d_mesh_has_six_surfaces() -> void:
	var mesh: ArrayMesh = Tile3D._build_box_mesh()
	assert_eq(mesh.get_surface_count(), 6, "立体牌应有 6 个面")


func test_tile_3d_setup_face_up() -> void:
	var t := Tile3D.new()
	add_child_autofree(t)
	t.setup(TileId.W5, true, false)
	assert_eq(t.tile_id, TileId.W5)
	assert_true(t.face_up)
	assert_not_null(t._mesh)


# E2-02 / #232：点击发 instance_id；tile_id 仅渲染
# Green 目标唯一：setup_entity；禁止 4 参 setup（生产尚未扩参 → parse error）
func test_tile_3d_setup_stores_instance_id_and_click_emits_it() -> void:
	var t := Tile3D.new()
	add_child_autofree(t)
	await get_tree().process_frame
	assert_true(t.has_method("setup_entity"),
		"Tile3D 须提供 setup_entity(tile_id, face_up, red, instance_id)")
	if not t.has_method("setup_entity"):
		return
	t.callv("setup_entity", [TileId.W5, true, true, 777])
	assert_eq(t.tile_id, TileId.W5, "tile_id 保留渲染")
	assert_true(t.is_red_dora)
	var stored_iid: Variant = t.get("tile_instance_id")
	assert_true(stored_iid != null, "setup_entity 须写入 tile_instance_id")
	if stored_iid == null:
		return
	assert_eq(int(stored_iid), 777)
	t.set_clickable(true)
	watch_signals(t)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	t._input_event(null, ev, Vector3.ZERO, Vector3.UP, 0)
	assert_signal_emitted(t, "tile_clicked")
	var params: Array = get_signal_parameters(t, "tile_clicked")
	assert_eq(int(params[0]), 777, "tile_clicked 发 instance_id，禁止 tile_id fallback")
	assert_ne(int(params[0]), TileId.W5)


func test_tile_3d_click_without_valid_instance_id_does_not_emit() -> void:
	var t := Tile3D.new()
	add_child_autofree(t)
	await get_tree().process_frame
	assert_true(t.has_method("setup_entity"),
		"Tile3D 须提供 setup_entity(tile_id, face_up, red, instance_id)")
	if not t.has_method("setup_entity"):
		return
	t.callv("setup_entity", [TileId.T1, true, false, Tile.INVALID_INSTANCE_ID])
	t.set_clickable(true)
	watch_signals(t)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	t._input_event(null, ev, Vector3.ZERO, Vector3.UP, 0)
	assert_signal_not_emitted(t, "tile_clicked",
		"无有效 instance_id 不可作为玩家动作提交")


func test_mahjong_table_3d_builds_viewport() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	assert_not_null(table._vp)
	assert_not_null(table._camera)
	assert_not_null(table._world_root)


func test_mahjong_table_3d_bind_hand() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var state := BattleState.for_east_round(42, 0, 1, 0, 0)
	var n: int = state.seats[0].hand.size()
	assert_gt(n, 0, "东风局开局应有手牌")
	table.bind_battle_state(state, 0, 4)
	assert_eq(table._hand_tiles.size(), n, "3D 手牌数应与 hand 一致")


func test_meld_rebuild_creates_tiles() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var tiles: Array[Tile] = [Tile.new(TileId.W1), Tile.new(TileId.W1), Tile.new(TileId.W1)]
	var pon := Meld.make_pon(tiles, 1)
	table._rebuild_melds(0, [pon])
	assert_eq(table._meld_tiles[0].size(), 3, "碰应有 3 张 3D 副露牌")


func test_tile_animate_to_sets_base() -> void:
	var t := Tile3D.new()
	add_child_autofree(t)
	t.setup(TileId.T5, true, false)
	t.animate_to(Vector3(0.2, 0.02, 0.3), Vector3(0, 90, 0), 0.01)
	await get_tree().create_timer(0.05).timeout
	assert_almost_eq(t._base_y, 0.02, 0.001)


func test_live_wall_and_dead_wall() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var state := BattleState.for_east_round(42, 0, 1, 0, 0)
	var live: int = state.wall.live_wall_size()
	assert_gt(live, 0, "开局应有 live wall")
	table.bind_battle_state(state, 0, 4)
	# 稀疏示意堆：最多 4 侧 × 8 叠 × 2 层
	assert_gt(table._wall_tiles.size(), 0, "应有牌山示意")
	assert_lte(table._wall_tiles.size(), MahjongTable3D.WALL_STACKS_PER_SIDE_MAX * 4 * 2)
	assert_eq(table._dead_wall_tiles.size(), 10, "王牌区示意 5 叠×2")


func test_center_sides_and_riichi_sticks() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var state := BattleState.for_east_round(7, 0, 1, 2, 3)
	state.seats[1].riichi.declared = true
	table.bind_battle_state(state, 0, 4)
	assert_eq(table._center_side_labels.size(), 4, "四方分数标签")
	assert_true(table._center_label.text.contains("本") or table._center_label.text.contains("局"), "中心应显示局/本场")
	assert_true(table._center_label.text.contains("余"), "中心应显示余张")
	# 池 3 根 + seat1 立直 1 根
	assert_eq(table._riichi_stick_meshes.size(), 4, "立直棒 = 池 + 已立直家")
	assert_not_null(table._active_marker, "当前家高亮条")


func test_active_marker_moves_with_current_seat() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var state := BattleState.for_east_round(3, 0, 1, 0, 0)
	state.current_seat = 0
	table.bind_battle_state(state, 0, 4)
	var z0: float = table._active_marker.position.z
	state.current_seat = 2
	table.bind_battle_state(state, 0, 4)
	assert_lt(table._active_marker.position.z, z0, "current=2 时高亮应移向对家侧")


# E2-02：同 tile_id 多实体在 _rebuild_player_hand 后保持 original_index 相对序
func test_rebuild_player_hand_same_tile_id_preserves_original_order() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	var seat := Seat.new(0, TileId.E)
	# 原始序：W3,W1,W3,W1,W3 → 排序后 _hand_tiles instance 序 [11,13,10,12,14]
	seat.hand.add(Tile.new(TileId.W3, false, 0, 10))
	seat.hand.add(Tile.new(TileId.W1, false, 0, 11))
	seat.hand.add(Tile.new(TileId.W3, false, 0, 12))
	seat.hand.add(Tile.new(TileId.W1, false, 0, 13))
	seat.hand.add(Tile.new(TileId.W3, false, 0, 14))
	seat.last_drawn_instance_id = Tile.INVALID_INSTANCE_ID
	table._rebuild_player_hand(seat, false)
	assert_eq(table._hand_tiles.size(), 5)
	var order: Array = []
	for n in table._hand_tiles:
		assert_true(n is Tile3D)
		order.append(int((n as Tile3D).tile_instance_id))
	assert_eq(order, [11, 13, 10, 12, 14],
		"3D 手牌同 tile_id 必须按 Hand 原始下标保序")


# E2-02：非法 instance（含纯展示 INVALID）定位立即 ZERO
func test_get_hand_slot_invalid_instance_returns_zero() -> void:
	var table := MahjongTable3D.new()
	add_child_autofree(table)
	await get_tree().process_frame
	table.custom_minimum_size = Vector2(800, 600)
	table.size = Vector2(800, 600)
	# 纯展示 Tile3D：INVALID_INSTANCE_ID
	var display := Tile3D.new()
	table._world_root.add_child(display)
	display.setup_entity(TileId.W5, true, false, Tile.INVALID_INSTANCE_ID)
	table._hand_tiles.append(display)
	assert_eq(table.get_hand_slot_global_center(Tile.INVALID_INSTANCE_ID), Vector2.ZERO,
		"INVALID_INSTANCE_ID 不得定位到纯展示牌")
	assert_eq(table.get_hand_slot_global_center(-1), Vector2.ZERO)
	# 有效手牌存在时，非法 id 仍立即 ZERO
	var seat := Seat.new(0, TileId.E)
	seat.hand.add(Tile.new(TileId.W1, false, 0, 700))
	table._rebuild_player_hand(seat, false)
	assert_eq(table.get_hand_slot_global_center(Tile.INVALID_INSTANCE_ID), Vector2.ZERO)
	assert_ne(table.get_hand_slot_global_center(700), Vector2.ZERO, "合法 instance 仍可定位")
