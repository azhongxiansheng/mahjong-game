extends Button

# 大厅横向玩法牌匾：保留原生 Button 输入/焦点/可访问性，图片只提供材质。

const BANNER_SHEET := preload("res://assets/ui/lobby_stage/mode_banner_sheet_transparent.png")
const BANNER_REGIONS := [
	Rect2(150, 44, 950, 226),
	Rect2(150, 294, 950, 232),
	Rect2(150, 545, 950, 242),
]

@export_range(0, 2) var banner_index: int = 0
@export var title: String = ""
@export var subtitle: String = ""

var _visual_tween: Tween = null
var _visual_state: StringName = &"idle"
var _target_scale := Vector2.ONE
var _target_art_modulate := Color.WHITE
var _hovered := false
var _focused := false
var _last_disabled := false


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	text = title
	tooltip_text = "%s｜%s" % [title, subtitle]
	clip_contents = false
	var atlas := AtlasTexture.new()
	atlas.atlas = BANNER_SHEET
	atlas.region = BANNER_REGIONS[banner_index]
	$BannerArt.texture = atlas
	$Copy/Title.text = title
	$Copy/Subtitle.text = subtitle
	for child in find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for color_name in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_disabled_color"]:
		add_theme_color_override(color_name, Color.TRANSPARENT)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	button_down.connect(_set_pressed_visual)
	button_up.connect(_refresh_highlight_state)
	_last_disabled = disabled
	set_process(true)


func _process(_delta: float) -> void:
	if disabled == _last_disabled:
		return
	_last_disabled = disabled
	_refresh_highlight_state()


func get_visual_state() -> StringName:
	return _visual_state


func finish_visual_transition() -> void:
	if _visual_tween != null and _visual_tween.is_valid():
		_visual_tween.kill()
	_visual_tween = null
	scale = _target_scale
	$BannerArt.modulate = _target_art_modulate


func _on_mouse_entered() -> void:
	_hovered = true
	_refresh_highlight_state()


func _on_mouse_exited() -> void:
	_hovered = false
	_refresh_highlight_state()


func _on_focus_entered() -> void:
	_focused = true
	_refresh_highlight_state()


func _on_focus_exited() -> void:
	_focused = false
	_refresh_highlight_state()


func _refresh_highlight_state() -> void:
	if disabled:
		_transition_to(&"disabled", Vector2.ONE, Color(0.55, 0.55, 0.55, 0.75))
	elif _focused:
		_transition_to(&"focused", Vector2(1.025, 1.025), Color(1.08, 1.04, 1.0, 1.0))
	elif _hovered:
		_transition_to(&"hovered", Vector2(1.025, 1.025), Color(1.08, 1.04, 1.0, 1.0))
	else:
		_transition_to(&"idle", Vector2.ONE, Color.WHITE)


func _set_pressed_visual() -> void:
	if not disabled:
		_transition_to(&"pressed", Vector2(0.985, 0.985), Color(1.0, 0.92, 0.88, 1.0), 0.06)


func _transition_to(state: StringName, target_scale: Vector2,
		target_modulate: Color, duration: float = 0.12) -> void:
	if _visual_tween != null and _visual_tween.is_valid():
		_visual_tween.kill()
	_visual_state = state
	_target_scale = target_scale
	_target_art_modulate = target_modulate
	pivot_offset = size * 0.5
	_visual_tween = create_tween().set_parallel(true)
	_visual_tween.tween_property(self, "scale", target_scale, duration)
	_visual_tween.tween_property($BannerArt, "modulate", target_modulate, duration)
