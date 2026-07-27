extends GutTest

const STRIP_PATH := "res://ui/four_player_table/seat_draw_forecast_strip.gd"
const TABLE_SCENE := preload("res://ui/four_player_table/four_player_table.tscn")
const Coordinator := preload("res://battle/seat_draw_forecast_coordinator.gd")


func _state(viewer: int) -> BattleState:
	var state := BattleState.for_east_round(347, 2, 1, 0, 0, TileId.E, 3)
	var registry := SkillRegistry.new()
	var scheduler := SkillScheduler.new(registry, state)
	assert_true(BossAbilityFactory.inject(registry, &"char_toki_passive_v1", viewer))
	assert_eq(scheduler.emit_event(
		BattleEvent.make(&"GAME_BEGIN", viewer)).triggered_skills.size(), 1)
	return state


func test_real_table_shows_four_relative_seats_only_to_owner_in_top_safe_area() -> void:
	assert_true(ResourceLoader.exists(STRIP_PATH), "须提供独立四席 UI strip")
	if not ResourceLoader.exists(STRIP_PATH):
		return
	var table = TABLE_SCENE.instantiate()
	add_child_autofree(table)
	var state := _state(2)
	table.set_local_seat(2)
	table.set_seat_draw_forecast_label("先示 · 四席窥运")
	table.bind_battle_state(state, 0, 4)
	assert_eq(table.seat_draw_forecast_count(), 4)
	assert_eq(table.seat_draw_forecast_slot_labels(), ["自家", "下家", "对家", "上家"])
	assert_eq(table.seat_draw_forecast_missing_count(), 0)
	var strip := table._seat_draw_forecast_strip as Control
	var rect := strip.get_global_rect()
	assert_true(rect.position.y >= TableLayout.TOP_BAR_H)
	assert_false(rect.intersects(TableLayout.HAND_HOST_RECTS[2]),
		"四席预测条不得覆盖对家手牌安全框")
	assert_true(rect.end.y < TableLayout.ACTION_BAR_RECT.position.y,
		"四席预测条不得遮牌河、手牌或操作栏")
	table.set_local_seat(0)
	table.bind_battle_state(state, 0, 4)
	assert_eq(table.seat_draw_forecast_count(), 0,
		"非能力拥有者不得看到预测条")


func test_wall_shortage_keeps_four_slots_and_renders_missing_as_dash() -> void:
	assert_true(ResourceLoader.exists(STRIP_PATH), "须提供独立四席 UI strip")
	if not ResourceLoader.exists(STRIP_PATH):
		return
	var table = TABLE_SCENE.instantiate()
	add_child_autofree(table)
	var state := _state(1)
	assert_true(state.wall.set_draw_index(state.wall.live_end_index() - 2))
	var skill: SkillResource = null
	# 测试仅需用同一 params 重算；从 reveal 记录反推 viewer 后构造真实 ability。
	var registry := SkillRegistry.new()
	assert_true(BossAbilityFactory.inject(registry, &"char_toki_passive_v1", 1))
	for entry in registry.get_all_entries():
		skill = entry.skill as SkillResource
	if skill != null:
		skill.params = {
			"seat_draw_forecast_active": true,
			"seat_draw_forecast_hand_seq": state.hand_seq,
			"seat_draw_forecast_viewer": 1,
			"seat_draw_forecast_pending": [0, 1, 2, 3],
		}
		Coordinator.recompute(state, skill)
	table.set_local_seat(1)
	table.set_seat_draw_forecast_label("先示 · 四席窥运")
	table.bind_battle_state(state, 0, 4)
	assert_eq(table.seat_draw_forecast_count(), 2)
	assert_eq(table.seat_draw_forecast_missing_count(), 2)
	assert_eq(table.seat_draw_forecast_slot_texts().count("—"), 2)
