class_name SettingsOverlay extends Control

# 大厅与牌桌复用的设置层；只调用既有 SettingsManager setter。

signal closed

const PANEL_W := 520
const PANEL_H := 560
const FPS_PRESETS: Array = [30, 60, 120, 144, 0]
const FPS_LABELS: Array = ["30 FPS", "60 FPS", "120 FPS", "144 FPS", "不限制"]

var _sfx_slider: HSlider = null
var _sfx_value_label: Label = null
var _fps_option: OptionButton = null
var _claim_slider: HSlider = null
var _claim_value_label: Label = null
var _close_btn: Button = null
var _test_btn: Button = null
var _fullscreen_btn: CheckButton = null
var _stats_btn: Button = null
var _done_btn: Button = null
var _closing := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 600


func _ready() -> void:
	_build_ui()
	_wire_focus()
	if _close_btn != null:
		_close_btn.grab_focus()


func close_overlay() -> void:
	_on_close()


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.name = "SettingsBackdrop"
	backdrop.color = Color(DT.BG_BASE.r, DT.BG_BASE.g, DT.BG_BASE.b, DT.MODAL_BG_DIM)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_gui_input)
	add_child(backdrop)
	_register_hook(backdrop)

	var panel := DT.make_centered_panel(PANEL_W, PANEL_H)
	panel.name = "SettingsModal"
	add_child(panel)

	var header := Control.new()
	header.name = "SettingsHeader"
	header.position = Vector2(36, 20)
	header.size = Vector2(PANEL_W - 72, 56)
	panel.add_child(header)
	_register_hook(header)

	var title := Label.new()
	title.text = "结界校准 · 设置"
	title.position = Vector2.ZERO
	title.size = Vector2(330, 52)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	DT.apply_subtitle_style(title)
	header.add_child(title)

	_close_btn = DT.make_button("关闭", DT.BtnRole.GHOST, Vector2(104, 44))
	_close_btn.name = "SettingsCloseButton"
	_close_btn.position = Vector2(header.size.x - 104, 4)
	_close_btn.focus_mode = Control.FOCUS_ALL
	_close_btn.pressed.connect(_on_close)
	header.add_child(_close_btn)
	_register_hook(_close_btn)

	var scroll := ScrollContainer.new()
	scroll.name = "SettingsContentScroll"
	scroll.position = Vector2(36, 88)
	scroll.size = Vector2(PANEL_W - 72, 354)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_register_hook(scroll)

	var content := VBoxContainer.new()
	content.name = "SettingsContent"
	content.custom_minimum_size = Vector2(PANEL_W - 92, 460)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", DT.GAP_NORMAL)
	scroll.add_child(content)

	content.add_child(_section_label("音效音量"))
	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", DT.GAP_NORMAL)
	content.add_child(sfx_row)
	_sfx_slider = HSlider.new()
	_sfx_slider.name = "SettingsSfxSlider"
	_sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sfx_slider.min_value = 0.0
	_sfx_slider.max_value = 1.0
	_sfx_slider.step = 0.01
	_sfx_slider.value = _sm().sfx_volume
	_sfx_slider.focus_mode = Control.FOCUS_ALL
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	DT.style_hslider(_sfx_slider)
	sfx_row.add_child(_sfx_slider)
	_register_hook(_sfx_slider)
	_sfx_value_label = _value_label("%d%%" % int(_sm().sfx_volume * 100))
	sfx_row.add_child(_sfx_value_label)

	var immediate_row := HBoxContainer.new()
	immediate_row.add_theme_constant_override("separation", DT.GAP_NORMAL)
	content.add_child(immediate_row)
	_test_btn = DT.make_button("试听", DT.BtnRole.SECONDARY, Vector2(112, 40))
	_test_btn.name = "SettingsPreviewButton"
	_test_btn.focus_mode = Control.FOCUS_ALL
	_test_btn.pressed.connect(_on_test_pressed)
	immediate_row.add_child(_test_btn)
	_fullscreen_btn = CheckButton.new()
	_fullscreen_btn.name = "SettingsFullscreenButton"
	_fullscreen_btn.text = "全屏"
	_fullscreen_btn.custom_minimum_size = Vector2(130, 40)
	_fullscreen_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fullscreen_btn.focus_mode = Control.FOCUS_ALL
	_fullscreen_btn.button_pressed = _sm().fullscreen
	_fullscreen_btn.toggled.connect(_on_fullscreen_toggled)
	DT.style_check_button(_fullscreen_btn)
	immediate_row.add_child(_fullscreen_btn)

	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", DT.GAP_NORMAL)
	content.add_child(fps_row)
	var fps_label := _section_label("帧率上限")
	fps_label.custom_minimum_size.x = 140
	fps_row.add_child(fps_label)
	_fps_option = OptionButton.new()
	_fps_option.name = "SettingsFpsOption"
	_fps_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fps_option.focus_mode = Control.FOCUS_ALL
	for label in FPS_LABELS:
		_fps_option.add_item(String(label))
	var current_index := FPS_PRESETS.find(int(_sm().framerate_cap))
	_fps_option.selected = current_index if current_index >= 0 else 1
	_fps_option.item_selected.connect(_on_fps_selected)
	DT.style_option_button(_fps_option)
	fps_row.add_child(_fps_option)

	content.add_child(_section_label("鸣牌倒计时"))
	var claim_row := HBoxContainer.new()
	claim_row.add_theme_constant_override("separation", DT.GAP_NORMAL)
	content.add_child(claim_row)
	_claim_slider = HSlider.new()
	_claim_slider.name = "SettingsClaimSlider"
	_claim_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_claim_slider.min_value = 1.0
	_claim_slider.max_value = 15.0
	_claim_slider.step = 0.5
	_claim_slider.value = float(_sm().claim_timeout_sec)
	_claim_slider.focus_mode = Control.FOCUS_ALL
	_claim_slider.value_changed.connect(_on_claim_timeout_changed)
	DT.style_hslider(_claim_slider)
	claim_row.add_child(_claim_slider)
	_claim_value_label = _value_label("%.1fs" % float(_sm().claim_timeout_sec))
	claim_row.add_child(_claim_value_label)

	var hint := Label.new()
	hint.text = "设置即时生效并沿用现有本地持久化；关闭不会撤销。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	DT.apply_caption_style(hint)
	content.add_child(hint)

	var footer := HBoxContainer.new()
	footer.name = "SettingsFooter"
	footer.position = Vector2(36, 474)
	footer.size = Vector2(PANEL_W - 72, 52)
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", DT.GAP_NORMAL)
	panel.add_child(footer)
	_register_hook(footer)
	_stats_btn = DT.make_button("查看战绩", DT.BtnRole.SECONDARY, Vector2(132, 44))
	_stats_btn.name = "SettingsStatsButton"
	_stats_btn.focus_mode = Control.FOCUS_ALL
	_stats_btn.pressed.connect(_on_stats_pressed)
	footer.add_child(_stats_btn)
	_done_btn = DT.make_button("完成", DT.BtnRole.PRIMARY, Vector2(132, 44))
	_done_btn.name = "SettingsDoneButton"
	_done_btn.focus_mode = Control.FOCUS_ALL
	_done_btn.pressed.connect(_on_close)
	footer.add_child(_done_btn)

	DT.popin(panel)


func _register_hook(node: Node) -> void:
	node.unique_name_in_owner = true
	node.owner = self


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	DT.apply_body_style(label)
	return label


func _value_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 68
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	DT.apply_body_style(label)
	return label


func _wire_focus() -> void:
	var controls: Array[Control] = [
		_close_btn, _sfx_slider, _test_btn, _fullscreen_btn, _fps_option,
		_claim_slider, _stats_btn, _done_btn,
	]
	if controls.any(func(control: Control) -> bool: return control == null):
		return
	for index in range(controls.size()):
		var current := controls[index]
		var next := controls[(index + 1) % controls.size()]
		var previous := controls[(index - 1 + controls.size()) % controls.size()]
		current.focus_next = current.get_path_to(next)
		current.focus_previous = current.get_path_to(previous)


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_on_close()


func _on_stats_pressed() -> void:
	var view := StatsView.new()
	view.name = "_stats_view_root"
	get_tree().root.add_child(view)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		_on_close()
		get_viewport().set_input_as_handled()


func _on_sfx_changed(value: float) -> void:
	_sm().set_sfx_volume(value)
	if _sfx_value_label != null:
		_sfx_value_label.text = "%d%%" % int(value * 100)


func _on_claim_timeout_changed(value: float) -> void:
	_sm().set_claim_timeout_sec(value)
	_sm().set_riichi_timeout_sec(value + 1.0)
	if _claim_value_label != null:
		_claim_value_label.text = "%.1fs" % value


func _on_test_pressed() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null:
		audio_manager.play("tile_click")


func _on_fullscreen_toggled(enabled: bool) -> void:
	_sm().set_fullscreen(enabled)


func _on_fps_selected(index: int) -> void:
	if index >= 0 and index < FPS_PRESETS.size():
		_sm().set_framerate_cap(int(FPS_PRESETS[index]))


func _on_close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()


func _sm() -> Node:
	return get_node("/root/SettingsManager")
