extends GutTest

const TABLE_SCENE := preload("res://ui/four_player_table/four_player_table.tscn")
const SEAT_SCENE := preload("res://ui/four_player_table/seat_panel.tscn")
const PLAYABLE_SCENE := preload("res://ui/four_player_table/playable_table.tscn")


func test_all_roster_portraits_resolve_to_dedicated_avatar_assets() -> void:
	for character in CharacterPool.all():
		var avatar_path := SeatPanel.resolve_avatar_path(character.portrait_path)
		assert_true(ResourceLoader.exists(avatar_path),
			"%s 应有可加载头像：%s" % [character.id, avatar_path])
		if character.id == &"lin_yeche":
			assert_eq(avatar_path,
				"res://assets/ui/lobby_stage/resident_lin_yeche_avatar.png")
		else:
			assert_eq(avatar_path,
				character.portrait_path.trim_suffix(".png") + "_avatar.png")


func test_persona_change_replaces_existing_portrait_with_avatar() -> void:
	var panel := SEAT_SCENE.instantiate() as SeatPanel
	add_child_autofree(panel)
	panel.set_ai_persona("旧角色", "AI",
		"res://assets/roguelike/characters/char_lingye.png")
	panel.set_ai_persona("裘绝", "AI",
		"res://assets/roguelike/characters/char_qiu_jue.png")
	var texture := panel.get_portrait_texture()
	assert_not_null(texture)
	assert_eq(texture.resource_path,
		"res://assets/roguelike/characters/char_qiu_jue_avatar.png")


func test_four_seats_bind_distinct_character_avatars_in_order() -> void:
	var table := TABLE_SCENE.instantiate() as FourPlayerTable
	add_child_autofree(table)
	table.bind_character_personas([
		&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling",
	])
	var expected := [
		"res://assets/ui/lobby_stage/resident_lin_yeche_avatar.png",
		"res://assets/roguelike/characters/char_qiu_jue_avatar.png",
		"res://assets/roguelike/characters/char_bai_touli_avatar.png",
		"res://assets/roguelike/characters/char_hua_ling_avatar.png",
	]
	assert_eq(table.seat_panels.size(), 4)
	for seat in range(4):
		var texture := table.seat_panels[seat].get_portrait_texture()
		assert_not_null(texture, "seat %d 应显示角色头像" % seat)
		if texture != null:
			assert_eq(texture.resource_path, expected[seat],
				"seat %d 的角色头像不得串位" % seat)

	# 公共场 recipient=2 时，绝对席 2 应旋转到本地 seat 0。
	table.bind_character_personas([
		&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling",
	], 2)
	var rotated_expected := [expected[2], expected[3], expected[0], expected[1]]
	for seat in range(4):
		assert_eq(table.seat_panels[seat].get_portrait_texture().resource_path,
			rotated_expected[seat], "公共投影 seat %d 应按 recipient 旋转" % seat)


func test_playable_table_character_binding_reaches_four_seat_projection() -> void:
	var playable := PLAYABLE_SCENE.instantiate() as PlayableTable
	add_child_autofree(playable)
	playable.bind_character_ids([
		&"qiu_jue", &"lin_yeche", &"hua_ling", &"bai_touli",
	])
	var table := playable.find_child("FourPlayerTable", true, false) as FourPlayerTable
	assert_not_null(table, "生产 PlayableTable 应持有四席投影视图")
	if table == null:
		return
	var expected_ids := ["qiu_jue", "lin_yeche", "hua_ling", "bai_touli"]
	for seat in range(4):
		var texture := table.seat_panels[seat].get_portrait_texture()
		assert_not_null(texture)
		if texture != null:
			assert_true(texture.resource_path.contains(expected_ids[seat])
				or (expected_ids[seat] == "lin_yeche"
					and texture.resource_path.contains("resident_lin_yeche")),
				"生产入口 seat %d 的角色身份不得串位" % seat)
