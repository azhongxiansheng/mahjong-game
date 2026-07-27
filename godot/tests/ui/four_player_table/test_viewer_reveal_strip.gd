extends GutTest

const Strip := preload("res://ui/four_player_table/viewer_reveal_strip.gd")
const TABLE_SCENE := preload("res://ui/four_player_table/four_player_table.tscn")


func _state_with_reveal(viewer_seat: int = 0) -> BattleState:
	var st := BattleState.for_east_round(340, 0, 1, 0, 0)
	var registry := SkillRegistry.new()
	var scheduler := SkillScheduler.new(registry, st)
	assert_true(BossAbilityFactory.inject(
		registry, &"char_akagi_passive_v1", viewer_seat))
	scheduler.emit_event(BattleEvent.make(&"TILE_DRAWN", viewer_seat))
	assert_eq(st.revealed_tiles.size(), 1,
		"真实 factory/hook/TILE_DRAWN 链必须产出一张 reveal")
	return st


func _state_with_bai_touli_reveal(viewer_seat: int = 0) -> BattleState:
	var st := BattleState.for_east_round(341, 0, 1, 0, 0)
	var registry := SkillRegistry.new()
	var scheduler := SkillScheduler.new(registry, st)
	assert_true(BossAbilityFactory.inject(
		registry, &"char_washizu_passive_v1", viewer_seat))
	var ctx := scheduler.emit_event(BattleEvent.make(&"GAME_BEGIN", viewer_seat))
	assert_eq(ctx.triggered_skills.size(), 1)
	return st


func _state_with_an_cheng_prediction(viewer_seat: int = 0) -> BattleState:
	var st := BattleState.for_east_round(344, 0, 1, 0, 0)
	var registry := SkillRegistry.new()
	var scheduler := SkillScheduler.new(registry, st)
	assert_true(BossAbilityFactory.inject(
		registry, &"char_awai_passive_v1", viewer_seat))
	var ctx := scheduler.emit_event(BattleEvent.make(&"GAME_BEGIN", viewer_seat))
	assert_eq(ctx.triggered_skills.size(), 1)
	return st


func _state_with_yuan_wall_top(viewer_seat: int = 0) -> BattleState:
	var st := BattleState.for_east_round(345, 0, 1, 0, 0)
	var registry := SkillRegistry.new()
	var scheduler := SkillScheduler.new(registry, st)
	assert_true(BossAbilityFactory.inject(
		registry, &"char_koromo_passive_v1", viewer_seat))
	var ctx := scheduler.emit_event(BattleEvent.make(&"TILE_DRAWN", viewer_seat))
	assert_eq(ctx.triggered_skills.size(), 1)
	return st


func test_strip_renders_real_tile_instance_and_clears() -> void:
	var st := _state_with_reveal()
	var instance := st.revealed_tiles[0].tile as TileSkillAnchor
	var strip = Strip.new()
	add_child_autofree(strip)
	strip.set_tiles([instance])
	assert_true(strip.visible)
	assert_eq(strip.revealed_count(), 1)
	assert_eq(strip.revealed_instance_ids(), [instance.tile.instance_id])
	strip.set_tiles([])
	assert_false(strip.visible)
	assert_eq(strip.revealed_count(), 0)


func test_thirteen_reveals_wrap_without_crossing_safe_compact_size() -> void:
	var st := BattleState.for_east_round(341, 0, 1, 0, 0)
	var instances: Array = []
	for tile in st.seats[1].hand.tiles():
		var instance := TileSkillAnchor.make(tile, 1)
		instance.holder_seat = 1
		instances.append(instance)
	var strip = Strip.new()
	add_child_autofree(strip)
	strip.set_tiles(instances)
	assert_eq(strip.revealed_count(), 13)
	assert_lte(strip.size.x, 205.0)
	assert_lte(strip.size.y, 120.0)


func test_real_table_only_shows_reveal_to_local_viewer() -> void:
	var table = TABLE_SCENE.instantiate()
	add_child_autofree(table)
	var st := _state_with_reveal(0)
	table.set_local_seat(0)
	table.bind_battle_state(st, 0, 4)
	assert_eq(table.seat_panels[1].viewer_reveal_count(), 1)
	table.set_local_seat(2)
	table.bind_battle_state(st, 0, 4)
	assert_eq(table.seat_panels[1].viewer_reveal_count(), 0,
		"切到未授权本地 viewer 后必须清除显示")


func test_bai_touli_real_table_shows_two_per_opponent_and_expires_on_tile_leave() -> void:
	var table = TABLE_SCENE.instantiate()
	add_child_autofree(table)
	var st := _state_with_bai_touli_reveal(0)
	table.set_local_seat(0)
	table.bind_battle_state(st, 0, 4)
	for holder in [1, 2, 3]:
		assert_eq(table.seat_panels[holder].viewer_reveal_count(), 2)
	var revealed := st.revealed_tiles[0] as Dictionary
	var instance := revealed.tile as TileSkillAnchor
	var holder := int(instance.holder_seat)
	assert_not_null(st.seats[holder].hand.take_by_instance_id(instance.tile.instance_id))
	table.bind_battle_state(st, 0, 4)
	assert_eq(table.seat_panels[holder].viewer_reveal_count(), 1,
		"牌离开目标手牌后对应揭示必须失效")


func test_three_opponent_positions_keep_reveal_strips_screen_upright_and_in_bounds() -> void:
	var table = TABLE_SCENE.instantiate()
	add_child_autofree(table)
	var st := BattleState.for_east_round(342, 0, 1, 0, 0)
	for holder in [1, 2, 3]:
		var tile: Tile = st.seats[holder].hand.first()
		var instance := TileSkillAnchor.make(tile, holder)
		instance.holder_seat = holder
		st.revealed_tiles.append({"tile": instance, "visible_to": [0]})
	table.set_local_seat(0)
	table.bind_battle_state(st, 0, 4)
	for holder in [1, 2, 3]:
		var panel := table.seat_panels[holder] as SeatPanel
		assert_eq(panel.viewer_reveal_count(), 1)
		var strip := panel._viewer_reveal_strip as Control
		var rotation := rad_to_deg(strip.get_global_transform().get_rotation())
		assert_almost_eq(rotation, 0.0, 0.01,
			"方位 %d 的私有信息必须保持屏幕正立" % holder)
		var rect := strip.get_global_rect()
		assert_true(rect.position.x >= 0.0 and rect.end.x <= TableLayout.TABLE_W)
		assert_true(rect.position.y >= TableLayout.TOP_BAR_H \
			and rect.end.y < TableLayout.ACTION_BAR_RECT.position.y,
			"揭示条不得越过顶栏或操作栏")


func test_an_cheng_prediction_reuses_top_reveal_strip_and_clears_after_draw() -> void:
	var table = TABLE_SCENE.instantiate()
	add_child_autofree(table)
	var st := _state_with_an_cheng_prediction(0)
	var expected: Tile = st.wall.peek_next_draw()
	table.set_local_seat(0)
	table.set_next_draw_reveal_label("预知")
	table.bind_battle_state(st, 0, 4)
	assert_eq(table.next_draw_reveal_count(), 1)
	assert_eq(table.next_draw_revealed_instance_ids(), [expected.instance_id])
	var strip := table._next_draw_reveal_strip as Control
	var rect := strip.get_global_rect()
	assert_true(rect.position.y >= TableLayout.TOP_BAR_H)
	assert_true(rect.end.y < TableLayout.ACTION_BAR_RECT.position.y,
		"预知条须留在顶部安全区，不遮操作栏")
	table.set_local_seat(1)
	table.bind_battle_state(st, 0, 4)
	assert_eq(table.next_draw_reveal_count(), 0, "其他本地 viewer 不得看到预知")
	table.set_local_seat(0)
	assert_eq(st.wall.draw().instance_id, expected.instance_id)
	table.bind_battle_state(st, 0, 4)
	assert_eq(table.next_draw_reveal_count(), 0, "摸牌后预知条须清除")


func test_yuan_wall_top_uses_three_tile_safe_gap_without_covering_hand_or_river() -> void:
	var table = TABLE_SCENE.instantiate()
	add_child_autofree(table)
	var st := _state_with_yuan_wall_top(0)
	table.set_local_seat(0)
	table.set_next_draw_reveal_label("潮见")
	table.bind_battle_state(st, 0, 4)
	assert_eq(table.next_draw_reveal_count(), 3)
	var expected := st.wall.peek_top_n(3)
	assert_eq(table.next_draw_revealed_instance_ids(), [
		(expected[0] as Tile).instance_id,
		(expected[1] as Tile).instance_id,
		(expected[2] as Tile).instance_id,
	])
	var strip := table._next_draw_reveal_strip as Control
	var rect := strip.get_global_rect()
	assert_gte(rect.position.y, 84.0, "潮见条必须下移到对家手牌后的顶部空档")
	assert_lte(rect.end.y, 134.0, "潮见条不得侵入 y=142 起的对家牌河安全区")
	assert_false(rect.intersects(TableLayout.HAND_HOST_RECTS[2]),
		"潮见条不得遮挡对家手牌")
	for crowded in TableLayout.crowded_state_rects():
		assert_false(rect.intersects(crowded), "潮见条不得遮挡任一牌河")
	assert_false(rect.intersects(TableLayout.ACTION_BAR_RECT))
	assert_false(rect.intersects(TableLayout.HAND_SAFE_RECT))
	table.set_local_seat(1)
	table.bind_battle_state(st, 0, 4)
	assert_eq(table.next_draw_reveal_count(), 0, "非 owner 本地 viewer 不得看到潮见")
