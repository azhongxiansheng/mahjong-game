class_name LobbyCodexOverlay extends Control

# 大厅单一全屏资料馆（E1-05 / #229）。
# 角色 / 道具 / 规则三入口复用本实例；页签切换复用同一 CodexContent。

signal closed

const PAGE_CHARACTERS := &"characters"
const PAGE_ITEMS := &"items"
const PAGE_RULES := &"rules"

var _current_page: StringName = PAGE_CHARACTERS
var _catalog: LobbyCodexCatalog = LobbyCodexCatalog.new()
var _content: VBoxContainer = null
var _content_host: ScrollContainer = null
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

	var panel := PanelContainer.new()
	panel.name = "CodexPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = DesignTokens.PANEL_PAD
	panel.offset_top = DesignTokens.PANEL_PAD
	panel.offset_right = -DesignTokens.PANEL_PAD
	panel.offset_bottom = -DesignTokens.PANEL_PAD
	var sb := StyleBoxFlat.new()
	sb.bg_color = DesignTokens.SURFACE_PANEL
	sb.border_color = DesignTokens.BORDER_GOLD
	sb.set_border_width_all(DesignTokens.CARD_BORDER)
	sb.set_corner_radius_all(DesignTokens.CARD_RADIUS)
	sb.content_margin_left = DesignTokens.GAP_LOOSE
	sb.content_margin_right = DesignTokens.GAP_LOOSE
	sb.content_margin_top = DesignTokens.GAP_NORMAL
	sb.content_margin_bottom = DesignTokens.GAP_NORMAL
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 16
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var root := VBoxContainer.new()
	root.name = "CodexRoot"
	root.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(root)

	root.add_child(_build_header())
	root.add_child(_build_tabs())

	_content_host = ScrollContainer.new()
	_content_host.name = "CodexContent"
	_content_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_host.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_content_host)

	_content = VBoxContainer.new()
	_content.name = "CodexContentList"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
	_content_host.add_child(_content)

	_set_page(PAGE_CHARACTERS)


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.name = "CodexHeader"
	header.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)

	var title := Label.new()
	title.name = "CodexTitle"
	title.text = "资料馆"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", DesignTokens.FONT_TITLE)
	title.add_theme_color_override("font_color", DesignTokens.TEXT_TITLE)
	header.add_child(title)

	_close_btn = DesignTokens.make_button("关闭", DesignTokens.BtnRole.PRIMARY, Vector2(120, DesignTokens.BUTTON_H))
	_close_btn.name = "CodexCloseButton"
	_close_btn.focus_mode = Control.FOCUS_ALL
	_close_btn.pressed.connect(_on_close_pressed)
	header.add_child(_close_btn)
	return header


func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.name = "CodexTabs"
	row.add_theme_constant_override("separation", DesignTokens.GAP_TIGHT)
	_tab_group = ButtonGroup.new()

	_character_tab = _make_tab("CodexCharacterTab", "角色", PAGE_CHARACTERS)
	_item_tab = _make_tab("CodexItemTab", "道具", PAGE_ITEMS)
	_rules_tab = _make_tab("CodexRulesTab", "规则", PAGE_RULES)
	row.add_child(_character_tab)
	row.add_child(_item_tab)
	row.add_child(_rules_tab)
	return row


func _make_tab(btn_name: String, text: String, page: StringName) -> Button:
	var btn := DesignTokens.make_button(text, DesignTokens.BtnRole.SECONDARY, Vector2(140, DesignTokens.BUTTON_H))
	btn.name = btn_name
	btn.focus_mode = Control.FOCUS_ALL
	btn.toggle_mode = true
	btn.button_group = _tab_group
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
	if _content == null:
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.free()
	match _current_page:
		PAGE_ITEMS:
			_fill_items()
		PAGE_RULES:
			_fill_rules()
		_:
			_fill_characters()


func _fill_characters() -> void:
	for row in _catalog.characters():
		var card := _make_entry_card()
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", DesignTokens.GAP_TIGHT)
		card.add_child(body)

		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
		body.add_child(top)

		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(72, 96)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var path := String(row.get("portrait_path", ""))
		if path != "" and ResourceLoader.exists(path):
			portrait.texture = load(path) as Texture2D
		top.add_child(portrait)

		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_theme_constant_override("separation", 4)
		top.add_child(copy)

		copy.add_child(_label(String(row.get("display_name", "")), DesignTokens.FONT_SUBTITLE, DesignTokens.TEXT_TITLE, false))
		var affinities: Array = row.get("affinity_labels", [])
		var affinity_text := " / ".join(PackedStringArray(affinities))
		if affinity_text != "":
			copy.add_child(_label(affinity_text, DesignTokens.FONT_CAPTION, DesignTokens.TEXT_MUTED, false))
		copy.add_child(_label(String(row.get("description", "")), DesignTokens.FONT_BODY, DesignTokens.TEXT_PRIMARY, true))
		var ability_name := String(row.get("ability_name", ""))
		if ability_name != "":
			copy.add_child(_label(ability_name, DesignTokens.FONT_BODY, DesignTokens.TEXT_TITLE, false))
			copy.add_child(_label(String(row.get("ability_description", "")), DesignTokens.FONT_CAPTION, DesignTokens.TEXT_PRIMARY, true))
		_content.add_child(card)


func _fill_items() -> void:
	for row in _catalog.items():
		var card := _make_entry_card()
		var body := HBoxContainer.new()
		body.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
		card.add_child(body)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(56, 56)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icon_path := String(row.get("icon_path", ""))
		if icon_path != "" and ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path) as Texture2D
		body.add_child(icon)

		var copy := VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		copy.add_theme_constant_override("separation", 4)
		body.add_child(copy)

		copy.add_child(_label(String(row.get("display_name", "")), DesignTokens.FONT_SUBTITLE, DesignTokens.TEXT_TITLE, false))
		var meta := "%s · %s" % [String(row.get("category", "")), String(row.get("rarity_label", ""))]
		copy.add_child(_label(meta, DesignTokens.FONT_CAPTION, DesignTokens.TEXT_MUTED, false))
		copy.add_child(_label(String(row.get("description", "")), DesignTokens.FONT_BODY, DesignTokens.TEXT_PRIMARY, true))
		_content.add_child(card)


func _fill_rules() -> void:
	for row in _catalog.rules():
		var card := _make_entry_card()
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", DesignTokens.GAP_TIGHT)
		card.add_child(body)
		body.add_child(_label(String(row.get("title", "")), DesignTokens.FONT_SUBTITLE, DesignTokens.TEXT_TITLE, false))
		body.add_child(_label(String(row.get("body", "")), DesignTokens.FONT_BODY, DesignTokens.TEXT_PRIMARY, true))
		_content.add_child(card)


func _make_entry_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.12, 0.92)
	sb.border_color = DesignTokens.BORDER_GOLD_SOFT
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = DesignTokens.GAP_NORMAL
	sb.content_margin_right = DesignTokens.GAP_NORMAL
	sb.content_margin_top = DesignTokens.GAP_TIGHT
	sb.content_margin_bottom = DesignTokens.GAP_TIGHT
	card.add_theme_stylebox_override("panel", sb)
	return card


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
	# 关闭 ↔ 三页签 显式闭环，Tab/Shift+Tab 不落到底层。
	if _close_btn == null or _character_tab == null or _item_tab == null or _rules_tab == null:
		return
	if not is_inside_tree():
		return
	_close_btn.focus_next = _close_btn.get_path_to(_character_tab)
	_character_tab.focus_next = _character_tab.get_path_to(_item_tab)
	_item_tab.focus_next = _item_tab.get_path_to(_rules_tab)
	_rules_tab.focus_next = _rules_tab.get_path_to(_close_btn)

	_close_btn.focus_previous = _close_btn.get_path_to(_rules_tab)
	_character_tab.focus_previous = _character_tab.get_path_to(_close_btn)
	_item_tab.focus_previous = _item_tab.get_path_to(_character_tab)
	_rules_tab.focus_previous = _rules_tab.get_path_to(_item_tab)


func _on_close_pressed() -> void:
	closed.emit()
