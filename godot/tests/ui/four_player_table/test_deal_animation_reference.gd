extends GutTest

const PLAYABLE_TABLE := preload("res://ui/four_player_table/playable_table.tscn")


func _make_bound_table(rng_seed: int = 20260720) -> PlayableTable:
	var table: PlayableTable = PLAYABLE_TABLE.instantiate()
	add_child_autofree(table)
	var state := BattleState.for_east_round(rng_seed, 0, 1, 0, 0)
	table._table.bind_battle_state(state, 0, 4)
	return table


func test_reference_deal_timing_constants():
	assert_eq(DealAnimation.FLIGHT, 0.115, "单张落牌动画固定 115ms")
	assert_eq(DealAnimation.DROP_OFFSET_Y, 14.0, "牌从目标上方 14px 落下")
	assert_eq(DealAnimation.BLOCK_INTERVAL, 0.095, "前三轮相邻玩家间隔 95ms")
	assert_eq(DealAnimation.LAST_BLOCK_INTERVAL, 0.065, "最后一张相邻玩家间隔 65ms")
	assert_eq(DealAnimation.SETTLE_TIME, 0.160, "末张后固定保留 160ms")
	assert_eq(DealAnimation.TOTAL_DURATION, 1.675, "完整发牌时长必须为 1675ms")


func test_reference_deal_schedule_is_4441_and_52_tiles():
	var anim := DealAnimation.new()
	add_child_autofree(anim)
	assert_true(anim.has_method("build_reference_schedule"),
		"发牌必须公开可测试的 4/4/4/1 时序")
	if not anim.has_method("build_reference_schedule"):
		return
	var schedule: Array = anim.build_reference_schedule()
	assert_eq(schedule.size(), 52)
	var counts := [0, 0, 0, 0]
	var blocks := [[], [], [], []]
	for entry in schedule:
		var seat_id: int = int(entry["seat"])
		counts[seat_id] += 1
		var block_id: int = int(entry["block"])
		if not blocks[block_id].has(seat_id):
			blocks[block_id].append(seat_id)
	assert_eq(counts, [13, 13, 13, 13])
	for block_id in range(4):
		assert_eq(blocks[block_id].size(), 4, "每轮必须覆盖四家")
	var per_seat_blocks := [0, 0, 0, 0]
	for entry in schedule:
		if int(entry["seat"]) == 0:
			per_seat_blocks[int(entry["block"])] += 1
	assert_eq(per_seat_blocks, [4, 4, 4, 1], "每家发牌必须严格 4/4/4/1")


func test_reference_schedule_delays_match_bundle_formula():
	var anim := DealAnimation.new()
	add_child_autofree(anim)
	if not anim.has_method("build_reference_schedule"):
		fail_test("缺 build_reference_schedule")
		return
	var schedule: Array = anim.build_reference_schedule()
	var expected_delay := {
		"0-0": 0.000, "0-1": 0.095, "0-2": 0.190, "0-3": 0.285,
		"1-0": 0.380, "1-1": 0.475, "1-2": 0.570, "1-3": 0.665,
		"2-0": 0.760, "2-1": 0.855, "2-2": 0.950, "2-3": 1.045,
		"3-0": 1.140, "3-1": 1.205, "3-2": 1.270, "3-3": 1.335,
	}
	for entry in schedule:
		var key := "%d-%d" % [int(entry["block"]), int(entry["seat"])]
		assert_almost_eq(float(entry["delay"]), float(expected_delay[key]), 0.0001,
			"同一轮同一家所有牌必须同时落下")


func test_real_table_collects_4x13_when_visible_and_hidden() -> void:
	var table := _make_bound_table()
	var visible_targets: Array = DealAnimation._collect_target_rects(table)
	assert_eq(visible_targets.size(), 4, "真实 2D 牌桌必须覆盖四家")
	for seat_targets in visible_targets:
		assert_eq((seat_targets as Array).size(), 13)
	table._set_hand_rows_visible(false)
	var hidden_targets: Array = DealAnimation._collect_target_rects(table)
	assert_eq(hidden_targets, visible_targets,
		"发牌隐藏只能切 visible，不得改变 getBoundingClientRect 等价几何")
	table._set_hand_rows_visible(true)


func test_second_hand_after_reveal_still_has_4x13_targets() -> void:
	var table := _make_bound_table(11)
	var previous_state := BattleState.for_east_round(11, 0, 1, 0, 0)
	var winner := table._table.seat_panels[2] as SeatPanel
	winner.reveal_hand_face_up(previous_state.seats[2].hand, false)
	assert_true(DealAnimation._collect_target_rects(table).is_empty(),
		"翻牌行不应冒充下一局发牌槽")
	assert_true(table.has_method("_bind_state_for_deal"),
		"生产开局绑定必须先清上局翻牌，再绑定新局状态")
	if not table.has_method("_bind_state_for_deal"):
		return
	var next_state := BattleState.for_east_round(12, 1, 2, 0, 0)
	table._bind_state_for_deal(next_state, 1, 4)
	var next_targets: Array = DealAnimation._collect_target_rects(table)
	assert_eq(next_targets.size(), 4)
	for seat_targets in next_targets:
		assert_eq((seat_targets as Array).size(), 13,
			"上局胜者在下一局也必须恢复 13 个真实牌背槽")


func test_play_async_removes_animation_before_returning() -> void:
	var table := _make_bound_table(21)
	var slot_ids: Array = []
	for panel in table._table.seat_panels:
		slot_ids.append((panel as SeatPanel)._deal_slots.map(
			func(slot: Control): return slot.get_instance_id()))
	table._set_hand_rows_visible(false)
	await DealAnimation.play_async(table)
	var remaining := table.get_children().filter(
		func(child: Node): return child is DealAnimation)
	assert_true(remaining.is_empty(),
		"play_async 返回前必须 tree_exited，不能与真手牌同帧重叠")
	table._set_hand_rows_visible(true)
	for seat_id in range(4):
		var current_ids: Array = (table._table.seat_panels[seat_id] as SeatPanel)._deal_slots.map(
			func(slot: Control): return slot.get_instance_id())
		assert_eq(current_ids, slot_ids[seat_id], "演出不得替换真实手牌槽")
