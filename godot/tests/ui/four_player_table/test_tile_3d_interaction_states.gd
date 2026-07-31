extends GutTest


func test_tile_visual_states_are_independent_and_have_deterministic_priority() -> void:
	var tile := Tile3D.new()
	add_child_autofree(tile)
	await get_tree().process_frame
	tile.setup_entity(TileId.W5, true, true, 413001)
	for method in [
		"set_dora", "set_hover_match", "set_latest_discard",
		"set_win_tile", "set_selected", "visual_state",
	]:
		assert_true(tile.has_method(method), "Tile3D 缺少视觉状态 API：%s" % method)
	if not tile.has_method("visual_state"):
		return
	tile.call("set_dora", true)
	tile.call("set_hover_match", true)
	tile.call("set_latest_discard", true)
	tile.call("set_win_tile", true)
	tile.call("set_selected", true)
	tile.set_dim(true)
	var state := tile.call("visual_state") as Dictionary
	assert_true(bool(state.get("dora", false)))
	assert_true(bool(state.get("hover_match", false)))
	assert_true(bool(state.get("latest_discard", false)))
	assert_true(bool(state.get("win_tile", false)))
	assert_true(bool(state.get("selected", false)))
	assert_true(bool(state.get("dim", false)))
	assert_eq(String(state.get("overlay", "")), "win",
		"win > latest > selected > hover_match > dora")
	assert_not_null(tile._mesh.material_overlay)


func test_selected_tile_stays_lifted_after_hover_exit() -> void:
	var tile := Tile3D.new()
	add_child_autofree(tile)
	await get_tree().process_frame
	tile.setup_entity(TileId.T3, true, false, 413002)
	tile.set_clickable(true)
	assert_true(tile.has_method("set_selected"))
	if not tile.has_method("set_selected"):
		return
	tile.call("set_selected", true)
	tile._on_mouse_entered()
	tile._on_mouse_exited()
	assert_true(bool(tile.get("_lifted")), "选中态必须在 hover 退出后保持抬起")
	tile.call("set_selected", false)
	assert_false(bool(tile.get("_lifted")))
