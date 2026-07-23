extends GutTest

# E2-01（#231）：练习场启动器只消费已验证 GameSessionConfig。

const CONFIG_SCRIPT := "res://session/game_session_config.gd"
const LAUNCHER_SCRIPT := "res://session/practice_session_launcher.gd"


func _load_config_script() -> GDScript:
	if not ResourceLoader.exists(CONFIG_SCRIPT):
		return null
	return load(CONFIG_SCRIPT) as GDScript


func _load_launcher_script() -> GDScript:
	if not ResourceLoader.exists(LAUNCHER_SCRIPT):
		return null
	return load(LAUNCHER_SCRIPT) as GDScript


func _make_practice_config(
	p_round_kind: StringName = &"EAST",
	p_game_mode: StringName = &"STANDARD",
	p_seed: int = 42
) -> Variant:
	var script := _load_config_script()
	if script == null:
		return null
	var intent := SessionIntent.new(&"PRACTICE", p_round_kind, p_game_mode, &"lin_yeche")
	var result: Variant = script.call(
		"from_intent", intent, p_seed, "practice-launch", "rv1", {}
	)
	if result == null or not result.ok:
		return null
	return result.config


func test_launcher_script_exists() -> void:
	assert_true(
		ResourceLoader.exists(LAUNCHER_SCRIPT),
		"#231 应新增 PracticeSessionLauncher"
	)
	var script := _load_launcher_script()
	assert_not_null(script)
	if script == null:
		return
	assert_true(
		String(script.source_code).contains("class_name PracticeSessionLauncher"),
		"必须暴露 class_name PracticeSessionLauncher"
	)


func test_launch_rejects_null_and_public_and_illegal() -> void:
	var launcher_script := _load_launcher_script()
	var config_script := _load_config_script()
	assert_not_null(launcher_script)
	assert_not_null(config_script)
	if launcher_script == null or config_script == null:
		return
	var launcher: Variant = launcher_script.new()
	assert_null(launcher.launch(null), "null Config 必须拒绝")

	# 公共配置不得由练习启动器实例化
	var pub_intent := SessionIntent.new(&"PUBLIC_CASUAL", &"EAST", &"STANDARD")
	var authority := {
		"room_kind": "PUBLIC_CASUAL",
		"round_kind": "EAST",
		"game_mode": "STANDARD",
		"participants": ["HUMAN", "AI", "AI", "AI"],
		"character_ids": ["lin_yeche", "qiu_jue", "bai_touli", "hua_ling"],
		"seed": 9,
		"session_id": "pub",
		"rule_version": "rv1",
	}
	var pub_result: Variant = config_script.call(
		"from_intent", pub_intent, 0, "", "", authority
	)
	assert_true(pub_result.ok)
	assert_null(
		launcher.launch(pub_result.config),
		"PUBLIC_CASUAL 必须被练习启动器拒绝"
	)

	# 绕过 create_validated，用裸构造产出非法练习席位，真实断言二次校验拒绝
	var illegal: Variant = config_script.new(
		&"PRACTICE",
		&"EAST",
		&"STANDARD",
		[&"AI", &"AI", &"AI", &"AI"],
		[&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"],
		1,
		"x",
		"rv"
	)
	assert_not_null(illegal, "裸构造应能产出未校验对象以测 launcher")
	assert_eq(illegal.participants[0], &"AI")
	assert_null(
		launcher.launch(illegal),
		"非 [HUMAN,AI,AI,AI] 练习配置必须被 launcher 二次校验拒绝"
	)

	# 空 session_id 非法
	var illegal_empty_sess: Variant = config_script.new(
		&"PRACTICE",
		&"EAST",
		&"STANDARD",
		[&"HUMAN", &"AI", &"AI", &"AI"],
		[&"lin_yeche", &"qiu_jue", &"bai_touli", &"hua_ling"],
		1,
		"",
		"rv"
	)
	assert_null(launcher.launch(illegal_empty_sess), "空 session_id 必须拒绝")


func test_launch_east_and_hanchan_configure_game_driver() -> void:
	var launcher_script := _load_launcher_script()
	assert_not_null(launcher_script)
	if launcher_script == null:
		return
	var launcher: Variant = launcher_script.new()

	var east_cfg: Variant = _make_practice_config(&"EAST", &"STANDARD", 100)
	assert_not_null(east_cfg, "需要可转换的练习 Config（依赖 GameSessionConfig）")
	if east_cfg == null:
		return
	var east_driver: Variant = launcher.launch(east_cfg)
	assert_not_null(east_driver, "练习 EAST 应返回 GameDriver")
	assert_true(east_driver is GameDriver)
	assert_eq(east_driver.seed, 100)
	assert_eq(east_driver.total_hands, 4)
	assert_eq(east_driver.hands_per_round, 4)

	var hanchan_cfg: Variant = _make_practice_config(&"HANCHAN", &"TRASH_TALK", 200)
	assert_not_null(hanchan_cfg)
	if hanchan_cfg == null:
		return
	var hanchan_driver: Variant = launcher.launch(hanchan_cfg)
	assert_not_null(hanchan_driver)
	assert_true(hanchan_driver is GameDriver)
	assert_eq(hanchan_driver.seed, 200)
	assert_eq(hanchan_driver.total_hands, 8)
	assert_eq(hanchan_driver.hands_per_round, 4)


func test_launch_sets_playable_battle_controller_factory() -> void:
	var launcher_script := _load_launcher_script()
	assert_not_null(launcher_script)
	if launcher_script == null:
		return
	var cfg: Variant = _make_practice_config(&"EAST", &"STANDARD", 33)
	assert_not_null(cfg)
	if cfg == null:
		return
	var launcher: Variant = launcher_script.new()
	var driver: Variant = launcher.launch(cfg)
	assert_not_null(driver)
	assert_true(driver.bc_factory.is_valid(), "应设置 bc_factory 以确保练习玩家席语义")
	var bc: Variant = driver.bc_factory.call(33, 0, false, TileId.E)
	assert_not_null(bc)
	assert_true(
		bc is PlayableBattleController,
		"bc_factory 必须产出 PlayableBattleController"
	)


func test_launcher_does_not_bind_ui_or_run_loop_or_legacy_runners() -> void:
	var launcher_script := _load_launcher_script()
	assert_not_null(launcher_script)
	if launcher_script == null:
		return
	var source: String = launcher_script.source_code
	for forbidden in [
		"LobbyShell",
		"RuleDrawer",
		"RunState",
		"NodeResult",
		"BattleNodeRunner",
		"PlayableTable",
		"run_to_end",
		"start_hand",
		"main.go",
		"WebSocket",
		"from_intent",
	]:
		assert_false(
			source.contains(forbidden),
			"启动器边界不得包含：%s" % forbidden
		)
	assert_true(source.contains("GameDriver"), "启动器应构造 GameDriver")
	assert_true(
		source.contains("PlayableBattleController") or source.contains("bc_factory"),
		"可设置 PlayableBattleController 工厂"
	)
