extends GutTest

# E1-03（#227）：生产级 1600×900 大厅布局与稳定交互挂点。
# 规则选择态由 #228 接入；图鉴内容与音频业务归 #229。

const LOBBY_SCENE := "res://ui/lobby/lobby_shell.tscn"
const DESIGN_SIZE := Vector2(1600, 900)

const REQUIRED_CONTROLS := [
	"TopBar",
	"ResidentStage",
	"ResidentPortrait",
	"EntryRail",
	"PracticeButton",
	"MatchButton",
	"BottomBar",
	"NoticeButton",
	"HelpButton",
	"SettingsButton",
	"CharacterCodexButton",
	"ItemCodexButton",
	"RulesButton",
	"BgmButton",
	"SfxButton",
	"RuleDrawerHost",
]

const UTILITY_SIGNALS := {
	"NoticeButton": "notice_pressed",
	"HelpButton": "help_pressed",
	"SettingsButton": "settings_pressed",
	"CharacterCodexButton": "character_codex_pressed",
	"ItemCodexButton": "item_codex_pressed",
	"RulesButton": "rules_pressed",
	"BgmButton": "bgm_pressed",
	"SfxButton": "sfx_pressed",
}


func _spawn_lobby(size: Vector2 = DESIGN_SIZE) -> LobbyShell:
	var host := Control.new()
	host.name = "LobbyTestHost"
	host.size = size
	add_child_autofree(host)
	var shell: LobbyShell = load(LOBBY_SCENE).instantiate()
	host.add_child(shell)
	return shell


func _global_rect(node: Control) -> Rect2:
	return node.get_global_rect()


func test_production_lobby_exposes_all_stable_layout_hooks() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	for node_name in REQUIRED_CONTROLS:
		var node := shell.get_node_or_null("%%%s" % node_name)
		assert_not_null(node, "大厅应提供稳定挂点 %%%s" % node_name)
		assert_true(node is Control, "%%%s 应为 UI Control" % node_name)


func test_1600_by_900_regions_are_ordered_non_overlapping_and_in_bounds() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	await get_tree().process_frame

	var bounds := Rect2(shell.global_position, DESIGN_SIZE)
	var top := _global_rect(shell.get_node("%TopBar") as Control)
	var resident := _global_rect(shell.get_node("%ResidentStage") as Control)
	var entries := _global_rect(shell.get_node("%EntryRail") as Control)
	var bottom := _global_rect(shell.get_node("%BottomBar") as Control)

	for region in [top, resident, entries, bottom]:
		assert_true(bounds.encloses(region), "主要布局区域不得越出 1600×900 画布")
	assert_lte(top.end.y, resident.position.y, "顶栏应位于主内容上方")
	assert_lte(top.end.y, entries.position.y, "顶栏应位于入口区上方")
	assert_lte(resident.end.x, entries.position.x, "角色常驻区与右侧入口不得重叠")
	assert_lte(resident.end.y, bottom.position.y, "角色常驻区应位于底栏上方")
	assert_lte(entries.end.y, bottom.position.y, "入口区应位于底栏上方")
	assert_gt(resident.size.x, entries.size.x, "角色常驻区应是大厅视觉主体")


func test_layout_keeps_relative_structure_on_larger_viewport() -> void:
	var shell := _spawn_lobby(Vector2(1920, 1080))
	await get_tree().process_frame
	await get_tree().process_frame

	var resident := _global_rect(shell.get_node("%ResidentStage") as Control)
	var entries := _global_rect(shell.get_node("%EntryRail") as Control)
	var bottom := _global_rect(shell.get_node("%BottomBar") as Control)
	assert_lte(resident.end.x, entries.position.x, "放大窗口后左右主区仍不得重叠")
	assert_lte(entries.end.y, bottom.position.y, "放大窗口后入口区仍在底栏上方")
	assert_lte(bottom.end.x, 1920.0, "放大窗口后底栏不得越过右边界")
	assert_lte(bottom.end.y, 1080.0, "放大窗口后底栏不得越过下边界")


func test_resident_portrait_loads_first_original_character_texture() -> void:
	var characters: Array = CharacterPool.all()
	assert_gt(characters.size(), 0, "角色池至少应有一名原创角色")
	var resident: Character = characters[0] as Character
	assert_true(ResourceLoader.exists(resident.portrait_path), "默认角色立绘必须走真实资源路径")

	var shell := _spawn_lobby()
	await get_tree().process_frame
	var portrait := shell.get_node("%ResidentPortrait") as TextureRect
	assert_not_null(portrait.texture, "角色常驻区必须加载默认角色立绘")
	assert_eq(portrait.texture.resource_path, resident.portrait_path, "大厅应展示角色池第一名角色")
	assert_gt(portrait.texture.get_size().x, 0.0, "加载的角色纹理必须有效")
	assert_gt(portrait.texture.get_size().y, 0.0, "加载的角色纹理必须有效")


func test_entry_and_utility_buttons_emit_public_hook_signals() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	watch_signals(shell)

	(shell.get_node("%PracticeButton") as Button).pressed.emit()
	assert_signal_emitted(shell, "practice_pressed")
	(shell.get_node("%MatchButton") as Button).pressed.emit()
	assert_signal_emitted(shell, "match_pressed")
	for button_name in UTILITY_SIGNALS:
		var signal_name: String = UTILITY_SIGNALS[button_name]
		assert_true(shell.has_signal(signal_name), "大厅应声明 %s" % signal_name)
		(shell.get_node("%%%s" % button_name) as Button).pressed.emit()
		assert_signal_emitted(shell, signal_name)


func test_keyboard_focus_reaches_primary_and_utility_actions() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	var focusable_names := [
		"PracticeButton",
		"MatchButton",
		"NoticeButton",
		"HelpButton",
		"SettingsButton",
		"CharacterCodexButton",
		"ItemCodexButton",
		"RulesButton",
		"BgmButton",
		"SfxButton",
	]
	for node_name in focusable_names:
		var button := shell.get_node("%%%s" % node_name) as Button
		assert_eq(button.focus_mode, Control.FOCUS_ALL, "%%%s 必须支持键盘焦点" % node_name)
	var practice := shell.get_node("%PracticeButton") as Button
	var match_button := shell.get_node("%MatchButton") as Button
	assert_eq(
		practice.focus_neighbor_bottom,
		practice.get_path_to(match_button),
		"向下应从电脑练习移动到公共匹配"
	)
	assert_eq(
		match_button.focus_neighbor_top,
		match_button.get_path_to(practice),
		"向上应从公共匹配返回电脑练习"
	)


func test_rule_drawer_host_is_hidden_and_non_interactive_on_cold_start() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	var host := shell.get_node("%RuleDrawerHost") as Control
	assert_false(host.visible, "大厅冷启动不应直接展开规则抽屉")
	assert_eq(host.get_child_count(), 1, "#228 应在既有宿主内只挂一个规则抽屉")
	assert_eq(host.mouse_filter, Control.MOUSE_FILTER_IGNORE, "隐藏宿主不得拦截大厅输入")


func test_e1_03_does_not_cross_into_session_voice_or_run_implementation() -> void:
	var script: GDScript = load("res://ui/lobby/lobby_shell.gd")
	assert_not_null(script)
	for forbidden in [
		"GameSessionConfig",
		"run_flow",
		"RunState",
		"voice",
		"Voice",
		"PTT",
		"麦克风",
		"语音",
	]:
		assert_false(script.source_code.contains(forbidden), "#227 不得越界引入：%s" % forbidden)
