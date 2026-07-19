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
	# 用已有发牌后的 hand（13 或 14 张）
	var n: int = state.seats[0].hand.size()
	assert_gt(n, 0, "东风局开局应有手牌")
	table.bind_battle_state(state, 0, 4)
	assert_eq(table._hand_tiles.size(), n, "3D 手牌数应与 hand 一致")
