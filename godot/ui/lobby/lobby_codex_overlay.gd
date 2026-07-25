class_name LobbyCodexOverlay extends Control

# 大厅单一全屏资料馆（E1-05 / #229）。
# 角色 / 道具 / 规则三入口复用本实例；页签切换复用同一 CodexContent。

signal closed

const PAGE_CHARACTERS := &"characters"
const PAGE_ITEMS := &"items"
const PAGE_RULES := &"rules"

var _current_page: StringName = PAGE_CHARACTERS
var _catalog: LobbyCodexCatalog = LobbyCodexCatalog.new()
var _panel: PanelContainer = null
var _header_plaque: PanelContainer = null
var _tabs: HBoxContainer = null
var _stage: PanelContainer = null
var _stage_body: VBoxContainer = null
var _roster: VBoxContainer = null
var _content: VBoxContainer = null
var _content_host: ScrollContainer = null
var _detail_panel: PanelContainer = null
var _detail_title: Label = null
var _detail_content: VBoxContainer = null
var _roster_buttons: Array[Button] = []
var _character_tab: Button = null
var _item_tab: Button = null
var _rules_tab: Button = null
var _close_btn: Button = null
var _tab_group: ButtonGroup = null
var _built: bool = false


func _init() -> void:
	name = "LobbyCodexOverlay"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _ready() -> void:
	_wire_focus_graph()


func get_current_page() -> StringName:
	return _current_page


func get_hook_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	for n in [
		self,
		_panel,
		_header_plaque,
		_tabs,
		_stage,
		_roster,
		_detail_panel,
		_detail_title,
		_close_btn,
		_character_tab,
		_item_tab,
		_rules_tab,
		_content_host,
	]:
		if n != null:
			nodes.append(n)
	return nodes


func open_on_page(page: StringName) -> void:
	_set_page(page)
	_wire_focus_graph()
	if _close_btn:
		_close_btn.grab_focus()


func _build_ui() -> void:
	if _built:
		return
	_built = true

	var dim := ColorRect.new()
	dim.name = "CodexDim"
	dim.color = Color(DesignTokens.BG_BASE.r, DesignTokens.BG_BASE.g, DesignTokens.BG_BASE.b, DesignTokens.MODAL_BG_DIM)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.name = "CodexPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 18
	_panel.offset_top = 18
	_panel.offset_right = -18
	_panel.offset_bottom = -18
	_panel.add_theme_stylebox_override("panel", DesignTokens.make_lobby_texture_style(
		DesignTokens.LOBBY_LACQUER_PANEL, 108, 92, 108, 92, 46, 40
	))
	add_child(_panel)

	var root := VBoxContainer.new()
	root.name = "CodexRoot"
	root.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(root)

	root.add_child(_build_header())
	root.add_child(_build_tabs())

	var body := HBoxContainer.new()
	body.name = "CodexStageRosterScroll"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
	root.add_child(body)

	_stage = PanelContainer.new()
	_stage.name = "CodexStage"
	_stage.custom_minimum_size.x = 420
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.add_theme_stylebox_override("panel", DesignTokens.make_lobby_texture_style(
		DesignTokens.LOBBY_LACQUER_PANEL, 108, 92, 108, 92, 32, 28
	))
	body.add_child(_stage)
	_stage_body = VBoxContainer.new()
	_stage_body.alignment = BoxContainer.ALIGNMENT_CENTER
	_stage_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.add_child(_stage_body)

	var roster_host := ScrollContainer.new()
	roster_host.name = "CodexRosterHost"
	roster_host.custom_minimum_size.x = 260
	roster_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster_host.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(roster_host)
	_roster = VBoxContainer.new()
	_roster.name = "CodexRoster"
	_roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster.add_theme_constant_override("separation", DesignTokens.GAP_TIGHT)
	roster_host.add_child(_roster)

	_detail_panel = PanelContainer.new()
	_detail_panel.name = "CodexDetailScroll"
	_detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_panel.add_theme_stylebox_override("panel", DesignTokens.make_lobby_texture_style(
		DesignTokens.LOBBY_SCROLL_PANEL, 70, 58, 70, 58, 70, 48
	))
	body.add_child(_detail_panel)

	_content_host = ScrollContainer.new()
	_content_host.name = "CodexContent"
	_content_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_host.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_panel.add_child(_content_host)

	_content = VBoxContainer.new()
	_content.name = "CodexContentList"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
	_content_host.add_child(_content)

	_detail_title = _label("", DesignTokens.FONT_TITLE, DesignTokens.LOBBY_CINNABAR, false)
	_detail_title.name = "CodexDetailTitle"
	_content.add_child(_detail_title)
	_detail_content = VBoxContainer.new()
	_detail_content.name = "CodexDetailContent"
	_detail_content.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
	_content.add_child(_detail_content)

	_set_page(PAGE_CHARACTERS)


func _build_header() -> Control:
	_header_plaque = PanelContainer.new()
	_header_plaque.name = "CodexHeaderPlaque"
	_header_plaque.custom_minimum_size.y = 66
	_header_plaque.add_theme_stylebox_override("panel", DesignTokens.make_lobby_texture_style(
		DesignTokens.LOBBY_WOOD_NAMEPLATE, 54, 20, 54, 20, 30, 9
	))

	var header := HBoxContainer.new()
	header.name = "CodexHeader"
	header.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
	_header_plaque.add_child(header)

	var title := Label.new()
	title.name = "CodexTitle"
	title.text = "资料馆"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", DesignTokens.LOBBY_INK)
	header.add_child(title)

	_close_btn = DesignTokens.make_button("关闭", DesignTokens.BtnRole.PRIMARY, Vector2(140, 52))
	_close_btn.name = "CodexCloseButton"
	_close_btn.focus_mode = Control.FOCUS_ALL
	DesignTokens.apply_lobby_material_button(_close_btn, true)
	_close_btn.pressed.connect(_on_close_pressed)
	header.add_child(_close_btn)
	return _header_plaque


func _build_tabs() -> Control:
	_tabs = HBoxContainer.new()
	_tabs.name = "CodexTabs"
	_tabs.custom_minimum_size.y = 56
	_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabs.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
	_tab_group = ButtonGroup.new()

	_character_tab = _make_tab("CodexCharacterTab", "角色", PAGE_CHARACTERS)
	_item_tab = _make_tab("CodexItemTab", "道具", PAGE_ITEMS)
	_rules_tab = _make_tab("CodexRulesTab", "规则", PAGE_RULES)
	_tabs.add_child(_character_tab)
	_tabs.add_child(_item_tab)
	_tabs.add_child(_rules_tab)
	return _tabs


func _make_tab(btn_name: String, text: String, page: StringName) -> Button:
	var btn := DesignTokens.make_button(text, DesignTokens.BtnRole.SECONDARY, Vector2(176, 54))
	btn.name = btn_name
	btn.focus_mode = Control.FOCUS_ALL
	btn.toggle_mode = true
	btn.button_group = _tab_group
	DesignTokens.apply_lobby_material_button(btn)
	btn.pressed.connect(func() -> void: _set_page(page))
	return btn


func _set_page(page: StringName) -> void:
	_current_page = page
	_sync_tab_state()
	_rebuild_content()


func _sync_tab_state() -> void:
	if _character_tab:
		_character_tab.button_pressed = _current_page == PAGE_CHARACTERS
	if _item_tab:
		_item_tab.button_pressed = _current_page == PAGE_ITEMS
	if _rules_tab:
		_rules_tab.button_pressed = _current_page == PAGE_RULES


func _rebuild_content() -> void:
	if _content == null or _roster == null or _stage_body == null:
		return
	_clear_children(_roster)
	_clear_children(_stage_body)
	_clear_children(_detail_content)
	_roster_buttons.clear()
	var rows := _page_rows()
	var group := ButtonGroup.new()
	group.allow_unpress = false
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var button := Button.new()
		button.name = "CodexRosterEntry%d" % index
		button.text = _entry_title(row)
		button.custom_minimum_size = Vector2(0, 56)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_ALL
		button.toggle_mode = true
		button.button_group = group
		button.set_meta("entry_title", _entry_title(row))
		DesignTokens.apply_lobby_material_button(button, true)
		button.pressed.connect(_select_entry.bind(index))
		_roster.add_child(button)
		_roster_buttons.append(button)
	if not rows.is_empty():
		_select_entry(0)
	_wire_focus_graph()


func _page_rows() -> Array:
	match _current_page:
		PAGE_ITEMS:
			return _catalog.items()
		PAGE_RULES:
			return _catalog.rules()
		_:
			return _catalog.characters()


func _entry_title(row: Dictionary) -> String:
	return String(row.get("title", "")) if _current_page == PAGE_RULES else String(row.get("display_name", ""))


func _select_entry(index: int) -> void:
	var rows := _page_rows()
	if index < 0 or index >= rows.size():
		return
	for button_index in range(_roster_buttons.size()):
		_roster_buttons[button_index].button_pressed = button_index == index
	_render_stage(rows[index])
	_render_detail(rows[index])


func _render_stage(row: Dictionary) -> void:
	_clear_children(_stage_body)
	var path := ""
	if _current_page == PAGE_CHARACTERS:
		path = String(row.get("portrait_path", ""))
	elif _current_page == PAGE_ITEMS:
		path = String(row.get("icon_path", ""))
	if path != "" and ResourceLoader.exists(path):
		var art := TextureRect.new()
		art.name = "CodexStageArt"
		art.custom_minimum_size = Vector2(330, 430 if _current_page == PAGE_CHARACTERS else 280)
		art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		art.size_flags_vertical = Control.SIZE_EXPAND_FILL
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.texture = load(path) as Texture2D
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage_body.add_child(art)
	var caption := _label(_entry_title(row), DesignTokens.FONT_SUBTITLE, DesignTokens.LOBBY_WASHI_TEXT, false)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_body.add_child(caption)


func _render_detail(row: Dictionary) -> void:
	_clear_children(_detail_content)
	_detail_title.text = _entry_title(row)
	if _current_page == PAGE_CHARACTERS:
		var affinities: Array = row.get("affinity_labels", [])
		var affinity_text := " / ".join(PackedStringArray(affinities))
		if affinity_text != "":
			_detail_content.add_child(_label(affinity_text, DesignTokens.FONT_CAPTION, DesignTokens.LOBBY_CINNABAR, false))
		_detail_content.add_child(_label(String(row.get("description", "")), DesignTokens.FONT_BODY, DesignTokens.LOBBY_INK, true))
		var ability_name := String(row.get("ability_name", ""))
		if ability_name != "":
			_detail_content.add_child(_label(ability_name, DesignTokens.FONT_SUBTITLE, DesignTokens.LOBBY_CINNABAR, false))
			_detail_content.add_child(_label(String(row.get("ability_description", "")), DesignTokens.FONT_BODY, DesignTokens.LOBBY_INK, true))
	elif _current_page == PAGE_ITEMS:
		var meta := "%s · %s" % [String(row.get("category", "")), String(row.get("rarity_label", ""))]
		_detail_content.add_child(_label(meta, DesignTokens.FONT_CAPTION, DesignTokens.LOBBY_CINNABAR, false))
		_detail_content.add_child(_label(String(row.get("description", "")), DesignTokens.FONT_BODY, DesignTokens.LOBBY_INK, true))
	else:
		_detail_content.add_child(_label(String(row.get("body", "")), DesignTokens.FONT_BODY, DesignTokens.LOBBY_INK, true))
	var summary_parts := PackedStringArray()
	for catalog_row in _page_rows():
		if _current_page == PAGE_ITEMS:
			summary_parts.append(String(catalog_row.get("category", "")))
		elif _current_page == PAGE_RULES:
			summary_parts.append(String(catalog_row.get("title", "")))
	if not summary_parts.is_empty():
		_detail_content.add_child(_label(
			" · ".join(summary_parts), DesignTokens.FONT_CAPTION, DesignTokens.LOBBY_CINNABAR, true
		))


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.free()


func _label(text: String, font_size: int, color: Color, enable_autowrap: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	if enable_autowrap:
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return lbl


func _wire_focus_graph() -> void:
	# 关闭 → 三页签 → 木札名录 → 关闭，Tab/Shift+Tab 不落到底层。
	if _close_btn == null or _character_tab == null or _item_tab == null or _rules_tab == null:
		return
	if not is_inside_tree():
		return
	_close_btn.focus_next = _close_btn.get_path_to(_character_tab)
	_character_tab.focus_next = _character_tab.get_path_to(_item_tab)
	_item_tab.focus_next = _item_tab.get_path_to(_rules_tab)
	if _roster_buttons.is_empty():
		_rules_tab.focus_next = _rules_tab.get_path_to(_close_btn)
		_close_btn.focus_previous = _close_btn.get_path_to(_rules_tab)
	else:
		_rules_tab.focus_next = _rules_tab.get_path_to(_roster_buttons[0])
		for index in range(_roster_buttons.size()):
			var next_control: Control = _close_btn if index == _roster_buttons.size() - 1 else _roster_buttons[index + 1]
			var previous_control: Control = _rules_tab if index == 0 else _roster_buttons[index - 1]
			_roster_buttons[index].focus_next = _roster_buttons[index].get_path_to(next_control)
			_roster_buttons[index].focus_previous = _roster_buttons[index].get_path_to(previous_control)
		_close_btn.focus_previous = _close_btn.get_path_to(_roster_buttons[-1])
	_character_tab.focus_previous = _character_tab.get_path_to(_close_btn)
	_item_tab.focus_previous = _item_tab.get_path_to(_character_tab)
	_rules_tab.focus_previous = _rules_tab.get_path_to(_item_tab)


func _on_close_pressed() -> void:
	closed.emit()
