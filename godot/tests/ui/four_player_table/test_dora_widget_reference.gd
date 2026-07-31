extends GutTest

# 参考桌面左上角：五个紧凑宝牌槽 + 本场棒/立直棒计数，同一条内实时同步。


func _make_widget() -> DoraWidget:
	var widget := DoraWidget.new()
	add_child_autofree(widget)
	return widget


func test_reference_strip_geometry_green_backs_and_honba_counter() -> void:
	var widget := _make_widget()
	widget.update_indicators([])
	await get_tree().process_frame
	assert_eq(widget.size, Vector2(246, 50),
		"宝牌区必须为本场棒和立直棒保留同一条紧凑轮廓")
	for slot_index in range(5):
		var slot := widget.get_node_or_null("IndicatorSlot%d" % slot_index) as Control
		assert_not_null(slot, "宝牌槽 %d 存在" % slot_index)
		if slot == null:
			continue
		assert_eq(slot.size, Vector2(26, 34))
		assert_true(slot.get_node_or_null("GreenBack") is Panel,
			"未翻宝牌槽必须是独立深绿色牌背，不复用红色 back.png")
	var counter := widget.get_node_or_null("HonbaCount") as Label
	assert_not_null(counter)
	if counter != null:
		assert_eq(counter.text, "×0")
	assert_true(widget.get_node_or_null("HonbaStick") is Control)
	assert_true(widget.get_node_or_null("RiichiStick") is Control)
	var riichi_counter := widget.get_node_or_null("RiichiCount") as Label
	assert_not_null(riichi_counter)
	if riichi_counter != null:
		assert_eq(riichi_counter.text, "×0")


func test_update_state_reveals_indicator_and_updates_both_stick_counts() -> void:
	var widget := _make_widget()
	assert_true(widget.has_method("update_state"),
		"组合条需要一次性同步宝牌与本场数")
	if not widget.has_method("update_state"):
		return
	var update_method: Dictionary = {}
	for method in widget.get_method_list():
		if method.name == "update_state":
			update_method = method
			break
	assert_eq((update_method.get("args", []) as Array).size(), 3,
		"组合条 update_state 必须同时接收宝牌、本场棒和立直棒")
	if (update_method.get("args", []) as Array).size() != 3:
		return
	widget.call("update_state", [TileId.W5], 1, 3)
	await get_tree().process_frame
	var slot0 := widget.get_node_or_null("IndicatorSlot0") as Control
	assert_not_null(slot0)
	if slot0 != null:
		var face := slot0.get_node_or_null("Face") as CardTileBack
		assert_not_null(face)
		if face != null:
			assert_true(face._is_face_up)
			assert_eq(face._tile_id, TileId.W5)
	for slot_index in range(1, 5):
		var slot := widget.get_node_or_null("IndicatorSlot%d" % slot_index)
		assert_true(slot != null and slot.get_node_or_null("GreenBack") is Panel)
	var counter := widget.get_node_or_null("HonbaCount") as Label
	assert_not_null(counter)
	if counter != null:
		assert_eq(counter.text, "×1")
	var riichi_counter := widget.get_node_or_null("RiichiCount") as Label
	assert_not_null(riichi_counter)
	if riichi_counter != null:
		assert_eq(riichi_counter.text, "×3")


func test_initial_playable_bind_syncs_dora_and_honba_before_first_event() -> void:
	var playable: Control = load(
		"res://ui/four_player_table/playable_table.tscn").instantiate()
	add_child_autofree(playable)
	await get_tree().process_frame
	var state := BattleState.for_east_round(20260729, 0, 1, 2, 0)
	state.riichi_sticks = 2
	playable._bind_state_for_deal(state, 0, 4)
	await get_tree().process_frame
	var widget := playable._dora_widget as DoraWidget
	assert_not_null(widget)
	if widget == null:
		return
	assert_eq(widget.position, Vector2(180, 100),
		"组合条必须使用参考桌面 left=180/top=100 的舞台坐标")
	var slot0 := widget.get_node_or_null("IndicatorSlot0") as Control
	assert_not_null(slot0, "首次 bind 必须立即翻出第一张宝牌指示牌")
	if slot0 != null:
		var face := slot0.get_node_or_null("Face") as CardTileBack
		assert_not_null(face)
		if face != null:
			assert_eq(face._tile_id,
				state.dora_indicators.visible_tiles()[0].id)
	var counter := widget.get_node_or_null("HonbaCount") as Label
	assert_not_null(counter)
	if counter != null:
		assert_eq(counter.text, "×2")
	var riichi_counter := widget.get_node_or_null("RiichiCount") as Label
	assert_not_null(riichi_counter)
	if riichi_counter != null:
		assert_eq(riichi_counter.text, "×2")
	var center := (playable._table as FourPlayerTable).center_info as CenterInfoPanel
	assert_false(center._label_riichi.visible,
		"立直棒文字不得继续写在中央盘")
	assert_true(center._riichi_sticks_row == null \
		or not center._riichi_sticks_row.visible,
		"中央盘不得继续绘制立直棒图形")
