class_name LobbyAudioPopup extends Control

# 大厅右下轻量音量弹层（E1-05 / #229）。
# BGM / SFX 共用；只提供两滑条 + SFX 试听，不含语音 / 静音席 / 举报。

signal closed

const PANEL_W: float = 360.0
const PANEL_H: float = 280.0

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
	for n in [self, _bgm_slider, _sfx_slider, _preview_btn, _close_btn]:
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
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_gui_input)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "AudioPopupPanel"
	panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	panel.anchor_left = 1.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_W - DesignTokens.PANEL_PAD
	panel.offset_top = -PANEL_H - DesignTokens.PANEL_PAD
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
	sb.shadow_size = 12
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var root := VBoxContainer.new()
	root.name = "AudioPopupRoot"
	root.add_theme_constant_override("separation", DesignTokens.GAP_NORMAL)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", DesignTokens.GAP_TIGHT)
	root.add_child(header)

	var title := Label.new()
	title.text = "音量"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", DesignTokens.FONT_SUBTITLE)
	title.add_theme_color_override("font_color", DesignTokens.TEXT_TITLE)
	header.add_child(title)

	_close_btn = DesignTokens.make_button("关闭", DesignTokens.BtnRole.GHOST, Vector2(88, 36))
	_close_btn.name = "AudioPopupCloseButton"
	_close_btn.focus_mode = Control.FOCUS_ALL
	_close_btn.pressed.connect(_on_close_pressed)
	header.add_child(_close_btn)

	root.add_child(_build_slider_block("BGM", true))
	root.add_child(_build_slider_block("SFX", false))

	_preview_btn = DesignTokens.make_button("试听音效", DesignTokens.BtnRole.SECONDARY, Vector2(140, 40))
	_preview_btn.name = "SfxPreviewButton"
	_preview_btn.focus_mode = Control.FOCUS_ALL
	_preview_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview_btn.pressed.connect(_on_preview_pressed)
	root.add_child(_preview_btn)

	_sync_from_settings()


func _build_slider_block(title_text: String, is_bgm: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.GAP_TIGHT)
	col.add_child(row)

	var title := Label.new()
	title.text = title_text
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	title.add_theme_color_override("font_color", DesignTokens.TEXT_PRIMARY)
	row.add_child(title)

	var value_lbl := Label.new()
	value_lbl.custom_minimum_size = Vector2(52, 0)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_lbl.add_theme_font_size_override("font_size", DesignTokens.FONT_BODY)
	value_lbl.add_theme_color_override("font_color", DesignTokens.TEXT_TITLE)
	row.add_child(value_lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 28)
	slider.focus_mode = Control.FOCUS_ALL
	DesignTokens.style_hslider(slider)
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
