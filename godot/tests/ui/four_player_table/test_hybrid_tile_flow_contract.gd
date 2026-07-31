extends GutTest

const PLAYABLE_TABLE := preload("res://ui/four_player_table/playable_table.tscn")

var _next_iid := 430000


func _tile(tile_id: int, owner: int) -> Tile:
	var tile := Tile.new(tile_id, false, owner, _next_iid)
	_next_iid += 1
	return tile


func _make_hybrid() -> PlayableTable:
	var playable := PLAYABLE_TABLE.instantiate() as PlayableTable
	add_child_autofree(playable)
	playable.set_hybrid_enabled(true)
	await get_tree().process_frame
	return playable


func _hand_tiles(renderer: MahjongTable3D, seat_id: int) -> Array:
	return renderer._hand_tiles if seat_id == 0 else renderer._opp_tiles[seat_id]


func _yaw_delta(first: float, second: float) -> float:
	return absf(wrapf(first - second, -180.0, 180.0))


func _planar_step(first: Tile3D, second: Tile3D) -> float:
	return Vector2(first.position.x, first.position.z).distance_to(
		Vector2(second.position.x, second.position.z))


func test_four_hands_keep_13_tiles_and_post_draw_14th_gap() -> void:
	var playable := await _make_hybrid()
	var renderer := playable.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(43001, 0, 1, 0, 0)
	playable.bind_table_state(state, 0, 4)
	for seat_id in range(4):
		assert_eq(_hand_tiles(renderer, seat_id).size(), 13)

	for seat_id in range(4):
		var drawn := _tile(TileId.ALL[seat_id], seat_id)
		assert_true(state.seats[seat_id].hand.add(drawn))
		state.seats[seat_id].last_drawn_instance_id = drawn.instance_id
	playable.bind_table_state(state, 0, 4)

	for seat_id in range(4):
		var tiles := _hand_tiles(renderer, seat_id)
		assert_eq(tiles.size(), 14)
		var regular_step := _planar_step(tiles[12] as Tile3D, tiles[11] as Tile3D)
		var drawn_step := _planar_step(tiles[13] as Tile3D, tiles[12] as Tile3D)
		var scale_ := MahjongTable3D.SELF_HAND_SCALE if seat_id == 0 \
			else MahjongTable3D.OPPONENT_HAND_SCALE
		assert_almost_eq(regular_step,
			(Tile3D.TILE_W + 0.004) * scale_, 0.0001)
		assert_almost_eq(drawn_step,
			(Tile3D.TILE_W + 0.004 + 0.028) * scale_, 0.0001,
			"seat=%d：第 14 张必须保留独立摸牌间隔" % seat_id)


func test_four_rivers_render_24_tiles_riichi_rotation_and_latest_marker() -> void:
	var playable := await _make_hybrid()
	var renderer := playable.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(43002, 0, 1, 0, 0)
	const RIICHI_INDEX := 7
	for seat_id in range(4):
		for index in range(24):
			assert_true(state.seats[seat_id].river.append_discard(
				_tile(TileId.ALL[(seat_id * 7 + index) % TileId.ALL.size()], seat_id),
				index == RIICHI_INDEX))
	playable.bind_table_state(state, 0, 4)
	var base_yaws := [0.0, -90.0, 180.0, 90.0]
	for seat_id in range(4):
		var river: Array = renderer._river_tiles[seat_id]
		assert_eq(river.size(), 24)
		assert_lte(_yaw_delta((river[RIICHI_INDEX] as Tile3D).rotation_degrees.y,
			float(base_yaws[seat_id]) + 90.0), 0.01,
			"seat=%d：立直弃牌必须横置" % seat_id)
		for index in range(river.size()):
			assert_eq(bool((river[index] as Tile3D).visual_state().get(
				"latest_discard", false)), index == 23,
				"seat=%d index=%d：仅河末牌标记为最新弃牌" % [seat_id, index])


func test_hover_click_dim_and_same_tile_highlight_use_production_chain() -> void:
	var playable := await _make_hybrid()
	var renderer := playable.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(43003, 0, 1, 0, 0)
	var target_source := state.seats[0].hand.first() as Tile
	assert_true(state.seats[1].river.append_discard(
		_tile(target_source.id, 1)))
	playable.bind_table_state(state, 0, 4)
	var target: Tile3D = null
	for value in renderer._hand_tiles:
		if (value as Tile3D).tile_instance_id == target_source.instance_id:
			target = value as Tile3D
			break
	assert_not_null(target)
	if target == null:
		return
	renderer.set_hand_clickable(true)
	watch_signals(renderer)
	target._on_mouse_entered()
	assert_signal_emitted_with_parameters(renderer, "hand_tile_hover",
		[target.tile_id, true])
	assert_true(bool(target.get("_lifted")))
	assert_true(bool((renderer._river_tiles[1][0] as Tile3D).visual_state().get(
		"hover_match", false)), "hover 必须经 PlayableTable 联动全桌同牌")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	target._input_event(renderer._camera, click, Vector3.ZERO, Vector3.UP, 0)
	assert_signal_emitted_with_parameters(renderer, "player_card_clicked",
		[target.tile_instance_id])

	renderer.dim_hand_except([target.tile_instance_id])
	assert_false(target.is_dim())
	assert_true((renderer._hand_tiles[1] as Tile3D).is_dim())
	target._on_mouse_exited()
	assert_false(bool(target.get("_lifted")))
	assert_false(bool((renderer._river_tiles[1][0] as Tile3D).visual_state().get(
		"hover_match", false)))


func test_deal_visibility_and_settlement_stay_above_tile_overlay() -> void:
	var playable := await _make_hybrid()
	var renderer := playable.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(43004, 0, 1, 0, 0)
	playable.bind_table_state(state, 0, 4)
	playable._set_hand_rows_visible(false)
	for seat_id in range(4):
		for tile in _hand_tiles(renderer, seat_id):
			assert_false((tile as Tile3D).visible,
				"发牌演出必须隐藏 seat=%d 的 3D 手牌" % seat_id)
	playable._set_hand_rows_visible(true)
	for seat_id in range(4):
		for tile in _hand_tiles(renderer, seat_id):
			assert_true((tile as Tile3D).visible)
	playable._present_public_hand_settlement({
		"outcome": "TSUMO",
		"winner_seats": [0],
		"loser_seat": -1,
		"score_deltas": [6000, -2000, -2000, -2000],
		"scores": [31000, 23000, 23000, 23000],
	})
	var overlay := playable.get_public_hand_settlement_overlay()
	assert_not_null(overlay)
	assert_true(overlay.visible)
	assert_eq(overlay.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_gt(overlay.z_index, renderer.z_index,
		"结算遮罩必须位于透明牌层之上并拦截输入")


func test_winner_reveal_keeps_one_win_marker_across_rebind_and_clear() -> void:
	var playable := await _make_hybrid()
	var renderer := playable.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(43005, 0, 1, 0, 0)
	playable.bind_table_state(state, 0, 4)
	var win_id: int = (state.seats[1].hand.first() as Tile).id
	assert_true(renderer.has_method("mark_seat_win_tile"),
		"renderer 必须能按胜者席标记和牌张")
	if not renderer.has_method("mark_seat_win_tile"):
		return
	renderer.call("mark_seat_win_tile", 1, win_id)
	renderer.reveal_seat_hand_face_up(1, state.seats[1].hand, false)
	var marked := 0
	for tile in renderer._opp_tiles[1]:
		assert_true((tile as Tile3D).face_up)
		assert_gt((tile as Tile3D).transform.basis.y.normalized().dot(Vector3.UP),
			0.95, "对手和牌亮牌必须平放，使牌面朝向相机可读")
		if bool((tile as Tile3D).visual_state().get("win_tile", false)):
			marked += 1
	assert_eq(marked, 1)
	playable.bind_table_state(state, 0, 4)
	marked = 0
	for tile in renderer._opp_tiles[1]:
		if bool((tile as Tile3D).visual_state().get("win_tile", false)):
			marked += 1
	assert_eq(marked, 1, "重绑不得清掉胜者和牌张标记")
	renderer.clear_all_hand_reveals()
	for tile in renderer._opp_tiles[1]:
		assert_false(bool((tile as Tile3D).visual_state().get("win_tile", false)))


func test_playable_confirmed_winner_chain_marks_winning_seat_tile() -> void:
	var playable := await _make_hybrid()
	var renderer := playable.get("_hybrid_table_3d") as MahjongTable3D
	var battle := PlayableBattleController.new(43006, 0)
	playable._bc = battle
	playable.bind_table_state(battle.state, 0, 4)
	var winning_tile := battle.state.seats[2].hand.first() as Tile
	var anchor := TileSkillAnchor.make(winning_tile, 2)
	var event := BattleEvent.make(&"WIN_DECLARED", 2, anchor)
	playable._reveal_winner_hand(event)
	var marked := 0
	for tile in renderer._opp_tiles[2]:
		if bool((tile as Tile3D).visual_state().get("win_tile", false)):
			marked += 1
	assert_eq(marked, 1,
		"WIN_DECLARED → PlayableTable → renderer 必须标记真实胜者席")


func test_claimed_entities_animate_from_hand_and_river_into_meld() -> void:
	var playable := await _make_hybrid()
	var renderer := playable.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(43007, 0, 1, 0, 0)
	var tile_id := TileId.HAKU
	var companions: Array[Tile] = [_tile(tile_id, 0), _tile(tile_id, 0)]
	for _index in range(companions.size()):
		var removed := state.seats[0].hand.first() as Tile
		state.seats[0].hand.take_by_instance_id(removed.instance_id)
	for companion in companions:
		assert_true(state.seats[0].hand.add(companion))
	var called := _tile(tile_id, 1)
	assert_true(state.seats[1].river.append_discard(called))
	playable.bind_table_state(state, 0, 4)
	var before_positions := {}
	var before_nodes := {}
	for iid in [companions[0].instance_id, companions[1].instance_id,
			called.instance_id]:
		var node := renderer._tile_registry.get("entity:%d" % iid) as Tile3D
		assert_not_null(node)
		before_nodes[iid] = node
		before_positions[iid] = node.position

	for companion in companions:
		assert_not_null(state.seats[0].hand.take_by_instance_id(companion.instance_id))
	assert_same(state.seats[1].river.claim_last(called.instance_id), called)
	var meld_tiles: Array[Tile] = [called, companions[0], companions[1]]
	assert_not_null(state.seats[0].melds.add_pon(meld_tiles, 1, called))
	playable.bind_table_state(state, 0, 4)
	for iid in before_nodes.keys():
		var moved := renderer._tile_registry.get("entity:%d" % int(iid)) as Tile3D
		assert_same(moved, before_nodes[iid], "鸣牌必须复用权威 tile_instance_id 节点")
		assert_true(moved.scale.is_equal_approx(Vector3.ONE),
			"复用手牌/牌河节点进入副露时必须归一化为统一牌尺寸")
		assert_true(moved.position.is_equal_approx(before_positions[iid]),
			"鸣牌首帧必须从原手牌/河牌位置起飞")
	await get_tree().create_timer(0.3).timeout
	for iid in before_nodes.keys():
		var moved := renderer._tile_registry.get("entity:%d" % int(iid)) as Tile3D
		assert_false(moved.position.is_equal_approx(before_positions[iid]),
			"鸣牌动画结束后必须到达副露区")


func test_discard_reuses_hand_entity_and_animates_from_its_current_pose() -> void:
	var playable := await _make_hybrid()
	var renderer := playable.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(430071, 0, 1, 0, 0)
	playable.bind_table_state(state, 0, 4)
	var discarded := state.seats[0].hand.first() as Tile
	var key := "entity:%d" % discarded.instance_id
	var hand_node := renderer._tile_registry.get(key) as Tile3D
	var hand_position := hand_node.position
	assert_same(state.seats[0].hand.take_by_instance_id(
		discarded.instance_id), discarded)
	assert_true(state.seats[0].river.append_discard(discarded))

	playable.bind_table_state(state, 0, 4)
	var river_node := renderer._tile_registry.get(key) as Tile3D
	assert_same(river_node, hand_node,
		"弃牌必须按 tile_instance_id 复用原手牌节点")
	assert_true(river_node.position.is_equal_approx(hand_position),
		"原生弃牌动画首帧必须从真实手牌当前位置起飞")
	await get_tree().create_timer(0.25).timeout
	assert_false(river_node.position.is_equal_approx(hand_position),
		"原生弃牌动画结束后必须进入牌河目标位姿")


func test_added_kan_reuses_added_hand_entity_for_stacked_animation() -> void:
	var playable := await _make_hybrid()
	var renderer := playable.get("_hybrid_table_3d") as MahjongTable3D
	var state := BattleState.for_east_round(430072, 0, 1, 0, 0)
	var replaced := state.seats[0].hand.first() as Tile
	assert_not_null(state.seats[0].hand.take_by_instance_id(replaced.instance_id))
	var added := _tile(TileId.HATSU, 0)
	assert_true(state.seats[0].hand.add(added))
	var called := _tile(TileId.HATSU, 1)
	var pon := Meld.make_pon([
		_tile(TileId.HATSU, 0), called, _tile(TileId.HATSU, 0),
	], 1, 430400, called)
	assert_true(state.seats[0].melds.add_existing(pon))
	playable.bind_table_state(state, 0, 4)
	var key := "entity:%d" % added.instance_id
	var hand_node := renderer._tile_registry.get(key) as Tile3D
	var hand_position := hand_node.position

	assert_not_null(state.seats[0].hand.take_by_instance_id(added.instance_id))
	assert_true(state.seats[0].melds.promote_pon(pon.meld_id, added))
	playable.bind_table_state(state, 0, 4)
	var stacked_node := renderer._tile_registry.get(key) as Tile3D
	assert_same(stacked_node, hand_node,
		"加杠必须复用 added_tile_instance_id 对应的原手牌节点")
	if stacked_node == null:
		return
	assert_true(renderer._meld_tiles[0].has(stacked_node))
	assert_true(stacked_node.position.is_equal_approx(hand_position),
		"加杠动画首帧必须从 added tile 的真实手牌位姿起飞")
	await get_tree().create_timer(0.3).timeout
	assert_false(stacked_node.position.is_equal_approx(hand_position),
		"加杠动画结束后 added tile 必须叠到原碰横牌上方")


func test_hybrid_uses_native_discard_animation_without_second_2d_fly_tile() -> void:
	var playable := await _make_hybrid()
	var renderer := playable.get("_hybrid_table_3d") as MahjongTable3D
	assert_true(renderer.has_method("uses_native_tile_animations"))
	var direct_texture_rects_before := 0
	for child in playable.get_children():
		if child is TextureRect:
			direct_texture_rects_before += 1
	playable._pending_discard_fly = {
		"from": Vector2(400, 700),
		"tile_id": TileId.W1,
		"is_red": false,
	}
	playable._play_discard_fly_to_river()
	var direct_texture_rects_after := 0
	for child in playable.get_children():
		if child is TextureRect:
			direct_texture_rects_after += 1
	assert_eq(direct_texture_rects_after, direct_texture_rects_before,
		"3D 河牌已有原生移动动画时不得叠加第二张 2D 飞牌")
