class_name LobbyShell extends Control

# 生产主入口壳（E1-01 / #225 + E1-03 / #227 + E1-04 / #228 + E1-05 / #229）。
# 1600×900 生产大厅布局、规则抽屉、资料馆、音量弹层与 SessionIntent 输出。
# 不定义正式会话配置，不启动牌局，不联网。

const SCENE_PATH := "res://ui/lobby/lobby_shell.tscn"
const LOBBY_BGM_PATH := "res://assets/bgm/lobby_xuxiguan.ogg"

## 电脑练习入口挂点（打开规则抽屉）。
signal practice_pressed
## 公共匹配入口挂点（打开同一规则抽屉；不假装已匹配）。
signal match_pressed
## 规则抽屉确认后输出的纯 UI 意图（E1-04）。
signal session_intent_confirmed(intent: SessionIntent)
signal notice_pressed
signal help_pressed
signal settings_pressed
signal character_codex_pressed
signal item_codex_pressed
signal rules_pressed
signal bgm_pressed
signal sfx_pressed

var _status_label: Label = null
var _drawer_host: Control = null
var _rule_drawer: RuleDrawer = null
var _drawer_source: Control = null
var _codex_host: Control = null
var _codex_overlay: LobbyCodexOverlay = null
var _codex_source: Control = null
var _audio_host: Control = null
var _audio_popup: LobbyAudioPopup = null
var _audio_source: Control = null


func _ready() -> void:
	custom_minimum_size = Vector2(DesignTokens.VIEW_W, DesignTokens.VIEW_H)
	DesignTokens.style_full_panel(self)
	_build_ui()
	set_process_input(true)
	_request_lobby_bgm()


func _exit_tree() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("stop_bgm"):
		am.stop_bgm()


func request_practice() -> void:
	practice_pressed.emit()
	_open_rule_drawer(&"PRACTICE", get_node_or_null("%PracticeButton") as Control)


func request_match() -> void:
	match_pressed.emit()
	_open_rule_drawer(&"PUBLIC_CASUAL", get_node_or_null("%MatchButton") as Control)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_ESCAPE:
		return
	# 上层优先：资料馆 > 音量弹层 > 规则抽屉
	if _codex_host != null and _codex_host.visible:
		_close_codex()
		get_viewport().set_input_as_handled()
		return
	if _audio_host != null and _audio_host.visible:
		_close_audio_popup()
		get_viewport().set_input_as_handled()
		return
	if _drawer_host != null and _drawer_host.visible:
		_close_rule_drawer()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_add_ambient_background()

	var root := VBoxContainer.new()
	root.name = "RootVBox"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = DesignTokens.PANEL_PAD
	root.offset_top = DesignTokens.PANEL_PAD
	root.offset_right = -DesignTokens.PANEL_PAD
	root.offset_bottom = -DesignTokens.PANEL_PAD
	root.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
	add_child(root)

	var top_bar := _build_top_bar()
	root.add_child(top_bar)
	_register_hook(top_bar)

	var main_row := HBoxContainer.new()
	main_row.name = "MainRow"
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", DesignTokens.GAP_LOOSE)
	root.add_child(main_row)

	var resident := _build_resident_stage()
	resident.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resident.size_flags_vertical = Control.SIZE_EXPAND_FILL
	resident.size_flags_stretch_ratio = 1.65
	main_row.add_child(resident)
	_register_hook(resident)
	_register_hook(resident.find_child("ResidentPortrait", true, false))

	var entry_rail := _build_entry_rail()
	entry_rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry_rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	entry_rail.size_flags_stretch_ratio = 1.0
	main_row.add_child(entry_rail)
	_register_hook(entry_rail)
	_register_hook(entry_rail.find_child("PracticeButton", true, false))
	_register_hook(entry_rail.find_child("MatchButton", true, false))

	var bottom_bar := _build_bottom_bar()
	root.add_child(bottom_bar)
	_register_hook(bottom_bar)
	for btn_name in [
		"NoticeButton",
		"HelpButton",
		"SettingsButton",
		"CharacterCodexButton",
		"ItemCodexButton",
		"RulesButton",
		"BgmButton",
		"SfxButton",
	]:
		var found := find_child(btn_name, true, false)
		if found:
			_register_hook(found)

	# #228 宿主：冷启动隐藏且不拦截输入；始终挂唯一规则抽屉实例
	_drawer_host = Control.new()
	_drawer_host.name = "RuleDrawerHost"
	_drawer_host.visible = false
	_drawer_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_drawer_host)
	_register_hook(_drawer_host)

	_rule_drawer = RuleDrawer.new()
	_drawer_host.add_child(_rule_drawer)
	_rule_drawer.confirmed.connect(_on_rule_drawer_confirmed)
	_rule_drawer.cancelled.connect(_close_rule_drawer)
	for hook_node in _rule_drawer.get_hook_nodes():
		_register_hook(hook_node)

	# #229 资料馆：冷启动隐藏；三入口复用唯一全屏层
	_codex_host = Control.new()
	_codex_host.name = "CodexHost"
	_codex_host.visible = false
	_codex_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_codex_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_codex_host)
	_register_hook(_codex_host)

	_codex_overlay = LobbyCodexOverlay.new()
	_codex_host.add_child(_codex_overlay)
	_codex_overlay.closed.connect(_close_codex)
	for hook_node in _codex_overlay.get_hook_nodes():
		_register_hook(hook_node)

	# #229 音量弹层：冷启动隐藏；BGM/SFX 复用唯一弹层
	_audio_host = Control.new()
	_audio_host.name = "AudioPopupHost"
	_audio_host.visible = false
	_audio_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_audio_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_audio_host)
	_register_hook(_audio_host)

	_audio_popup = LobbyAudioPopup.new()
	_audio_host.add_child(_audio_popup)
	_audio_popup.closed.connect(_close_audio_popup)
	for hook_node in _audio_popup.get_hook_nodes():
		_register_hook(hook_node)

	# 底部资料 / 音量入口：按钮既有 signal 外再打开真实层（不重复 emit）
	var char_btn := get_node_or_null("%CharacterCodexButton") as Button
	if char_btn:
		char_btn.pressed.connect(func() -> void:
			_open_codex(&"characters", char_btn)
		)
	var item_btn := get_node_or_null("%ItemCodexButton") as Button
	if item_btn:
		item_btn.pressed.connect(func() -> void:
			_open_codex(&"items", item_btn)
		)
	var rules_btn := get_node_or_null("%RulesButton") as Button
	if rules_btn:
		rules_btn.pressed.connect(func() -> void:
			_open_codex(&"rules", rules_btn)
		)
	var bgm_btn := get_node_or_null("%BgmButton") as Button
	if bgm_btn:
		bgm_btn.pressed.connect(func() -> void:
			_open_audio_popup(bgm_btn)
		)
	var sfx_btn := get_node_or_null("%SfxButton") as Button
	if sfx_btn:
		sfx_btn.pressed.connect(func() -> void:
			_open_audio_popup(sfx_btn)
		)


## 代码构建子节点时须在已挂到本壳之后设 owner，%UniqueName 才挂到 LobbyShell。
func _register_hook(node: Node) -> void:
	if node == null:
		return
	node.unique_name_in_owner = true
	node.owner = self


func _add_ambient_background() -> void:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(0.07, 0.10, 0.16, 1.0),
		Color(0.04, 0.06, 0.09, 1.0),
		Color(0.06, 0.08, 0.12, 1.0),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])

	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.15, 0.0)
	tex.fill_to = Vector2(0.85, 1.0)
	tex.width = 32
	tex.height = 32

	var ambient := TextureRect.new()
	ambient.name = "AmbientBg"
	ambient.texture = tex
	ambient.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ambient.set_anchors_preset(Control.PRESET_FULL_RECT)
	ambient.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ambient.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(ambient)
	# DtBg 在 0；氛围层压在其上
	move_child(ambient, 1)

	# 左侧柔光，衬托角色常驻区
	var glow := ColorRect.new()
	glow.name = "ResidentGlow"
	glow.color = Color(0.55, 0.42, 0.18, 0.07)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.anchor_right = 0.55
	glow.offset_right = 0.0
	add_child(glow)
	move_child(glow, 2)


func _make_surface_panel(panel_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	var sb := StyleBoxFlat.new()
	sb.bg_color = DesignTokens.SURFACE_PANEL
	sb.border_color = DesignTokens.BORDER_GOLD_SOFT
	sb.set_border_width_all(DesignTokens.CARD_BORDER)
	sb.set_corner_radius_all(DesignTokens.CARD_RADIUS)
	sb.content_margin_left = DesignTokens.GAP_NORMAL
	sb.content_margin_right = DesignTokens.GAP_NORMAL
	sb.content_margin_top = DesignTokens.GAP_NORMAL
	sb.content_margin_bottom = DesignTokens.GAP_NORMAL
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _build_top_bar() -> Control:
	var top := HBoxContainer.new()
	top.name = "TopBar"
	top.custom_minimum_size = Vector2(0, DesignTokens.HUD_H + 12)
	top.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
	top.alignment = BoxContainer.ALIGNMENT_CENTER

	var player_card := _make_surface_panel("PlayerCard")
	player_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(player_card)

	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
	player_card.add_child(player_row)

	var avatar := ColorRect.new()
	avatar.name = "PlayerAvatar"
	avatar.custom_minimum_size = Vector2(44, 44)
	avatar.color = Color(0.22, 0.20, 0.16, 1.0)
	player_row.add_child(avatar)

	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.alignment = BoxContainer.ALIGNMENT_CENTER
	player_row.add_child(name_col)

	var guest_name := Label.new()
	guest_name.name = "PlayerName"
	guest_name.text = "游客"
	guest_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	guest_name.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	guest_name.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	name_col.add_child(guest_name)

	var brand := Label.new()
	brand.name = "BrandLabel"
	brand.text = "虚席馆"
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	brand.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	brand.add_theme_color_override("font_color", DesignTokens.TEXT_TITLE)
	name_col.add_child(brand)

	var util_row := HBoxContainer.new()
	util_row.name = "TopUtilityRow"
	util_row.add_theme_constant_override("separation", DesignTokens.GAP_TIGHT)
	top.add_child(util_row)

	util_row.add_child(_make_utility_button("NoticeButton", "公告", notice_pressed))
	util_row.add_child(_make_utility_button("HelpButton", "帮助", help_pressed))
	util_row.add_child(_make_utility_button("SettingsButton", "设置", settings_pressed))

	return top


func _build_resident_stage() -> Control:
	var stage := _make_surface_panel("ResidentStage")

	var body := HBoxContainer.new()
	body.name = "ResidentBody"
	body.add_theme_constant_override("separation", DesignTokens.GAP_LOOSE)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_child(body)

	var characters: Array = CharacterPool.all()
	var resident: Character = characters[0] as Character

	var portrait := TextureRect.new()
	portrait.name = "ResidentPortrait"
	portrait.custom_minimum_size = Vector2(280, 420)
	portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.size_flags_stretch_ratio = 1.2
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if resident != null and resident.portrait_path != "" and ResourceLoader.exists(resident.portrait_path):
		portrait.texture = load(resident.portrait_path) as Texture2D
	body.add_child(portrait)

	var copy_col := VBoxContainer.new()
	copy_col.name = "ResidentCopy"
	copy_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	copy_col.size_flags_stretch_ratio = 0.9
	copy_col.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
	copy_col.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(copy_col)

	var char_name := Label.new()
	char_name.name = "ResidentName"
	char_name.text = resident.display_name if resident else ""
	char_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	char_name.add_theme_font_size_override("font_size", DesignTokens.FONT_SUBTITLE)
	char_name.add_theme_color_override("font_color", DesignTokens.TEXT_TITLE)
	copy_col.add_child(char_name)

	var char_desc := Label.new()
	char_desc.name = "ResidentDescription"
	char_desc.text = resident.description if resident else ""
	char_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	char_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	char_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	char_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	char_desc.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	char_desc.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	copy_col.add_child(char_desc)

	return stage


func _build_entry_rail() -> Control:
	var rail := _make_surface_panel("EntryRail")

	var col := VBoxContainer.new()
	col.name = "EntryColumn"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", DesignTokens.GAP_LOOSE)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	rail.add_child(col)

	var prompt := Label.new()
	prompt.name = "Subtitle"
	prompt.text = "选择一种游戏方式"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", DesignTokens.FONT_SUBTITLE)
	prompt.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	col.add_child(prompt)

	var practice_btn := DesignTokens.make_button(
		"电脑练习", DesignTokens.BtnRole.PRIMARY, Vector2(360, 108)
	)
	practice_btn.name = "PracticeButton"
	practice_btn.focus_mode = Control.FOCUS_ALL
	practice_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	practice_btn.pressed.connect(request_practice)
	col.add_child(practice_btn)

	var practice_hint := Label.new()
	practice_hint.name = "PracticeHint"
	practice_hint.text = "1 人 + 3 AI"
	practice_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	DesignTokens.apply_caption_style(practice_hint)
	col.add_child(practice_hint)

	var match_btn := DesignTokens.make_button(
		"公共匹配", DesignTokens.BtnRole.SECONDARY, Vector2(360, 108)
	)
	match_btn.name = "MatchButton"
	match_btn.focus_mode = Control.FOCUS_ALL
	match_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	match_btn.pressed.connect(request_match)
	col.add_child(match_btn)

	var match_hint := Label.new()
	match_hint.name = "MatchHint"
	match_hint.text = "真人优先 / AI 补位"
	match_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	DesignTokens.apply_caption_style(match_hint)
	col.add_child(match_hint)

	# 明确练习 ↔ 匹配上下焦点邻接
	practice_btn.focus_neighbor_bottom = practice_btn.get_path_to(match_btn)
	match_btn.focus_neighbor_top = match_btn.get_path_to(practice_btn)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = "请选择游戏方式"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	DesignTokens.apply_caption_style(_status_label)
	col.add_child(_status_label)

	return rail


func _build_bottom_bar() -> Control:
	var bottom := HBoxContainer.new()
	bottom.name = "BottomBar"
	bottom.custom_minimum_size = Vector2(0, DesignTokens.HUD_H + 8)
	bottom.add_theme_constant_override("separation", DesignTokens.GAP_TIGHT)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER

	var left := HBoxContainer.new()
	left.name = "BottomLeft"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", DesignTokens.GAP_TIGHT)
	bottom.add_child(left)

	left.add_child(_make_utility_button("CharacterCodexButton", "角色图鉴", character_codex_pressed))
	left.add_child(_make_utility_button("ItemCodexButton", "道具图鉴", item_codex_pressed))
	left.add_child(_make_utility_button("RulesButton", "规则说明", rules_pressed))

	var right := HBoxContainer.new()
	right.name = "BottomRight"
	right.add_theme_constant_override("separation", DesignTokens.GAP_TIGHT)
	bottom.add_child(right)

	right.add_child(_make_utility_button("BgmButton", "BGM", bgm_pressed))
	right.add_child(_make_utility_button("SfxButton", "SFX", sfx_pressed))

	return bottom


func _make_utility_button(btn_name: String, text: String, pressed_signal: Signal) -> Button:
	var btn := DesignTokens.make_button(
		text, DesignTokens.BtnRole.GHOST, Vector2(120, DesignTokens.BUTTON_H)
	)
	btn.name = btn_name
	btn.focus_mode = Control.FOCUS_ALL
	btn.pressed.connect(func() -> void: pressed_signal.emit())
	return btn


func _set_status(text: String) -> void:
	if _status_label:
		_status_label.text = text


func _open_rule_drawer(room_kind: StringName, source: Control) -> void:
	if _drawer_host == null or _rule_drawer == null:
		return
	# 永远只保留一层：开抽屉前关掉资料馆 / 音量弹层。
	_close_codex(false)
	_close_audio_popup(false)
	_drawer_source = source
	_drawer_host.visible = true
	_drawer_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_set_status("选择局制与玩法")
	_rule_drawer.open_for(room_kind)


func _close_rule_drawer(restore_focus: bool = true) -> void:
	if _drawer_host == null:
		return
	if _rule_drawer:
		_rule_drawer.close_visual()
	_drawer_host.visible = false
	_drawer_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_status("请选择游戏方式")
	if restore_focus and _drawer_source and is_instance_valid(_drawer_source) \
			and _drawer_source.focus_mode != Control.FOCUS_NONE:
		_drawer_source.grab_focus()
	_drawer_source = null


func _on_rule_drawer_confirmed(intent: SessionIntent) -> void:
	session_intent_confirmed.emit(intent)
	_close_rule_drawer()


func _open_codex(page: StringName, source: Control) -> void:
	if _codex_host == null or _codex_overlay == null:
		return
	_close_rule_drawer(false)
	_close_audio_popup(false)
	_codex_source = source
	_codex_host.visible = true
	_codex_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_codex_overlay.open_on_page(page)


func _close_codex(restore_focus: bool = true) -> void:
	if _codex_host == null:
		return
	_codex_host.visible = false
	_codex_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if restore_focus and _codex_source and is_instance_valid(_codex_source) \
			and _codex_source.focus_mode != Control.FOCUS_NONE:
		_codex_source.grab_focus()
	_codex_source = null


func _open_audio_popup(source: Control) -> void:
	if _audio_host == null or _audio_popup == null:
		return
	_close_rule_drawer(false)
	_close_codex(false)
	_audio_source = source
	_audio_host.visible = true
	_audio_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_audio_popup.open_popup()


func _close_audio_popup(restore_focus: bool = true) -> void:
	if _audio_host == null:
		return
	_audio_host.visible = false
	_audio_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if restore_focus and _audio_source and is_instance_valid(_audio_source) \
			and _audio_source.focus_mode != Control.FOCUS_NONE:
		_audio_source.grab_focus()
	_audio_source = null


func _request_lobby_bgm() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am == null:
		return
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and "bgm_volume" in am:
		am.bgm_volume = float(sm.bgm_volume)
	if am.has_method("play_bgm"):
		am.play_bgm(LOBBY_BGM_PATH)
