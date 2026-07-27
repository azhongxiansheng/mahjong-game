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


func test_strip_renders_real_tile_instance_and_clears() -> void:
	var st := _state_with_reveal()
	var instance := st.revealed_tiles[0].tile as TileInstance
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
	for tile in st.seats[1].hand._tiles:
		var instance := TileInstance.make(tile, 1)
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


func test_three_opponent_positions_keep_reveal_strips_screen_upright_and_in_bounds() -> void:
	var table = TABLE_SCENE.instantiate()
	add_child_autofree(table)
	var st := BattleState.for_east_round(342, 0, 1, 0, 0)
	for holder in [1, 2, 3]:
		var tile: Tile = st.seats[holder].hand._tiles[0]
		var instance := TileInstance.make(tile, holder)
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
