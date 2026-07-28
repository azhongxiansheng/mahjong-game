class_name MatchSettlementPanel extends Control

# E2-05（#235）：整场结算覆盖层。
# 挂在现有 PlayableTable 上；仅展示排名与导航按钮，不接 Run。

signal rematch_requested
signal return_lobby_requested

const PANEL_W: int = 520
const PANEL_H: int = 400

var _consumed: bool = false
var _built: bool = false
var _title_label: Label = null
var _rows_host: VBoxContainer = null
var _rematch_btn: Button = null
var _return_btn: Button = null


func _init() -> void:
	name = "MatchSettlementPanel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	set_process_input(true)


func _ready() -> void:
	_ensure_built()


func present(view: Dictionary) -> void:
	_ensure_built()
	_consumed = false
	if _rematch_btn != null:
		_rematch_btn.disabled = false
	if _return_btn != null:
		_return_btn.disabled = false
	if _title_label != null:
		_title_label.text = str(view.get("title", "对局结束"))
	if _rows_host == null:
		return
	for child in _rows_host.get_children():
		child.queue_free()
	var rows: Array = view.get("rows", [])
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = row
		var label := Label.new()
		label.text = "第 %d 名  %s    %d" % [
			int(d.get("rank", 0)),
			str(d.get("name", "")),
			int(d.get("score", 0)),
		]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 20)
		var seat_id: int = int(d.get("seat_id", -1))
		var color := Color(1, 0.85, 0.4) if seat_id == 0 else Color(0.92, 0.92, 0.9)
		label.add_theme_color_override("font_color", color)
		_rows_host.add_child(label)
	if _rematch_btn != null:
		_rematch_btn.grab_focus()


func _ensure_built() -> void:
	if _built:
		return
	_built = true

	var bg := ColorRect.new()
	bg.name = "Backdrop"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.72)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_backdrop_gui_input)
	add_child(bg)

	var panel := Panel.new()
	panel.name = "SettlementModal"
	panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	panel.size = Vector2(PANEL_W, PANEL_H)
	panel.position = Vector2(
		(DT.VIEW_W - PANEL_W) / 2.0,
		(DT.VIEW_H - PANEL_H) / 2.0
	)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.18, 0.98)
	style.border_color = Color("d9b65b8c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 24
	style.shadow_offset = Vector2(0, 12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.position = Vector2(0, 28)
	_title_label.size = Vector2(PANEL_W, 40)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	_title_label.text = "整场结界解除"
	panel.add_child(_title_label)

	_rows_host = VBoxContainer.new()
	_rows_host.name = "RankRows"
	_rows_host.position = Vector2(60, 100)
	_rows_host.size = Vector2(PANEL_W - 120, 180)
	_rows_host.add_theme_constant_override("separation", 12)
	panel.add_child(_rows_host)

	_rematch_btn = Button.new()
	_rematch_btn.name = "RematchButton"
	_rematch_btn.text = "再来一局"
	DT.apply_button_role(_rematch_btn, DT.BtnRole.PRIMARY)
	_rematch_btn.custom_minimum_size = Vector2(160, 44)
	_rematch_btn.position = Vector2(70, PANEL_H - 72)
	_rematch_btn.size = Vector2(160, 44)
	_rematch_btn.pressed.connect(_on_rematch_pressed)
	_rematch_btn.focus_mode = Control.FOCUS_ALL
	panel.add_child(_rematch_btn)

	_return_btn = Button.new()
	_return_btn.name = "ReturnLobbyButton"
	_return_btn.text = "返回大厅"
	DT.apply_button_role(_return_btn, DT.BtnRole.SECONDARY)
	_return_btn.custom_minimum_size = Vector2(160, 44)
	_return_btn.position = Vector2(PANEL_W - 70 - 160, PANEL_H - 72)
	_return_btn.size = Vector2(160, 44)
	_return_btn.pressed.connect(_on_return_pressed)
	_return_btn.focus_mode = Control.FOCUS_ALL
	panel.add_child(_return_btn)
	_rematch_btn.focus_next = _rematch_btn.get_path_to(_return_btn)
	_rematch_btn.focus_previous = _rematch_btn.get_path_to(_return_btn)
	_return_btn.focus_next = _return_btn.get_path_to(_rematch_btn)
	_return_btn.focus_previous = _return_btn.get_path_to(_rematch_btn)


func _on_rematch_pressed() -> void:
	if _consumed:
		return
	_consumed = true
	_set_buttons_disabled(true)
	rematch_requested.emit()


func _on_return_pressed() -> void:
	if _consumed:
		return
	_consumed = true
	_set_buttons_disabled(true)
	return_lobby_requested.emit()


func _set_buttons_disabled(disabled: bool) -> void:
	if _rematch_btn != null:
		_rematch_btn.disabled = disabled
	if _return_btn != null:
		_return_btn.disabled = disabled


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
