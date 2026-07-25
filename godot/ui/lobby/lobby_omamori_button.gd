extends Button

# 单侧御守功能按钮：AtlasTexture 裁切素材，根节点继续承载真实 Button 语义。

const ICON_SHEET := preload("res://assets/ui/lobby_stage/side_omamori_icons_transparent.png")
const ICON_REGIONS := [
	Rect2(48, 34, 380, 360),
	Rect2(450, 34, 370, 360),
	Rect2(830, 34, 390, 360),
	Rect2(42, 420, 400, 380),
	Rect2(442, 420, 390, 380),
	Rect2(820, 420, 410, 380),
]

@export_range(0, 5) var icon_index: int = 0
@export var action_text: String = "功能"


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	text = action_text
	tooltip_text = action_text
	var atlas := AtlasTexture.new()
	atlas.atlas = ICON_SHEET
	atlas.region = ICON_REGIONS[icon_index]
	$Icon.texture = atlas
	$Caption.text = action_text
	for child in find_children("*", "Control", true, false):
		(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.05, 0.035, 0.03, 0.72 if state == "normal" else 0.9)
		style.border_color = Color(0.76, 0.12, 0.08, 0.45 if state == "normal" else 0.95)
		style.set_border_width_all(1 if state == "normal" else 2)
		style.set_corner_radius_all(8)
		add_theme_stylebox_override(state, style)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color",
			"font_focus_color", "font_disabled_color"]:
		add_theme_color_override(color_name, Color.TRANSPARENT)
