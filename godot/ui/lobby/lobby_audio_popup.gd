class_name LobbyAudioPopup extends Control

# 大厅右下轻量音量弹层（E1-05 / #229）。
# BGM / SFX 共用；只提供两滑条 + SFX 试听，不含语音 / 静音席 / 举报。

signal closed

const PANEL_W: float = 350.0
const PANEL_H: float = 178.0
const PANEL_RIGHT_GAP: float = 132.0
const PANEL_BOTTOM_GAP: float = 88.0

var _panel: PanelContainer = null
var _inner: PanelContainer = null
var _bgm_slider: HSlider = null
var _sfx_slider: HSlider = null
var _bgm_value: Label = null
var _sfx_value: Label = null
var _preview_btn: Button = null
var _close_btn: Button = null
var _built: bool = false


func _init() -> void:
	name = "LobbyAudioPopup"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func _ready() -> void:
	_wire_focus_graph()


func get_hook_nodes() -> Array[Node]:
	var nodes: Array[Node] = []
	for n in [self, _panel, _inner, _bgm_slider, _sfx_slider, _preview_btn, _close_btn]:
		if n != null:
			nodes.append(n)
	return nodes


func open_popup() -> void:
	_sync_from_settings()
	_wire_focus_graph()
	if _close_btn:
		_close_btn.grab_focus()


func _build_ui() -> void:
	if _built:
		return
	_built = true

	var dim := ColorRect.new()
	dim.name = "AudioPopupDim"
	dim.color = Color(0.04, 0.015, 0.01, 0.28)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_gui_input)
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.name = "AudioPopupPanel"
	_panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	_panel.anchor_left = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_left = -PANEL_W - PANEL_RIGHT_GAP
	_panel.offset_top = -PANEL_H - PANEL_BOTTOM_GAP
	_panel.offset_right = -PANEL_RIGHT_GAP
	_panel.offset_bottom = -PANEL_BOTTOM_GAP
	_panel.add_theme_stylebox_override("panel", DesignTokens.make_lobby_texture_style(
		DesignTokens.LOBBY_OMAMORI_CASE, 38, 44, 38, 34, 22, 8
	))
	add_child(_panel)

	_inner = PanelContainer.new()
	_inner.name = "AudioWashiInner"
	_inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inner.add_theme_stylebox_override("panel", DesignTokens.make_lobby_texture_style(
		DesignTokens.LOBBY_WASHI_PANEL, 28, 16, 28, 16, 16, 6
	))
	_panel.add_child(_inner)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 4)
	content_margin.add_theme_constant_override("margin_top", 12)
	content_margin.add_theme_constant_override("margin_right", 4)
	content_margin.add_theme_constant_override("margin_bottom", 4)
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inner.add_child(content_margin)

	var root := VBoxContainer.new()
	root.name = "AudioPopupRoot"
	root.add_theme_constant_override("separation", 6)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", DesignTokens.GAP_TIGHT)
	root.add_child(header)

	var title := Label.new()
	title.text = "音量"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", DesignTokens.LOBBY_CINNABAR)
	header.add_child(title)

	_preview_btn = DesignTokens.make_button("试听", DesignTokens.BtnRole.SECONDARY, Vector2(76, 34))
	_preview_btn.name = "SfxPreviewButton"
	_preview_btn.focus_mode = Control.FOCUS_ALL
	DesignTokens.apply_lobby_material_button(_preview_btn)
	_preview_btn.custom_minimum_size.y = 34
	_preview_btn.pressed.connect(_on_preview_pressed)
	header.add_child(_preview_btn)

	_close_btn = DesignTokens.make_button("关闭", DesignTokens.BtnRole.GHOST, Vector2(76, 34))
	_close_btn.name = "AudioPopupCloseButton"
	_close_btn.focus_mode = Control.FOCUS_ALL
	DesignTokens.apply_lobby_material_button(_close_btn, true)
	_close_btn.custom_minimum_size.y = 34
	_close_btn.pressed.connect(_on_close_pressed)
	header.add_child(_close_btn)

	var slider_row := HBoxContainer.new()
	slider_row.name = "AudioSliderRow"
	slider_row.add_theme_constant_override("separation", 14)
	slider_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(slider_row)
	slider_row.add_child(_build_slider_block("BGM", true))
	slider_row.add_child(_build_slider_block("SFX", false))

	_sync_from_settings()


func _build_slider_block(title_text: String, is_bgm: bool) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.GAP_TIGHT)
	col.add_child(row)

	var title := Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	title.add_theme_color_override("font_color", DesignTokens.LOBBY_INK)
	row.add_child(title)

	var value_lbl := Label.new()
	value_lbl.custom_minimum_size = Vector2(52, 0)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	value_lbl.add_theme_color_override("font_color", DesignTokens.LOBBY_CINNABAR)
	row.add_child(value_lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 28)
	slider.focus_mode = Control.FOCUS_ALL
	DesignTokens.style_lobby_material_slider(slider)
	col.add_child(slider)

	if is_bgm:
		slider.name = "BgmSlider"
		_bgm_slider = slider
		_bgm_value = value_lbl
		slider.value_changed.connect(_on_bgm_changed)
	else:
		slider.name = "SfxSlider"
		_sfx_slider = slider
		_sfx_value = value_lbl
		slider.value_changed.connect(_on_sfx_changed)
	return col


func _sync_from_settings() -> void:
	var sm := _sm()
	if sm == null:
		return
	if _bgm_slider:
		_bgm_slider.set_value_no_signal(float(sm.bgm_volume))
		_update_value_label(_bgm_value, float(sm.bgm_volume))
	if _sfx_slider:
		_sfx_slider.set_value_no_signal(float(sm.sfx_volume))
		_update_value_label(_sfx_value, float(sm.sfx_volume))


func _update_value_label(lbl: Label, v: float) -> void:
	if lbl:
		lbl.text = "%d%%" % int(round(v * 100.0))


func _on_bgm_changed(v: float) -> void:
	var sm := _sm()
	if sm:
		sm.set_bgm_volume(v)
	_update_value_label(_bgm_value, v)


func _on_sfx_changed(v: float) -> void:
	var sm := _sm()
	if sm:
		sm.set_sfx_volume(v)
	_update_value_label(_sfx_value, v)


func _on_preview_pressed() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("play"):
		am.play("button_click")


func _on_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_close_pressed()


func _wire_focus_graph() -> void:
	# 关闭 → BGM → SFX → 试听 → 关闭 显式闭环。
	if _close_btn == null or _bgm_slider == null or _sfx_slider == null or _preview_btn == null:
		return
	if not is_inside_tree():
		return
	_close_btn.focus_next = _close_btn.get_path_to(_bgm_slider)
	_bgm_slider.focus_next = _bgm_slider.get_path_to(_sfx_slider)
	_sfx_slider.focus_next = _sfx_slider.get_path_to(_preview_btn)
	_preview_btn.focus_next = _preview_btn.get_path_to(_close_btn)

	_close_btn.focus_previous = _close_btn.get_path_to(_preview_btn)
	_bgm_slider.focus_previous = _bgm_slider.get_path_to(_close_btn)
	_sfx_slider.focus_previous = _sfx_slider.get_path_to(_bgm_slider)
	_preview_btn.focus_previous = _preview_btn.get_path_to(_sfx_slider)


func _on_close_pressed() -> void:
	closed.emit()


func _sm() -> Node:
	# _init 时尚未入树，不能走 Node.get_node 绝对路径
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("SettingsManager")
