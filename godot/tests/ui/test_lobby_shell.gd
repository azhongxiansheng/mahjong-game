extends GutTest

# E1-01 (#225)：生产入口换大厅壳 — 导航契约 GUT。
# 只断言入口壳 / main_scene / 稳定挂点；SessionIntent 与规则抽屉由 #228 单独覆盖。

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


func test_lobby_uses_1600_by_900_design_geometry() -> void:
	assert_eq(DT.VIEW_W, 1600, "大厅设计宽度应锁定为 1600")
	assert_eq(DT.VIEW_H, 900, "大厅设计高度应锁定为 900")
	var shell: LobbyShell = load(LOBBY_SCENE).instantiate()
	add_child_autofree(shell)
	await get_tree().process_frame
	assert_eq(
		shell.custom_minimum_size,
		Vector2(1600, 900),
		"大厅根节点应声明 1600×900 最小设计尺寸"
	)


func test_lobby_copy_does_not_expose_internal_development_terms() -> void:
	var shell: LobbyShell = load(LOBBY_SCENE).instantiate()
	add_child_autofree(shell)
	await get_tree().process_frame
	var visible_copy := ""
	for label in shell.find_children("*", "Label", true, false):
		visible_copy += (label as Label).text + "\n"
	assert_true(visible_copy.contains("虚席馆"), "大厅应显示已确认的原创馆名")
	assert_true(visible_copy.contains("选择一种游戏方式"), "大厅应给玩家明确的入口提示")
	for forbidden in ["E1-01", "#225", "挂点", "后续接入", "导航壳"]:
		assert_false(
			visible_copy.contains(forbidden),
			"玩家可见文案不得暴露内部开发术语：%s" % forbidden
		)


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


func test_lobby_script_has_no_formal_session_config_or_run_dependency() -> void:
	var script: GDScript = load("res://ui/lobby/lobby_shell.gd")
	assert_not_null(script, "lobby_shell.gd 应存在")
	var source: String = script.source_code
	assert_false(source.contains("GameSessionConfig"), "E1-01 不得引入 GameSessionConfig")
	assert_false(source.contains("SaveSystem"), "大厅冷启动不得读取肉鸽存档")
	assert_false(source.contains("ContinuePrompt"), "大厅冷启动不得弹继续 Run 提示")
	assert_false(source.contains("has_save"), "大厅冷启动不得按 Run 存档分流")
	assert_false(source.contains("RunState"), "大厅壳不得依赖 RunState")
	assert_false(source.contains("run_flow.tscn"), "大厅壳不得跳转到 Run Flow")


func test_lobby_scene_tree_has_no_continue_run_prompt() -> void:
	var shell: LobbyShell = load(LOBBY_SCENE).instantiate()
	add_child_autofree(shell)
	await get_tree().process_frame
	assert_null(
		shell.find_child("*ContinuePrompt*", true, false),
		"大厅场景树不得挂载 ContinuePrompt"
	)


func test_loading_screen_targets_lobby_not_run_flow() -> void:
	var script: GDScript = load("res://scripts/loading_screen.gd")
	assert_not_null(script)
	var source: String = script.source_code
	assert_true(source.contains("lobby_shell.tscn"), "loading_screen 应跳转大厅壳")
	assert_false(source.contains("run_flow.tscn"), "loading_screen 不得再跳转 Run Flow")


func test_settings_has_no_run_or_save_system_exit_path() -> void:
	var script: GDScript = load("res://ui/settings_overlay.gd")
	assert_not_null(script)
	var source: String = script.source_code
	for forbidden in [
		"SaveSystem",
		"TutorialOverlay",
		"_on_tutorial_pressed",
		"_on_quit_run_pressed",
		"_on_quit_confirmed",
		"放弃本场",
		"重看新手引导",
	]:
		assert_false(source.contains(forbidden), "设置页不得保留旧入口：%s" % forbidden)


func test_capture_tool_includes_lobby_shell() -> void:
	var script: GDScript = load("res://tools/capture_screens.gd")
	assert_not_null(script, "capture_screens.gd 应存在")
	assert_true(
		script.source_code.contains(
			'["res://ui/lobby/lobby_shell.tscn", "lobby_shell"]'
		),
		"截图工具必须生成 /tmp/shot_lobby_shell.png"
	)
