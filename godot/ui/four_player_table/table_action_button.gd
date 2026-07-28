extends Button

# 牌桌专用动作旗标。根节点保留原生 Button 的点击、焦点与可访问文本；
# Polygon2D/Label 子层只负责原创的斜切旗标和多层字效。

const ACTION_FONT: FontFile = preload(
	"res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")
const TEXT_IVORY := Color("fff4dc")
const SHADOW_BLACK := Color("111016")
const UTILITY_BG := Color("111827e8")
const UTILITY_BORDER := Color("d9b65bcc")

const PALETTES := {
	&"chi": {"base": Color("247a55"), "accent": Color("55d58d")},
	&"pon": {"base": Color("137d9f"), "accent": Color("5fe3ff")},
	&"kan": {"base": Color("6d2a89"), "accent": Color("d66aff")},
	&"win": {"base": Color("a52d1c"), "accent": Color("ffb33f")},
	&"riichi": {"base": Color("9b6b16"), "accent": Color("ffd45c")},
	&"danger": {"base": Color("762b31"), "accent": Color("e66b72")},
	&"item": {"base": Color("176c68"), "accent": Color("58d7c8")},
	&"skip": {"base": Color("36373d"), "accent": Color("dddddd")},
}

var action_kind: StringName = &"skip"
var label_font_size: int = 26

var _rear_ribbon: Polygon2D = null
var _main_ribbon: Polygon2D = null
var _outline: Line2D = null
var _seal_marks: Array[Polygon2D] = []
var _shadow_label: Label = null
var _front_label: Label = null
var _hovered := false
var _held := false
var _last_disabled := false


func _ready() -> void:
	_build_visuals()
	_update_geometry()
	_refresh_visual_state()
	set_process(true)


func configure(label_text: String, kind: StringName) -> void:
	action_kind = kind if PALETTES.has(kind) else &"skip"
	text = label_text
	tooltip_text = label_text
	label_font_size = _font_size_for(label_text)
	set_meta("table_action_kind", action_kind)
	if is_node_ready():
		_sync_labels()
		_refresh_visual_state()


func _build_visuals() -> void:
	if _rear_ribbon != null:
		return
	flat = true
	clip_text = true
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for color_name in [
		"font_color", "font_hover_color", "font_pressed_color",
		"font_focus_color", "font_disabled_color",
	]:
		add_theme_color_override(color_name, Color.TRANSPARENT)

	_rear_ribbon = Polygon2D.new()
	_rear_ribbon.name = "RearRibbon"
	add_child(_rear_ribbon)

	_main_ribbon = Polygon2D.new()
	_main_ribbon.name = "MainRibbon"
	add_child(_main_ribbon)

	_outline = Line2D.new()
	_outline.name = "RibbonOutline"
	_outline.width = 2.0
	_outline.antialiased = true
	add_child(_outline)

	var seal := Node2D.new()
	seal.name = "OriginalSeal"
	add_child(seal)
	for index in range(4):
		var mark := Polygon2D.new()
		mark.name = "Diamond%d" % index
		seal.add_child(mark)
		_seal_marks.append(mark)

	_shadow_label = _make_label("ShadowLabel")
	add_child(_shadow_label)

	_front_label = _make_label("FrontLabel")
	add_child(_front_label)

	mouse_entered.connect(func() -> void:
		_hovered = true
		_refresh_visual_state())
	mouse_exited.connect(func() -> void:
		_hovered = false
		_held = false
		_refresh_visual_state())
	button_down.connect(func() -> void:
		_held = true
		_refresh_visual_state())
	button_up.connect(func() -> void:
		_held = false
		_refresh_visual_state())
	focus_entered.connect(_refresh_visual_state)
	focus_exited.connect(_refresh_visual_state)
	_sync_labels()


func _make_label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_top = -10
	label.offset_bottom = -4
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _sync_labels() -> void:
	if _front_label == null or _shadow_label == null:
		return
	for label in [_shadow_label, _front_label]:
		label.text = text
		label.add_theme_font_override("font", ACTION_FONT)
		label.add_theme_font_size_override("font_size", label_font_size)
	_shadow_label.add_theme_color_override("font_color", SHADOW_BLACK)
	_shadow_label.add_theme_color_override("font_outline_color", SHADOW_BLACK)
	_shadow_label.add_theme_constant_override("outline_size", 5)
	_front_label.add_theme_color_override("font_color", TEXT_IVORY)
	_front_label.add_theme_constant_override("outline_size", 3)


func _font_size_for(label_text: String) -> int:
	if label_text.length() <= 1:
		return 31
	if label_text.length() <= 2:
		return 24
	return 17


static func apply_table_utility_style(button: Button) -> void:
	if button == null:
		return
	button.set_meta("table_utility_button", true)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, _utility_stylebox(state))
	button.add_theme_color_override("font_color", TEXT_IVORY)
	button.add_theme_color_override("font_hover_color", Color("fff8e8"))
	button.add_theme_color_override("font_pressed_color", Color("e6d4a7"))
	button.add_theme_color_override("font_focus_color", Color("fff8e8"))
	button.add_theme_color_override("font_disabled_color", Color("8b8e98"))
	button.add_theme_font_size_override("font_size", 16)


static func _utility_stylebox(state: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UTILITY_BG
	style.border_color = UTILITY_BORDER
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_right = 2
	style.corner_radius_bottom_left = 7
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	match state:
		"hover":
			style.bg_color = Color("1b2940f2")
			style.border_color = Color("f0d27aff")
		"pressed":
			style.bg_color = Color("0b1220f2")
			style.border_color = Color("b98f39dd")
		"focus":
			style.bg_color = Color("162238f2")
			style.border_color = Color("ffe29aff")
		"disabled":
			style.bg_color = Color("10141ca8")
			style.border_color = Color("77705e80")
	return style


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _rear_ribbon != null:
		_update_geometry()


func _process(_delta: float) -> void:
	if disabled != _last_disabled:
		_last_disabled = disabled
		_refresh_visual_state()


func _update_geometry() -> void:
	if _rear_ribbon == null:
		return
	var width := maxf(size.x, custom_minimum_size.x)
	var height := maxf(size.y, custom_minimum_size.y)
	if width <= 0.0 or height <= 0.0:
		return
	var rear := PackedVector2Array([
		Vector2(0, 12), Vector2(11, 7), Vector2(width - 14, 7),
		Vector2(width, 14), Vector2(width - 11, height - 15),
		Vector2(5, height - 15),
	])
	var main := PackedVector2Array([
		Vector2(4, 12), Vector2(17, 5), Vector2(width - 15, 5),
		Vector2(width - 2, 14), Vector2(width - 11, height - 19),
		Vector2(14, height - 19), Vector2(2, height - 25),
	])
	_rear_ribbon.polygon = rear
	_main_ribbon.polygon = main
	var outline_points := main.duplicate()
	outline_points.append(main[0])
	_outline.points = outline_points

	var seal_center := Vector2(width - 20, height * 0.39)
	var offsets := [Vector2(-5, 0), Vector2(5, 0), Vector2(0, -5), Vector2(0, 5)]
	for index in range(_seal_marks.size()):
		var center: Vector2 = seal_center + offsets[index]
		_seal_marks[index].polygon = PackedVector2Array([
			center + Vector2(0, -2.5), center + Vector2(2.5, 0),
			center + Vector2(0, 2.5), center + Vector2(-2.5, 0),
		])


func _refresh_visual_state() -> void:
	if _main_ribbon == null:
		return
	var palette: Dictionary = PALETTES[action_kind]
	var base: Color = palette.base
	var accent: Color = palette.accent
	if disabled:
		base = base.lerp(Color("4a4b50"), 0.62)
		accent = accent.lerp(Color("8a8b90"), 0.68)
	elif _held:
		base = base.darkened(0.18)
		accent = accent.darkened(0.10)
	elif _hovered:
		base = base.lightened(0.12)
		accent = accent.lightened(0.12)
	elif has_focus():
		base = base.lightened(0.06)
		accent = TEXT_IVORY
	_rear_ribbon.color = Color(base, 0.66 if not disabled else 0.34)
	_main_ribbon.color = Color(base, 0.98 if not disabled else 0.58)
	_outline.default_color = accent
	for mark in _seal_marks:
		mark.color = accent
	_front_label.add_theme_color_override("font_outline_color", base.darkened(0.28))
	var text_alpha := 0.48 if disabled else 1.0
	_front_label.modulate = Color(1, 1, 1, text_alpha)
	_shadow_label.modulate = Color(1, 1, 1, text_alpha * 0.9)
