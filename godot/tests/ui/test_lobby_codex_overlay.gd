extends GutTest

# E1-05（#229）：三个资料入口复用一个全屏层，并保持键盘焦点闭环。

const LOBBY_SCENE := "res://ui/lobby/lobby_shell.tscn"
const DESIGN_SIZE := Vector2(1600, 900)
const PAGE_CASES := [
	["CharacterCodexButton", &"characters"],
	["ItemCodexButton", &"items"],
	["RulesButton", &"rules"],
]


func _spawn_lobby() -> LobbyShell:
	var host := Control.new()
	host.name = "CodexTestHost"
	host.size = DESIGN_SIZE
	add_child_autofree(host)
	var shell := load(LOBBY_SCENE).instantiate() as LobbyShell
	host.add_child(shell)
	return shell


func _require_hooks(shell: LobbyShell, names: Array) -> bool:
	var ok := true
	for hook_name in names:
		var node := shell.get_node_or_null("%%%s" % hook_name)
		assert_not_null(node, "资料馆必须提供稳定挂点 %%%s" % hook_name)
		ok = ok and node != null
	return ok


func _press(shell: LobbyShell, hook_name: String) -> void:
	(shell.get_node("%%%s" % hook_name) as Button).pressed.emit()


func _visible_copy(root: Node) -> String:
	var result := ""
	for node in root.find_children("*", "Label", true, false):
		var label := node as Label
		if label.is_visible_in_tree():
			result += " " + label.text
	for node in root.find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree():
			result += " " + button.text
	return result


func test_codex_is_single_hidden_overlay_on_cold_start() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, ["CodexHost", "LobbyCodexOverlay"]):
		return
	var host := shell.get_node("%CodexHost") as Control
	assert_false(host.visible, "冷启动不得遮住大厅")
	assert_eq(host.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(shell.find_children("LobbyCodexOverlay", "", true, false).size(), 1,
		"大厅只能持有一个资料馆实例")


func test_three_lobby_entries_open_same_overlay_on_requested_page() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, [
		"CodexHost", "LobbyCodexOverlay", "CharacterCodexButton", "ItemCodexButton", "RulesButton",
	]):
		return
	var overlay := shell.get_node("%LobbyCodexOverlay")
	assert_true(overlay.has_method("get_current_page"), "资料馆须公开只读当前页用于稳定验收")
	if not overlay.has_method("get_current_page"):
		return
	for page_case in PAGE_CASES:
		_press(shell, page_case[0])
		await get_tree().process_frame
		assert_true((shell.get_node("%CodexHost") as Control).visible)
		assert_same(shell.get_node("%LobbyCodexOverlay"), overlay, "三个入口必须复用同一实例")
		assert_eq(overlay.call("get_current_page"), page_case[1], "入口应打开对应资料页")
	assert_eq(shell.find_children("LobbyCodexOverlay", "", true, false).size(), 1)


func test_codex_tabs_switch_visible_content_without_creating_pages() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, [
		"LobbyCodexOverlay", "CharacterCodexButton", "CodexCharacterTab", "CodexItemTab",
		"CodexRulesTab", "CodexContent",
	]):
		return
	_press(shell, "CharacterCodexButton")
	await get_tree().process_frame
	var overlay := shell.get_node("%LobbyCodexOverlay")
	var content := shell.get_node("%CodexContent")
	assert_true(_visible_copy(content).contains(CharacterPool.all()[0].display_name),
		"角色页必须渲染真实角色数据")

	_press(shell, "CodexItemTab")
	await get_tree().process_frame
	assert_eq(overlay.call("get_current_page"), &"items")
	assert_true(_visible_copy(content).contains("常驻道具"))
	assert_true(_visible_copy(content).contains("一次性道具"))

	_press(shell, "CodexRulesTab")
	await get_tree().process_frame
	assert_eq(overlay.call("get_current_page"), &"rules")
	var rules_copy := _visible_copy(content)
	assert_true(rules_copy.contains("东风战"))
	assert_true(rules_copy.contains("嘴强欢乐场"))
	assert_eq(shell.find_children("CodexContent", "", true, false).size(), 1,
		"切页应复用同一个内容宿主")


func test_close_button_and_escape_restore_focus_to_real_source() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, [
		"CodexHost", "CodexCloseButton", "CharacterCodexButton", "ItemCodexButton",
	]):
		return
	for source_name in ["CharacterCodexButton", "ItemCodexButton"]:
		var source := shell.get_node("%%%s" % source_name) as Button
		source.grab_focus()
		_press(shell, source_name)
		await get_tree().process_frame
		assert_ne(get_viewport().gui_get_focus_owner(), source, "资料馆打开后焦点必须离开底层大厅")
		if source_name == "CharacterCodexButton":
			_press(shell, "CodexCloseButton")
		else:
			var escape := InputEventKey.new()
			escape.pressed = true
			escape.keycode = KEY_ESCAPE
			get_viewport().push_input(escape)
		await get_tree().process_frame
		assert_false((shell.get_node("%CodexHost") as Control).visible)
		assert_same(get_viewport().gui_get_focus_owner(), source, "关闭后焦点必须回到来源按钮")


func test_codex_is_full_screen_bounded_and_has_keyboard_focus_hooks() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, [
		"CodexHost", "LobbyCodexOverlay", "CodexCloseButton", "CodexCharacterTab",
		"CodexItemTab", "CodexRulesTab", "RulesButton",
	]):
		return
	_press(shell, "RulesButton")
	await get_tree().process_frame
	var bounds := Rect2(shell.global_position, DESIGN_SIZE)
	var host := shell.get_node("%CodexHost") as Control
	var overlay := shell.get_node("%LobbyCodexOverlay") as Control
	assert_true(bounds.encloses(host.get_global_rect()))
	assert_true(bounds.encloses(overlay.get_global_rect()))
	assert_gte(overlay.get_global_rect().size.x, 1400.0, "资料馆必须是全屏主层")
	assert_gte(overlay.get_global_rect().size.y, 800.0, "资料馆必须是全屏主层")
	for hook_name in ["CodexCloseButton", "CodexCharacterTab", "CodexItemTab", "CodexRulesTab"]:
		assert_eq((shell.get_node("%%%s" % hook_name) as Control).focus_mode, Control.FOCUS_ALL)


func test_codex_uses_generated_stage_roster_and_scroll_materials() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, [
		"CharacterCodexButton", "CodexPanel", "CodexStage", "CodexRoster",
		"CodexDetailScroll", "CodexDetailTitle",
	]):
		return
	_press(shell, "CharacterCodexButton")
	await get_tree().process_frame
	var panel_style := (shell.get_node("%CodexPanel") as Control).get_theme_stylebox("panel")
	var detail_style := (shell.get_node("%CodexDetailScroll") as Control).get_theme_stylebox("panel")
	assert_true(panel_style is StyleBoxTexture)
	assert_true(detail_style is StyleBoxTexture)
	assert_eq((panel_style as StyleBoxTexture).texture.resource_path,
		"res://assets/ui/lobby_materials/lobby_lacquer_panel_9slice.png")
	assert_eq((detail_style as StyleBoxTexture).texture.resource_path,
		"res://assets/ui/lobby_materials/lobby_scroll_panel_9slice.png")
	var entries := shell.get_node("%CodexRoster").find_children("CodexRosterEntry*", "Button", true, false)
	assert_gte(entries.size(), 2, "木札名录必须来自真实 catalog")
	if entries.size() >= 2:
		var expected := String((entries[1] as Button).get_meta("entry_title"))
		(entries[1] as Button).pressed.emit()
		await get_tree().process_frame
		assert_eq((shell.get_node("%CodexDetailTitle") as Label).text, expected)


func test_codex_has_weighted_header_tabs_and_three_layer_body() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, [
		"CharacterCodexButton", "CodexHeaderPlaque", "CodexTabs", "CodexStage",
		"CodexRoster", "CodexDetailScroll",
	]):
		return
	_press(shell, "CharacterCodexButton")
	await get_tree().process_frame
	var header := shell.get_node("%CodexHeaderPlaque") as Control
	var tabs := shell.get_node("%CodexTabs") as Control
	var stage := shell.get_node("%CodexStage") as Control
	var roster := shell.get_node("%CodexRoster") as Control
	var detail := shell.get_node("%CodexDetailScroll") as Control
	assert_lt(header.get_global_rect().end.y, tabs.get_global_rect().position.y + 4.0)
	assert_lt(tabs.get_global_rect().end.y, stage.get_global_rect().position.y + 4.0)
	assert_gt(tabs.get_global_rect().size.y, 50.0, "资料馆页签必须具有一级导航权重")
	assert_lt(stage.get_global_rect().position.x, roster.get_global_rect().position.x)
	assert_lt(roster.get_global_rect().position.x, detail.get_global_rect().position.x)


func test_codex_and_audio_are_mutually_exclusive_and_tab_stays_in_top_layer() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, [
		"CodexHost", "LobbyCodexOverlay", "AudioPopupHost", "CharacterCodexButton",
		"BgmButton", "RuleDrawerHost",
	]):
		return
	_press(shell, "CharacterCodexButton")
	await get_tree().process_frame
	var overlay := shell.get_node("%LobbyCodexOverlay") as Control
	for _step in range(12):
		var focus_next := InputEventAction.new()
		focus_next.action = &"ui_focus_next"
		focus_next.pressed = true
		get_viewport().push_input(focus_next)
		await get_tree().process_frame
		var focus_owner := get_viewport().gui_get_focus_owner()
		assert_not_null(focus_owner)
		if focus_owner != null:
			assert_true(overlay == focus_owner or overlay.is_ancestor_of(focus_owner),
				"资料馆打开时 Tab 不得泄漏到底层大厅")

	# 即使底层按钮被程序化触发，也必须切换而不是叠两层。
	_press(shell, "BgmButton")
	await get_tree().process_frame
	assert_false((shell.get_node("%CodexHost") as Control).visible)
	assert_true((shell.get_node("%AudioPopupHost") as Control).visible)
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	get_viewport().push_input(escape)
	await get_tree().process_frame
	assert_false((shell.get_node("%AudioPopupHost") as Control).visible,
		"Esc 必须关闭眼前的最上层弹层")

	_press(shell, "BgmButton")
	await get_tree().process_frame
	shell.request_practice()
	await get_tree().process_frame
	assert_false((shell.get_node("%AudioPopupHost") as Control).visible)
	assert_true((shell.get_node("%RuleDrawerHost") as Control).visible,
		"打开规则抽屉时不得保留音量层")


func test_codex_visible_copy_has_no_run_or_e6_controls() -> void:
	var shell := _spawn_lobby()
	await get_tree().process_frame
	if not _require_hooks(shell, ["LobbyCodexOverlay", "RulesButton"]):
		return
	_press(shell, "RulesButton")
	await get_tree().process_frame
	var copy := _visible_copy(shell.get_node("%LobbyCodexOverlay")).to_lower()
	for forbidden in [
		"run", "章节", "boss", "hp", "金币", "商店", "抽卡", "营地", "战令",
		"语音音量", "座位静音", "举报", "自动禁言", "e6",
	]:
		assert_false(copy.contains(forbidden), "资料馆可见内容不得包含：%s" % forbidden)


func test_capture_tool_has_real_codex_overlay_shot() -> void:
	var script := load("res://tools/capture_screens.gd") as GDScript
	assert_not_null(script)
	if script == null:
		return
	assert_true(script.source_code.contains("shot_lobby_codex.png"))
	assert_true(script.source_code.contains("func _capture_lobby_codex"))
