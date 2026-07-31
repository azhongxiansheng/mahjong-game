extends GutTest


const SEAT_PANEL_SCENE := preload("res://ui/four_player_table/seat_panel.tscn")


class HandQuerySeatPanelSpy extends SeatPanel:
	var queried_instance_ids: Array[int] = []
	var response: Dictionary = {}

	func _ready() -> void:
		pass

	func get_hand_tile_render_info(tile_instance_id: int) -> Dictionary:
		queried_instance_ids.append(tile_instance_id)
		return response.duplicate()


func _tile(tile_id: int, instance_id: int, is_red_dora: bool = false) -> Tile:
	return Tile.new(tile_id, is_red_dora, 0, instance_id)


func test_seat_panel_renderer_neutral_query_rejects_invalid_and_miss() -> void:
	var panel := SEAT_PANEL_SCENE.instantiate() as SeatPanel
	add_child_autofree(panel)
	panel.set_seat_id(0)
	await get_tree().process_frame
	var seat := Seat.new(0, TileId.E)
	seat.hand.add(_tile(TileId.W5, 51201, true))
	panel.bind_seat(seat)
	await get_tree().process_frame

	assert_true(panel.has_method("get_hand_tile_render_info"),
		"SeatPanel 必须提供 renderer-neutral 手牌实体查询")
	if not panel.has_method("get_hand_tile_render_info"):
		return
	assert_eq(panel.call("get_hand_tile_render_info", Tile.INVALID_INSTANCE_ID), {},
		"非法 instance 必须立即返回空字典")
	assert_eq(panel.call("get_hand_tile_render_info", 51999), {},
		"合法但不存在的 instance 必须返回空字典")


func test_seat_panel_renderer_neutral_query_returns_identity_and_geometry() -> void:
	var panel := SEAT_PANEL_SCENE.instantiate() as SeatPanel
	add_child_autofree(panel)
	panel.set_seat_id(0)
	await get_tree().process_frame
	var seat := Seat.new(0, TileId.E)
	seat.hand.add(_tile(TileId.W5, 51301, true))
	seat.hand.add(_tile(TileId.T3, 51302))
	panel.bind_seat(seat)
	await get_tree().process_frame

	assert_true(panel.has_method("get_hand_tile_render_info"),
		"SeatPanel 必须提供 renderer-neutral 手牌实体查询")
	if not panel.has_method("get_hand_tile_render_info"):
		return
	var info := panel.call("get_hand_tile_render_info", 51301) as Dictionary
	assert_eq(int(info.get("tile_instance_id", -1)), 51301)
	assert_eq(int(info.get("tile_id", -1)), TileId.W5)
	assert_true(bool(info.get("is_red_dora", false)))
	assert_eq(info.get("screen_center", Vector2.ZERO),
		panel.get_hand_slot_global_center(51301))
	assert_ne(info.get("screen_center", Vector2.ZERO), Vector2.ZERO)


func test_four_player_table_2d_fallback_uses_seat_panel_public_query() -> void:
	var table := FourPlayerTable.new()
	var panel := HandQuerySeatPanelSpy.new()
	panel.response = {
		"tile_instance_id": 51401,
		"tile_id": TileId.S5,
		"is_red_dora": false,
		"screen_center": Vector2(321, 654),
	}
	table.seat_panels.clear()
	table.seat_panels.append(panel)

	var info := table.get_hand_tile_render_info(51401)
	assert_eq(panel.queried_instance_ids, [51401],
		"2D fallback façade 只能调用 SeatPanel 公开查询")
	assert_eq(info, panel.response)
	panel.free()
	table.free()


func test_seat_panel_2d_fallback_keeps_exact_selected_instances() -> void:
	var panel := SEAT_PANEL_SCENE.instantiate() as SeatPanel
	add_child_autofree(panel)
	panel.set_seat_id(0)
	await get_tree().process_frame
	var seat := Seat.new(0, TileId.E)
	seat.hand.add(_tile(TileId.W5, 51501))
	seat.hand.add(_tile(TileId.W5, 51502))
	panel.bind_seat(seat)
	await get_tree().process_frame

	assert_true(panel.has_method("set_selected_instances"),
		"2D fallback 必须实现与 3D renderer 相同的实体选中接口")
	if not panel.has_method("set_selected_instances"):
		return
	panel.call("set_selected_instances", [51502])
	var lifted_by_instance := {}
	for slot in panel._hand_slots:
		var tile := slot.get_node_or_null("Tile") as CardTileBack
		lifted_by_instance[int(slot.get_meta("hand_instance_id", -1))] = \
			bool(tile.get("_is_lifted"))
	assert_false(bool(lifted_by_instance.get(51501, true)))
	assert_true(bool(lifted_by_instance.get(51502, false)),
		"只能让已选中的物理牌保持抬起")

	# 同一权威状态刷新后，选中态仍由 renderer 接口恢复，而不是依赖节点偶然复用。
	panel.bind_seat(seat)
	await get_tree().process_frame
	for slot in panel._hand_slots:
		var tile := slot.get_node_or_null("Tile") as CardTileBack
		var iid := int(slot.get_meta("hand_instance_id", -1))
		assert_eq(bool(tile.get("_is_lifted")), iid == 51502)

	panel.call("set_selected_instances", [])
	for slot in panel._hand_slots:
		var tile := slot.get_node_or_null("Tile") as CardTileBack
		assert_false(bool(tile.get("_is_lifted")), "清理必须移除全部 2D 选中态")
