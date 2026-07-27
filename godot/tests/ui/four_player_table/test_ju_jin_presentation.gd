extends GutTest

const PT := preload("res://ui/four_player_table/playable_table.gd")
const ABILITY_ID := &"char_tetsuya_passive_v1"


func _event(type: StringName, actor: int, extra: Dictionary = {}) -> BattleEvent:
	return BattleEvent.make(type, actor, null, extra)


func test_real_growth_reaches_top_status_and_delta_toast_for_nonzero_local_seat() -> void:
	var bc := PlayableBattleController.new(350)
	assert_true(BossAbilityFactory.inject(bc.registry, ABILITY_ID, 2))
	bc.call("_emit", &"WIN_DECLARED_PRE", 2, null, {})
	bc.call("_emit", &"WIN_DECLARED_PRE", 2, null, {})

	var table = PT.new()
	add_child_autofree(table)
	table.set("_reward_local_seat", 2)
	table.bind_character_ids([&"qiu_jue", &"lian_yao", &"ju_jin", &"hua_ling"])
	table.set("_bc", bc)
	table.call("_sync_character_status")
	var capsule := table.get_node_or_null("CharacterStatusBadge") as Control
	assert_not_null(capsule)
	if capsule == null:
		return
	assert_true(capsule.visible)
	assert_eq(String(capsule.call("status_text")), "阶升 2 阶 · 下次 +3 番")
	var rect := capsule.get_rect()
	assert_gte(rect.position.y, 0.0)
	assert_lte(rect.end.y, TableLayout.TOP_BAR_H)
	assert_lte(rect.end.x, TableLayout.TABLE_W - 196.0)

	table._handle_event_toast(_event(&"SKILL_TRIGGERED", 2, {
		"skill_id": ABILITY_ID,
		"skill_name": "局进吾·阶升必杀",
		"han_delta": 3,
	}))
	assert_not_null(table._toast_label)
	assert_eq(table._toast_label.text, "◆ 局进吾 · 阶升必杀　+3 番")
	assert_eq(table._toast_label.position, Vector2(110, 4))
	assert_false(table._toast_label.get_rect().intersects(
		TableLayout.HAND_HOST_RECTS[2]), "触发 toast 不得遮挡对家手牌")


func test_result_rows_attribute_ability_han_without_double_counting_generic_bonus() -> void:
	var table = PT.new()
	add_child_autofree(table)
	var rows: Array = table.call("_result_bonus_rows", {
		"han": 6,
		"dora_count": 1,
		"ability_extra_han_count": 3,
		"ability_extra_han_sources": [{
			"ability_id": String(ABILITY_ID),
			"ability_name": "局进吾·阶升必杀",
			"han": 3,
		}],
	}, [{"name": "立直", "han": 1}])
	assert_eq(rows, [
		{"name": "宝牌", "han": 1},
		{"name": "能力加番（局进吾·阶升必杀）", "han": 3},
		{"name": "附加番", "han": 1},
	])


func test_playable_table_stays_free_of_ju_jin_ids() -> void:
	var source := FileAccess.get_file_as_string(
		"res://ui/four_player_table/playable_table.gd")
	assert_false(source.contains("ju_jin"))
	assert_false(source.contains(String(ABILITY_ID)))


func test_leaving_table_stops_ju_jin_voice_and_pending_queue() -> void:
	var am := get_tree().root.get_node_or_null("AudioManager")
	assert_not_null(am)
	if am == null:
		return
	am.stop_character_voice()
	assert_true(am.play_character_voice(&"ju_jin", &"entry", 10))
	assert_true(am.play_character_voice(&"ju_jin", &"ability", 20))
	assert_true(am.play_character_voice(&"ju_jin", &"win", 20))
	var table = PT.new()
	add_child(table)
	table.queue_free()
	await get_tree().process_frame
	assert_eq(am.current_character_voice_path(), "")
	assert_eq(am.character_voice_pending_count(), 0)
