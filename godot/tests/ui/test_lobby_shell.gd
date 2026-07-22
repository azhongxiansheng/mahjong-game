extends GutTest

# E1-01 (#225)：生产入口换大厅壳 — 导航契约 GUT。
# 只断言入口壳 / main_scene / 稳定挂点；不覆盖 SessionIntent、GameSessionConfig、
# 规则抽屉或生产级视觉。

const LOBBY_SCENE := "res://ui/lobby/lobby_shell.tscn"
const RUN_FLOW_SCENE := "res://ui/run/run_flow.tscn"


func test_project_main_scene_points_to_lobby_shell() -> void:
	var main_scene: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	assert_eq(main_scene, LOBBY_SCENE, "生产 main_scene 必须是大厅入口壳")
	assert_ne(main_scene, RUN_FLOW_SCENE, "生产 main_scene 不得再是 Run Flow")


func test_lobby_scene_exists_and_instantiates_as_lobby_shell() -> void:
	assert_true(ResourceLoader.exists(LOBBY_SCENE), "lobby_shell.tscn 应存在")
	var packed: PackedScene = load(LOBBY_SCENE)
	assert_not_null(packed, "lobby_shell.tscn 应可 load")
	var node: Node = packed.instantiate()
	assert_not_null(node, "lobby_shell 应可实例化")
	assert_true(node is LobbyShell, "根节点 class_name 应为 LobbyShell")
	add_child_autofree(node)


func test_practice_hook_emits_practice_pressed() -> void:
	var shell: LobbyShell = load(LOBBY_SCENE).instantiate()
	add_child_autofree(shell)
	await get_tree().process_frame
	watch_signals(shell)
	shell.request_practice()
	assert_signal_emitted(shell, "practice_pressed")


func test_match_hook_emits_match_pressed() -> void:
	var shell: LobbyShell = load(LOBBY_SCENE).instantiate()
	add_child_autofree(shell)
	await get_tree().process_frame
	watch_signals(shell)
	shell.request_match()
	assert_signal_emitted(shell, "match_pressed")


func test_practice_and_match_buttons_call_hooks() -> void:
	var shell: LobbyShell = load(LOBBY_SCENE).instantiate()
	add_child_autofree(shell)
	await get_tree().process_frame
	watch_signals(shell)
	var practice_btn: Button = shell.get_node_or_null("%PracticeButton") as Button
	var match_btn: Button = shell.get_node_or_null("%MatchButton") as Button
	assert_not_null(practice_btn, "应有 %PracticeButton 挂点")
	assert_not_null(match_btn, "应有 %MatchButton 挂点")
	practice_btn.pressed.emit()
	assert_signal_emitted(shell, "practice_pressed")
	match_btn.pressed.emit()
	assert_signal_emitted(shell, "match_pressed")


func test_lobby_script_has_no_session_intent_or_game_session_config() -> void:
	var script: GDScript = load("res://ui/lobby/lobby_shell.gd")
	assert_not_null(script, "lobby_shell.gd 应存在")
	var source: String = script.source_code
	assert_false(source.contains("SessionIntent"), "E1-01 不得引入 SessionIntent")
	assert_false(source.contains("GameSessionConfig"), "E1-01 不得引入 GameSessionConfig")
	assert_false(source.contains("RunState"), "大厅壳不得依赖 RunState")
	assert_false(source.contains("run_flow.tscn"), "大厅壳不得跳转到 Run Flow")


func test_loading_screen_targets_lobby_not_run_flow() -> void:
	var script: GDScript = load("res://scripts/loading_screen.gd")
	assert_not_null(script)
	var source: String = script.source_code
	assert_true(source.contains("lobby_shell.tscn"), "loading_screen 应跳转大厅壳")
	assert_false(source.contains("run_flow.tscn"), "loading_screen 不得再跳转 Run Flow")


func test_settings_quit_returns_to_lobby_not_run_flow_reload() -> void:
	var script: GDScript = load("res://ui/settings_overlay.gd")
	assert_not_null(script)
	var source: String = script.source_code
	# 允许字面路径或 LobbyShell.SCENE_PATH 常量引用
	var targets_lobby: bool = (
		source.contains("lobby_shell.tscn")
		or source.contains("LobbyShell.SCENE_PATH")
	)
	assert_true(targets_lobby, "放弃/退出确认应 change_scene 到大厅壳")
	assert_true(
		source.contains("change_scene_to_file"),
		"退出路径须显式 change_scene_to_file（不得仅 reload 假定仍是 run_flow）"
	)
	assert_false(
		source.contains("reload_current_scene"),
		"退出确认不得再用 reload_current_scene 当作回主菜单"
	)
