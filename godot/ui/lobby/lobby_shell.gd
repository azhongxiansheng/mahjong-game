class_name LobbyShell extends Control

# 生产主入口壳（E1-01 / #225 + E1-03 / #227）。
# 1600×900 生产大厅布局与稳定交互挂点；规则选择态归 #228。
# 本壳仅导航与信号挂点，不含会话配置、联网或肉鸽路径。

const SCENE_PATH := "res://ui/lobby/lobby_shell.tscn"

## 电脑练习入口挂点（后续 #228 接规则抽屉；本 Issue 仅发 signal）。
signal practice_pressed
## 公共匹配入口挂点（后续 #228/#238；本 Issue 仅发 signal，不假装已匹配）。
signal match_pressed
signal notice_pressed
signal help_pressed
signal settings_pressed
signal character_codex_pressed
signal item_codex_pressed
signal rules_pressed
signal bgm_pressed
signal sfx_pressed

var _status_label: Label = null


func _ready() -> void:
	custom_minimum_size = Vector2(DesignTokens.VIEW_W, DesignTokens.VIEW_H)
	DesignTokens.style_full_panel(self)
	_build_ui()


func request_practice() -> void:
	_set_status("电脑练习即将开放")
	practice_pressed.emit()


func request_match() -> void:
	_set_status("公共匹配即将开放")
	match_pressed.emit()


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

	# #228 宿主：隐藏、空、不拦截输入
	var drawer_host := Control.new()
	drawer_host.name = "RuleDrawerHost"
	drawer_host.visible = false
	drawer_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(drawer_host)
	_register_hook(drawer_host)


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
