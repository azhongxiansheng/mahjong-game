extends Control

var _label: Label


func _ready() -> void:
	name = "CharacterStatusBadge"
	position = Vector2(1180.0, 8.0)
	size = Vector2(210.0, 32.0)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	set_status({})


func set_status(status: Dictionary) -> void:
	if _label == null:
		return
	var text := String(status.get("text", ""))
	visible = not text.is_empty()
	_label.text = text
	_label.add_theme_color_override(
		"font_color", status.get("color", Color(0.66, 0.63, 0.78)))


func status_text() -> String:
	return _label.text if _label != null else ""


func _build() -> void:
	_label = Label.new()
	_label.name = "StatusText"
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_constant_override("outline_size", 2)
	_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.95))
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.055, 0.045, 0.09, 0.9)
	panel.border_color = Color(0.48, 0.43, 0.63, 0.88)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	_label.add_theme_stylebox_override("normal", panel)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
