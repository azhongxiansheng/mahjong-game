extends GutTest

# E1-04（#228）：同一右侧规则抽屉、确定性重置、焦点与 8 模式 UI 输出。

const LOBBY_SCENE := "res://ui/lobby/lobby_shell.tscn"
const INTENT_SCRIPT := "res://ui/lobby/session_intent.gd"
const DESIGN_SIZE := Vector2(1600, 900)

const DRAWER_HOOKS := [
	"RuleDrawerHost",
	"RuleDrawerPanel",
	"DrawerBackButton",
	"DrawerTitle",
	"EastButton",
	"HanchanButton",
	"StandardButton",
	"TrashTalkButton",
	"DrawerCancelButton",
	"DrawerStartButton",
]

const UI_MODE_CASES := [
	["request_practice", "EastButton", "StandardButton", &"PRACTICE", &"EAST", &"STANDARD", &"PRACTICE_EAST_STANDARD"],
	["request_practice", "EastButton", "TrashTalkButton", &"PRACTICE", &"EAST", &"TRASH_TALK", &"PRACTICE_EAST_TRASH_TALK"],
	["request_practice", "HanchanButton", "StandardButton", &"PRACTICE", &"HANCHAN", &"STANDARD", &"PRACTICE_HANCHAN_STANDARD"],
	["request_practice", "HanchanButton", "TrashTalkButton", &"PRACTICE", &"HANCHAN", &"TRASH_TALK", &"PRACTICE_HANCHAN_TRASH_TALK"],
	["request_match", "EastButton", "StandardButton", &"PUBLIC_CASUAL", &"EAST", &"STANDARD", &"PUBLIC_EAST_STANDARD"],
	["request_match", "EastButton", "TrashTalkButton", &"PUBLIC_CASUAL", &"EAST", &"TRASH_TALK", &"PUBLIC_EAST_TRASH_TALK"],
	["request_match", "HanchanButton", "StandardButton", &"PUBLIC_CASUAL", &"HANCHAN", &"STANDARD", &"PUBLIC_HANCHAN_STANDARD"],
	["request_match", "HanchanButton", "TrashTalkButton", &"PUBLIC_CASUAL", &"HANCHAN", &"TRASH_TALK", &"PUBLIC_HANCHAN_TRASH_TALK"],
]

var _captured_intents: Array = []


func before_each() -> void:
	_captured_intents.clear()


func _spawn_lobby() -> LobbyShell:
	var host := Control.new()
	host.name = "RuleDrawerTestHost"
	host.size = DESIGN_SIZE
	add_child_autofree(host)
	var shell: LobbyShell = load(LOBBY_SCENE).instantiate()
	host.add_child(shell)
	assert_true(shell.has_signal("session_intent_confirmed"), "大厅必须公开 SessionIntent 确认信号")
	if shell.has_signal("session_intent_confirmed"):
		shell.connect("session_intent_confirmed", _on_intent_confirmed)
	return shell


func _on_intent_confirmed(intent: Variant) -> void:
	_captured_intents.append(intent)


func _require_hooks(shell: Node, hook_names: Array) -> bool:
	var all_found := true
	for hook_name in hook_names:
		var node := shell.get_node_or_null("%%%s" % hook_name)
		assert_not_null(node, "缺少稳定挂点 %%%s" % hook_name)
		all_found = all_found and node != null
	return all_found


func _select_toggle(shell: Node, hook_name: String) -> void:
	var button := shell.get_node_or_null("%%%s" % hook_name) as Button
	assert_not_null(button, "缺少可选按钮 %%%s" % hook_name)
	if button:
		button.button_pressed = true


func _assert_default_selection(shell: Node) -> void:
	assert_true((shell.get_node("%EastButton") as Button).button_pressed)
	assert_false((shell.get_node("%HanchanButton") as Button).button_pressed)
	assert_true((shell.get_node("%StandardButton") as Button).button_pressed)
	assert_false((shell.get_node("%TrashTalkButton") as Button).button_pressed)


func _assert_focus_target(source: Control, property_name: StringName, target: Control) -> void:
	var path: NodePath = source.get(property_name) as NodePath
	assert_false(path.is_empty(), "%s 必须显式配置 %s" % [source.name, property_name])
	if not path.is_empty():
		assert_same(source.get_node_or_null(path), target, "%s.%s 焦点目标不正确" % [source.name, property_name])


func test_practice_and_match_open_the_same_drawer_instance() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, ["RuleDrawerHost", "DrawerTitle", "DrawerCancelButton"]):
		return
	var host := shell.get_node("%RuleDrawerHost") as Control
	assert_false(host.visible)

	shell.request_practice()
	await get_tree().process_frame
	assert_true(host.visible, "电脑练习应打开规则抽屉")
	assert_eq(host.mouse_filter, Control.MOUSE_FILTER_STOP)
	assert_eq(host.get_child_count(), 1, "同一宿主只应持有一个规则抽屉")
	if host.get_child_count() != 1:
		return
	var drawer := host.get_child(0)
	assert_true((shell.get_node("%DrawerTitle") as Label).text.contains("电脑练习"))

	(shell.get_node("%DrawerCancelButton") as Button).pressed.emit()
	await get_tree().process_frame
	assert_false(host.visible)
	shell.request_match()
	await get_tree().process_frame
	assert_true(host.visible, "公共匹配应打开规则抽屉")
	assert_same(host.get_child(0), drawer, "两个一级入口必须复用同一抽屉实例")
	assert_true((shell.get_node("%DrawerTitle") as Label).text.contains("公共匹配"))


func test_drawer_exposes_stable_hooks_and_two_exclusive_groups() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, DRAWER_HOOKS):
		return

	shell.request_practice()
	await get_tree().process_frame
	var east := shell.get_node("%EastButton") as Button
	var hanchan := shell.get_node("%HanchanButton") as Button
	var standard := shell.get_node("%StandardButton") as Button
	var trash_talk := shell.get_node("%TrashTalkButton") as Button
	assert_not_null(east.button_group)
	assert_same(east.button_group, hanchan.button_group, "局制按钮必须同组互斥")
	assert_ne(east.button_group, standard.button_group, "局制与玩法必须是两组")
	assert_same(standard.button_group, trash_talk.button_group, "玩法按钮必须同组互斥")
	assert_false(east.button_group.allow_unpress)
	assert_false(standard.button_group.allow_unpress)

	hanchan.button_pressed = true
	assert_true(hanchan.button_pressed)
	assert_false(east.button_pressed)
	east.button_pressed = true
	assert_true(east.button_pressed)
	assert_false(hanchan.button_pressed)


func test_every_open_resets_to_east_standard_first_state() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, DRAWER_HOOKS):
		return

	# 冷启动首次打开。
	shell.request_practice()
	await get_tree().process_frame
	_assert_default_selection(shell)
	_select_toggle(shell, "HanchanButton")
	_select_toggle(shell, "TrashTalkButton")
	(shell.get_node("%DrawerCancelButton") as Button).pressed.emit()
	await get_tree().process_frame

	# practice → practice 仍重置。
	shell.request_practice()
	await get_tree().process_frame
	_assert_default_selection(shell)
	_select_toggle(shell, "HanchanButton")
	_select_toggle(shell, "TrashTalkButton")
	(shell.get_node("%DrawerCancelButton") as Button).pressed.emit()
	await get_tree().process_frame

	# practice → match 重置。
	shell.request_match()
	await get_tree().process_frame
	_assert_default_selection(shell)
	_select_toggle(shell, "HanchanButton")
	_select_toggle(shell, "TrashTalkButton")
	(shell.get_node("%DrawerCancelButton") as Button).pressed.emit()
	await get_tree().process_frame

	# match → match 仍重置。
	shell.request_match()
	await get_tree().process_frame
	_assert_default_selection(shell)


func test_all_eight_ui_combinations_emit_one_stable_intent_each() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, DRAWER_HOOKS):
		return
	var intent_script := load(INTENT_SCRIPT) as GDScript
	assert_not_null(intent_script)
	if intent_script == null:
		return
	for mode_case in UI_MODE_CASES:
		shell.call(mode_case[0])
		await get_tree().process_frame
		_select_toggle(shell, mode_case[1])
		_select_toggle(shell, mode_case[2])
		(shell.get_node("%DrawerStartButton") as Button).pressed.emit()
		await get_tree().process_frame
		assert_eq(_captured_intents.size(), 1, "每次确认只能输出一个 SessionIntent")
		var intent: Variant = _captured_intents.pop_front()
		assert_not_null(intent)
		assert_same(intent.get_script(), intent_script)
		assert_eq(intent.room_kind, mode_case[3])
		assert_eq(intent.round_kind, mode_case[4])
		assert_eq(intent.game_mode, mode_case[5])
		assert_eq(intent.selected_character_id, &"")
		assert_eq(intent.mode_id(), mode_case[6])


func test_cancel_back_and_escape_close_without_emitting_intent() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, ["RuleDrawerHost", "DrawerCancelButton", "DrawerBackButton"]):
		return
	for close_button_name in ["DrawerCancelButton", "DrawerBackButton"]:
		shell.request_practice()
		await get_tree().process_frame
		(shell.get_node("%%%s" % close_button_name) as Button).pressed.emit()
		await get_tree().process_frame
		assert_false((shell.get_node("%RuleDrawerHost") as Control).visible)
		assert_eq(_captured_intents.size(), 0)

	shell.request_match()
	await get_tree().process_frame
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	get_viewport().push_input(escape)
	await get_tree().process_frame
	assert_false((shell.get_node("%RuleDrawerHost") as Control).visible)
	assert_eq(_captured_intents.size(), 0, "Esc 不得提交 SessionIntent")


func test_open_and_close_move_focus_deterministically() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, DRAWER_HOOKS + ["PracticeButton", "MatchButton"]):
		return
	var focus_hooks := [
		"DrawerBackButton", "EastButton", "HanchanButton", "StandardButton",
		"TrashTalkButton", "DrawerCancelButton", "DrawerStartButton",
	]
	for hook_name in focus_hooks:
		assert_eq(
			(shell.get_node("%%%s" % hook_name) as Control).focus_mode,
			Control.FOCUS_ALL,
			"%%%s 必须支持键盘焦点" % hook_name
		)

	var back := shell.get_node("%DrawerBackButton") as Control
	var east := shell.get_node("%EastButton") as Control
	var hanchan := shell.get_node("%HanchanButton") as Control
	var standard := shell.get_node("%StandardButton") as Control
	var trash_talk := shell.get_node("%TrashTalkButton") as Control
	var cancel := shell.get_node("%DrawerCancelButton") as Control
	var start := shell.get_node("%DrawerStartButton") as Control
	_assert_focus_target(back, &"focus_neighbor_bottom", east)
	_assert_focus_target(back, &"focus_neighbor_right", east)
	_assert_focus_target(back, &"focus_neighbor_left", start)
	_assert_focus_target(east, &"focus_neighbor_right", hanchan)
	_assert_focus_target(hanchan, &"focus_neighbor_left", east)
	_assert_focus_target(east, &"focus_neighbor_bottom", standard)
	_assert_focus_target(standard, &"focus_neighbor_bottom", trash_talk)
	_assert_focus_target(trash_talk, &"focus_neighbor_bottom", cancel)
	_assert_focus_target(cancel, &"focus_neighbor_right", start)
	_assert_focus_target(start, &"focus_neighbor_left", cancel)

	shell.request_practice()
	await get_tree().process_frame
	back.grab_focus()
	var move_right := InputEventAction.new()
	move_right.action = &"ui_right"
	move_right.pressed = true
	get_viewport().push_input(move_right)
	await get_tree().process_frame
	assert_same(get_viewport().gui_get_focus_owner(), east, "返回键右移必须留在抽屉内")
	back.grab_focus()
	var move_left := InputEventAction.new()
	move_left.action = &"ui_left"
	move_left.pressed = true
	get_viewport().push_input(move_left)
	await get_tree().process_frame
	assert_same(get_viewport().gui_get_focus_owner(), start, "返回键左移必须在抽屉内闭环")
	cancel.pressed.emit()
	await get_tree().process_frame

	for open_method in ["request_practice", "request_match"]:
		var source_name := "PracticeButton" if open_method == "request_practice" else "MatchButton"
		var source := shell.get_node("%%%s" % source_name) as Button
		source.grab_focus()
		shell.call(open_method)
		await get_tree().process_frame
		assert_same(get_viewport().gui_get_focus_owner(), east, "抽屉打开后焦点应进入局制首项")
		cancel.pressed.emit()
		await get_tree().process_frame
		assert_same(get_viewport().gui_get_focus_owner(), source, "关闭后焦点应回到来源入口")


func test_open_drawer_stays_on_right_and_inside_1600_by_900() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, ["RuleDrawerHost", "RuleDrawerPanel"]):
		return
	shell.request_practice()
	await get_tree().create_timer(0.35).timeout
	var panel := shell.get_node("%RuleDrawerPanel") as Control
	var host := shell.get_node("%RuleDrawerHost") as Control
	var rect := panel.get_global_rect()
	var bounds := Rect2(shell.global_position, DESIGN_SIZE)
	assert_true(host.is_ancestor_of(panel), "规则面板必须位于既有 RuleDrawerHost 子树内")
	assert_true(bounds.encloses(rect), "展开后的规则抽屉不得越出设计画布")
	assert_gte(rect.position.x, 980.0, "规则抽屉必须从右侧展开")
	assert_gte(rect.size.x, 480.0, "规则抽屉宽度必须足以容纳二级选择")
	assert_lte(rect.size.x, 600.0, "抽屉不得遮住整个大厅")
	assert_gt(rect.size.y, 700.0, "抽屉应形成完整右侧二级面板")
	assert_almost_eq(rect.end.x, bounds.end.x, 1.0, "展开态右边缘必须贴齐 1600 设计边界")


func test_rule_drawer_consumes_real_lobby_material_assets() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, ["RuleDrawerPanel", "EastButton", "DrawerStartButton"]):
		return
	var panel_style := (shell.get_node("%RuleDrawerPanel") as Control).get_theme_stylebox("panel")
	assert_true(panel_style is StyleBoxTexture, "规则抽屉必须消费真实漆木 9-slice，而非纯色模拟")
	assert_eq((panel_style as StyleBoxTexture).texture.resource_path,
		"res://assets/ui/lobby_materials/lobby_lacquer_panel_9slice.png")
	var choice := shell.get_node("%EastButton") as Button
	var normal := choice.get_theme_stylebox("normal") as StyleBoxTexture
	var pressed := choice.get_theme_stylebox("pressed") as StyleBoxTexture
	assert_not_null(normal)
	assert_not_null(pressed)
	assert_eq(normal.texture.resource_path,
		"res://assets/ui/lobby_materials/lobby_washi_choice_9slice.png")
	assert_eq(pressed.texture.resource_path,
		"res://assets/ui/lobby_materials/lobby_choice_selected_9slice.png")


func test_rule_drawer_groups_sections_and_footer_without_dead_center_space() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, ["DrawerContentGroup", "ModeSection", "DrawerFooter"]):
		return
	shell.request_practice()
	await get_tree().create_timer(0.25).timeout
	var group := shell.get_node("%DrawerContentGroup") as Control
	var mode := shell.get_node("%ModeSection") as Control
	var footer := shell.get_node("%DrawerFooter") as Control
	assert_lt(footer.get_global_rect().position.y - mode.get_global_rect().end.y, 80.0,
		"操作区必须跟随选择组，不能隔着无意义大空白")
	assert_gt(group.get_global_rect().size.y, 360.0, "规则内容应形成完整纵向组")


func test_capture_tool_has_expanded_rule_drawer_shot() -> void:
	var script: GDScript = load("res://tools/capture_screens.gd")
	assert_not_null(script)
	assert_true(
		script.source_code.contains("shot_lobby_rule_drawer.png"),
		"#228 必须实际生成 /tmp/shot_lobby_rule_drawer.png"
	)
	assert_true(script.source_code.contains("func _capture_lobby_rule_drawer"))
	assert_true(script.source_code.contains("shell.request_practice()"), "截图必须真实打开练习规则抽屉")


func test_lobby_drawer_does_not_define_formal_config_or_runtime_services() -> void:
	for script_path in [
		"res://ui/lobby/lobby_shell.gd",
		"res://ui/lobby/rule_drawer.gd",
	]:
		if not ResourceLoader.exists(script_path):
			assert_true(false, "缺少脚本：%s" % script_path)
			continue
		var source: String = (load(script_path) as GDScript).source_code
		for forbidden in [
			"GameSessionConfig",
			"RunState",
			"run_flow",
			"WebSocket",
			"AudioStreamMicrophone",
			"PTT",
			"举报",
			"静音",
		]:
			assert_false(source.contains(forbidden), "#228 不得越界引入：%s" % forbidden)
