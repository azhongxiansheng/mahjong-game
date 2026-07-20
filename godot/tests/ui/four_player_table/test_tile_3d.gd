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
