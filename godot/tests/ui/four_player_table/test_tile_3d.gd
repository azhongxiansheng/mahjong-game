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
