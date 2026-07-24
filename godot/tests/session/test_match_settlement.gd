extends GutTest

# E2-05（#235）：整场结算排序 / 展示名 / 再来一局配置纯逻辑。


func _practice_config(
	seed_value: int = 42,
	session_id: String = "settle-src",
	round_kind: StringName = &"EAST",
	mode: StringName = &"STANDARD"
) -> GameSessionConfig:
	var intent := SessionIntent.new(&"PRACTICE", round_kind, mode, &"lin_yeche")
	var converted := GameSessionConfig.from_intent(
		intent, seed_value, session_id, "e2-05-v1", {}
	)
	assert_true(converted.ok, str(converted.error_code))
	return converted.config


func test_match_settlement_script_exists() -> void:
	assert_true(
		ResourceLoader.exists("res://session/match_settlement.gd"),
		"#235 应新增 MatchSettlement"
	)
	var script := load("res://session/match_settlement.gd") as GDScript
	assert_not_null(script)
	assert_true(
		String(script.source_code).contains("class_name MatchSettlement"),
		"必须暴露 class_name MatchSettlement"
	)


func test_build_seat_order_desc_and_tie_by_seat_asc() -> void:
	# 对齐 NetworkedEvent MATCH_SETTLED 契约：分降序，同分 seat 升序
	assert_eq(
		MatchSettlement.build_seat_order([24000, 25000, 26000, 25000]),
		[2, 1, 3, 0]
	)
	assert_eq(
		MatchSettlement.build_seat_order([30000, 25000, 25000, 20000]),
		[0, 1, 2, 3]
	)
	assert_eq(
		MatchSettlement.build_seat_order([32000, 28000, 22000, 18000]),
		[0, 1, 2, 3]
	)
	assert_eq(
		MatchSettlement.build_seat_order([100, 300, 300, 200]),
		[1, 2, 3, 0]
	)


func test_build_seat_order_rejects_invalid() -> void:
	assert_eq(MatchSettlement.build_seat_order([]), [])
	assert_eq(MatchSettlement.build_seat_order([1, 2, 3]), [])
	assert_eq(MatchSettlement.build_seat_order([1, 2, 3, 4, 5]), [])


func test_seat_display_name() -> void:
	assert_eq(MatchSettlement.seat_display_name(0), "你")
	assert_eq(MatchSettlement.seat_display_name(1), "AI 1")
	assert_eq(MatchSettlement.seat_display_name(2), "AI 2")
	assert_eq(MatchSettlement.seat_display_name(3), "AI 3")


func test_build_view_rows_follow_seat_order() -> void:
	var view: Dictionary = MatchSettlement.build_view(
		[24000, 25000, 26000, 25000], &"HANCHAN"
	)
	assert_eq(view.get("title", ""), "对局结束")
	assert_eq(view.get("round_kind"), &"HANCHAN")
	assert_eq(view.get("seat_order"), [2, 1, 3, 0])
	var rows: Array = view.get("rows", [])
	assert_eq(rows.size(), 4)
	assert_eq(rows[0].get("rank"), 1)
	assert_eq(rows[0].get("seat_id"), 2)
	assert_eq(rows[0].get("name"), "AI 2")
	assert_eq(rows[0].get("score"), 26000)
	assert_eq(rows[1].get("seat_id"), 1)
	assert_eq(rows[1].get("name"), "AI 1")
	assert_eq(rows[3].get("seat_id"), 0)
	assert_eq(rows[3].get("name"), "你")
	assert_eq(rows[3].get("rank"), 4)


func test_create_rematch_from_reuses_rules_new_identity() -> void:
	var src := _practice_config(7, "old-session", &"HANCHAN", &"TRASH_TALK")
	var rematch := GameSessionConfig.create_rematch_from(src, 99, "new-session")
	assert_not_null(rematch)
	assert_eq(rematch.room_kind, src.room_kind)
	assert_eq(rematch.round_kind, src.round_kind)
	assert_eq(rematch.game_mode, src.game_mode)
	assert_eq(rematch.participants, src.participants)
	assert_eq(rematch.character_ids, src.character_ids)
	assert_eq(rematch.rule_version, src.rule_version)
	assert_eq(rematch.seed, 99)
	assert_eq(rematch.session_id, "new-session")
	assert_ne(rematch.session_id, src.session_id)
	assert_ne(rematch.seed, src.seed)


func test_create_rematch_from_rejects_null_or_empty_id() -> void:
	assert_null(GameSessionConfig.create_rematch_from(null, 1, "x"))
	var src := _practice_config()
	assert_null(GameSessionConfig.create_rematch_from(src, 1, ""))


func test_settlement_modules_have_no_run_reward_paths() -> void:
	for path in [
		"res://session/match_settlement.gd",
		"res://ui/lobby/practice_match_coordinator.gd",
		"res://ui/four_player_table/match_settlement_panel.gd",
	]:
		assert_true(ResourceLoader.exists(path), "缺失文件: %s" % path)
		if not ResourceLoader.exists(path):
			continue
		var src := String((load(path) as GDScript).source_code)
		for forbidden in [
			"RunState",
			"NodeResult",
			"BattleNodeRunner",
			"run_flow",
			"hp_delta",
			"chapter_progress",
		]:
			assert_false(
				src.contains(forbidden),
				"%s 不得引用肉鸽路径 %s" % [path, forbidden]
			)
